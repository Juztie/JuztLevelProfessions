local _, JLP = ...
-- Advisory source-backed, bounded 1-225 purchase estimates. Never crafting authority.
local P={contract="forever-secondary-planner-v1",nativeDispatchAllowed=false,
    executionEligible=false,persisted=false,requiresLiveQA=false}
local function nat(v)
    v=tonumber(v)
    if not v or v~=v or v<0 or v==math.huge then return 0 end
    return math.floor(v)
end
local function qualifiedStock(v)
    return type(v)=="number" and v==v and v>=0 and v<math.huge and
        v==math.floor(v) and v or nil
end
local function stockStale(observation)
    return observation.snapshotStale==true or observation.bankStale==true or
        observation.freshness=="STALE"
end
local function valid(d)
    if type(d)~="table" or type(d.steps)~="table" or type(d.guideURL)~="string" or not d.guideURL:find("https://www.wowhead.com/forever/",1,true) then return false end
    local endAt=1
    for _,s in ipairs(d.steps) do
        if s.skillMin~=endAt or nat(s.skillMax)<=endAt or nat(s.estimatedCrafts)<1 or type(s.materials)~="table" or #s.materials==0 then return false end
        for _,mat in ipairs(s.materials) do
            if nat(mat.itemID)<1 or nat(mat.quantity)<1 or type(mat.name)~="string" then return false end
        end
        endAt=s.skillMax
    end
    return endAt==d.coverageEnd
end
local function recipeEvidence(key,data)
    local catalog=JLP.data and JLP.data.foreverSecondaryRecipeEvidence
    local rows=catalog and catalog.professions and catalog.professions[key]
    if type(rows)~="table" or #rows~=#data.steps then return nil,"RECIPE_EVIDENCE_INCOMPLETE" end
    for i,sourceStep in ipairs(data.steps) do
        local proof=rows[i]
        if not proof or proof.recipe~=sourceStep.recipe or type(proof.recipeID)~="number" or proof.recipeID<1 or
           type(proof.outputQuantity)~="number" or proof.outputQuantity<1 or
           type(proof.evidenceURL)~="string" or not proof.evidenceURL:find("wowhead.com/forever/spell="..tostring(proof.recipeID),1,true) or
           type(proof.materials)~="table" or #proof.materials==0 then return nil,"RECIPE_EVIDENCE_MISMATCH" end
        local seen={}
        for _,mat in ipairs(proof.materials) do
            if type(mat.itemID)~="number" or mat.itemID<1 or mat.itemID~=math.floor(mat.itemID) or
               type(mat.quantity)~="number" or mat.quantity<1 or mat.quantity~=math.floor(mat.quantity) or
               type(mat.name)~="string" or mat.name=="" or seen[mat.itemID] then
                return nil,"RECIPE_REAGENT_INVALID"
            end
            seen[mat.itemID]=true
        end
        -- Existing guide ingredient IDs remain audited, but public spells are authoritative on amounts.
        for _,m in ipairs(sourceStep.materials) do
            if not seen[m.itemID] then return nil,"GUIDE_REAGENT_REFERENCE_CONFLICT" end
        end
    end
    return rows
end
-- Exact public access references supplement the already qualified 1-225 guide.
-- The source-facing NPC/quest IDs are NOT client-observed vendor stock,
-- learned-state, travel permission or executable actions.
local function verifiedCookingGates(data)
    if type(data)~="table" or type(data.gates)~="table" then return nil,"ACCESS_GATES_UNAVAILABLE" end
    local expert,artisan=data.gates[1],data.gates[2]
    if not expert or expert.kind~="VENDOR_BOOK" or expert.skill~=150 or
       expert.itemID~=16072 or expert.requiredCookingSkillToUse~=125 or
       expert.itemSourceURL~="https://www.wowhead.com/forever/item=16072/expert-cookbook" or
       expert.vendorStock~="UNKNOWN" or expert.routeEligible~=false then
        return nil,"EXPERT_COOKBOOK_EVIDENCE_CONFLICT" end
    for faction,expected in pairs({ALLIANCE=3955,HORDE=12033}) do
        local vendor=expert.verifiedVendors and expert.verifiedVendors[faction]
        if not vendor or vendor.npcID~=expected or
           vendor.faction~=(faction=="HORDE" and "Horde" or "Alliance") or
           vendor.npcSourceURL~=("https://www.wowhead.com/forever/npc="..expected.."/"..(faction=="HORDE" and "wulan" or "shandrina")) or
           type(vendor.x)~="number" or type(vendor.y)~="number" then
            return nil,"EXPERT_VENDOR_IDENTITY_CONFLICT" end
    end
    if not artisan or artisan.kind~="ARTISAN_QUEST" or artisan.skill~=225 or
       artisan.characterLevel~=35 or artisan.questID~=6610 or artisan.npcID~=8125 or
       artisan.questSourceURL~="https://www.wowhead.com/forever/quest=6610/clamlette-surprise" or
       artisan.npcSourceURL~="https://www.wowhead.com/forever/npc=8125/dirge-quikcleave" or
       artisan.routeEligible~=false or artisan.completion~="UNVERIFIED" or
       artisan.requirementQuantitiesEvidence~="FOREVER_NPC_PUBLIC_COMMENTS_NOT_SERVER_ATTESTED" then
        return nil,"ARTISAN_QUEST_IDENTITY_CONFLICT" end
    local required={{12207,12},{7974,10},{8932,20}}
    if type(artisan.requirements)~="table" or #artisan.requirements~=#required then
        return nil,"ARTISAN_QUEST_MATERIALS_CONFLICT" end
    for i,values in ipairs(required) do
        local r=artisan.requirements[i]
        if not r or r.itemID~=values[1] or r.quantity~=values[2] then
            return nil,"ARTISAN_QUEST_MATERIALS_CONFLICT" end
    end
    return true
end
function P:GetData(key)
    local catalog=JLP.data and JLP.data.foreverSecondaryLeveling
    local data=catalog and catalog.professions and catalog.professions[key]
    local reg=JLP:GetModule("ProfessionRegistry")
    local def=reg and reg:Get(key)
    if not data or not def or tonumber(data.skillLineID)~=tonumber(def.skillLineID) then return nil,"SECONDARY_REFERENCE_UNAVAILABLE" end
    if not valid(data) then return nil,"SECONDARY_REFERENCE_INVALID" end
    -- Supplemental public NPC/quest proof cannot veto independently verified
    -- recipes, materials and guide skill bands. A conflicting access reference
    -- is not approved; Build exposes its own UNKNOWN state without forwarding it.
    local gateReason
    if key=="COOKING" then
        local validGates,why=verifiedCookingGates(data)
        if not validGates then gateReason=why end
    end
    local rows,reason=recipeEvidence(key,data)
    if not rows then return nil,reason end
    return data,gateReason
end
function P:Build(key,skill,options)
    options=type(options)=="table" and options or {}
    local data,accessReason=self:GetData(key)
    if not data then return nil,accessReason end
    local authoritative=assert(recipeEvidence(key,data))
    skill=tonumber(skill)
    if not skill then return nil,"SKILL_UNAVAILABLE" end
    skill=math.max(1,nat(skill))
    local inv=JLP:GetModule("Inventory")
    local result={contract=self.contract,professionKey=key,skill=skill,coverageEnd=data.coverageEnd,
        sourceURL=data.guideURL,estimated=true,completeRoute=false,
        amountsAreGuideEstimates=true,withinBandQuantityNotProRated=true,
        partialShoppingList=false,guideShoppingListOriginallyIncomplete=not data.shoppingListCompleteForListedRoute,
        missingMaterials=nil,sourceNote=data.notes,
        recipeEvidenceState="WOWHEAD_FOREVER_SPELL_VERIFIED",allListedReagentsVerified=true,
        nativeDispatchAllowed=false,executionEligible=false,
        currentStep=nil,steps={},materials={},gates={},pendingCraftsEstimate=0}
    local byID={}
    for ordinal,s in ipairs(data.steps) do
        local proof=authoritative[ordinal]
        if skill<s.skillMax then
            local active=skill>=s.skillMin
            if active then result.currentStep=s end
            result.steps[#result.steps+1]={skillMin=s.skillMin,skillMax=s.skillMax,
                recipe=s.recipe,estimatedCrafts=s.estimatedCrafts,active=active,
                fullBandEstimate=true,accessGate=s.accessGate,recipeID=proof.recipeID,
                recipeSourceURL=proof.evidenceURL,outputQuantity=proof.outputQuantity,
                recipeEvidenceState="WOWHEAD_FOREVER_SPELL_VERIFIED"}
            result.pendingCraftsEstimate=result.pendingCraftsEstimate+s.estimatedCrafts
            for _,mat in ipairs(proof.materials) do
                local row=byID[mat.itemID]
                if not row then
                    row={itemID=mat.itemID,name=mat.name,source=mat.source,guideEstimate=0,
                        sourceURL=mat.evidenceURL,recipeBands={}}
                    byID[mat.itemID]=row
                    result.materials[#result.materials+1]=row
                end
                row.guideEstimate=row.guideEstimate+nat(mat.quantity)*nat(s.estimatedCrafts)
                -- Source-qualified recipe attribution, not a new recipe or
                -- a native craftability assertion. Keep original guide bands.
                row.recipeBands[#row.recipeBands+1]={recipe=s.recipe,recipeID=proof.recipeID,
                    skillMin=s.skillMin,skillMax=s.skillMax,sourceURL=proof.evidenceURL,
                    perCraft=mat.quantity,craftsEstimate=s.estimatedCrafts}
            end
        end
    end
    for _,g in ipairs((key=="COOKING" and accessReason) and {} or (data.gates or {})) do
        if skill<=g.skill then
            result.gates[#result.gates+1]=g
        end
    end
    -- Access instructions remain independent from the selected craft band.
    -- Show Expert book and Artisan quest as read-only references even at 225+,
    -- without inventing learned, merchant-stock or quest-completion state.
    if key=="COOKING" then
        if accessReason then
            result.accessReferences=nil
            result.accessReferenceState="ACCESS_EVIDENCE_UNQUALIFIED"
        else
            result.accessReferences=data.gates
            result.accessReferenceState="WOWHEAD_FOREVER_PUBLIC_NOT_LIVE"
        end
        result.accessReferenceReason=accessReason
    end
    -- 225+ discovery references use the existing 70450 recipe catalogue.
    -- Unknown outputs/yields, learning and acquisition remain UNKNOWN; no
    -- fabricated crafts, new parallel catalogue or native authorization.
    if key=="COOKING" and skill>=225 then
        result.advancedReferences={}
        result.advancedReferenceState="CLIENT_CATALOGUE_UNAVAILABLE"
        local catalogue=JLP:GetModule("Build70450RecipeCatalogue")
        if catalogue and type(catalogue.GetRecipe)=="function" then
            local incomplete=false
            local seen={}
            for _,hint in ipairs(data.advancedCookingReferences or {}) do
                local spell=hint and hint.spellID
                local row=type(spell)=="number" and catalogue:GetRecipe("COOKING",spell,70450)
                if type(hint)~="table" or type(hint.name)~="string" or
                    type(hint.guideMinimumSkill)~="number" or
                    hint.guideMinimumSkill<225 or hint.guideMinimumSkill>300 or
                    seen[spell] or type(row)~="table" or row.spellID~=spell or
                    row.professionKey~="COOKING" or row.skillLineID~=185 or
                    row.sourceBuild~=70450 or row.name~=hint.name or
                    row.recordKind~="RECIPE_CANDIDATE" or
                    type(row.reagents)~="table" or #row.reagents==0 or
                    row.nativeDispatchAllowed~=false or row.executionEligible~=false then
                    incomplete=true
                else
                    local qualified=true
                    for _,r in ipairs(row.reagents) do
                        if type(r.itemID)~="number" or r.itemID<1 or
                           type(r.quantity)~="number" or r.quantity<1 then qualified=false end
                    end
                    if not qualified then
                        incomplete=true
                    else
                        seen[spell]=true
                        -- Public spell page may prove a visible base output count.
                        -- Validate both the expected CLIENT item identity and
                        -- exact source URL. A conflict downgrades ONLY the yield
                        -- field, not the independently qualified reagents/recipe.
                        local publicYield=nil
                        local yieldState="NOT_INDIVIDUALLY_VERIFIED"
                        if hint.publicBaseOutputQuantity~=nil or
                            hint.publicOutputItemID~=nil or hint.publicOutputURL~=nil then
                            local exact="https://www.wowhead.com/forever/spell="..tostring(spell).."/"
                            if type(hint.publicBaseOutputQuantity)=="number" and
                                hint.publicBaseOutputQuantity==math.floor(hint.publicBaseOutputQuantity) and
                                hint.publicBaseOutputQuantity>0 and hint.publicBaseOutputQuantity<1000 and
                                type(hint.publicOutputItemID)=="number" and
                                type(row.outputs)=="table" and #row.outputs==1 and
                                row.outputs[1].itemID==hint.publicOutputItemID and
                                type(hint.publicOutputURL)=="string" and
                                hint.publicOutputURL:sub(1,#exact)==exact and
                                hint.publicOutputURL:len()>#exact then
                                publicYield=hint.publicBaseOutputQuantity
                                yieldState="WOWHEAD_FOREVER_VISIBLE_BASE_OUTPUT_NOT_LIVE"
                            else
                                yieldState="PUBLIC_YIELD_EVIDENCE_CONFLICT"
                            end
                        end
                        result.advancedReferences[#result.advancedReferences+1]={
                            professionKey="COOKING",skillLineID=185,spellID=spell,
                            name=row.name,sourceBuild=70450,
                            sourceURL=data.guideURL,guideMinimumSkill=hint.guideMinimumSkill,
                            guideMinimumState="PUBLIC_GUIDE_REFERENCE_NOT_LIVE",
                            rawMinSkillLineRank=row.rawMinSkillLineRank,
                            rawYellowThreshold=row.rawYellowThreshold,
                            rawGreyThreshold=row.rawGreyThreshold,
                            thresholdState="RAW_70450_CLIENT_NOT_ORANGE_GREEN_PROOF",
                            reagentState=row.reagentState,reagents=row.reagents,
                            outputs=row.outputs,outputQuantityVerified=false,
                            publicBaseOutputQuantity=publicYield,
                            publicOutputQuantityState=yieldState,
                            publicOutputSourceURL=publicYield and hint.publicOutputURL or nil,
                            learnedState="UNKNOWN",acquisitionState="UNKNOWN",
                            estimatedCrafts=nil,readOnly=true,
                            nativeDispatchAllowed=false,executionEligible=false}
                    end
                end
            end
            result.advancedReferenceState=incomplete and
                "PARTIAL_SOURCE_UNAVAILABLE" or "QUALIFIED_70450_READ_ONLY"
        end
    end
    -- P0-207: a bounded, *non-executable* Cooking 225-300 reference step.
    -- A public minimum identifies eligible research candidates, NOT a
    -- learned recipe, verified orange/yellow curve or sufficient skill-up plan.
    -- No future output is credited to the actual material ledger.
    if key=="COOKING" and skill>=225 and skill<300 then
        local candidate
        for _,r in ipairs(result.advancedReferences or {}) do
            if type(r.guideMinimumSkill)=="number" and r.guideMinimumSkill<=skill and
                r.reagentState and type(r.reagents)=="table" and #r.reagents>0 then
                -- Prefer individually sourced output identities, then a stable
                -- spell ordering. This is a reference choice, not optimality.
                local a=r.publicOutputQuantityState=="WOWHEAD_FOREVER_VISIBLE_BASE_OUTPUT_NOT_LIVE"
                local b=candidate and candidate.publicOutputQuantityState=="WOWHEAD_FOREVER_VISIBLE_BASE_OUTPUT_NOT_LIVE"
                if not candidate or r.guideMinimumSkill>candidate.guideMinimumSkill or
                    (r.guideMinimumSkill==candidate.guideMinimumSkill and a and not b) or
                    (r.guideMinimumSkill==candidate.guideMinimumSkill and a==b and r.spellID<candidate.spellID) then
                    candidate=r
                end
            end
        end
        if candidate then
            local step={contract="JLP-COOKING-ADVANCED-ADVISORY-207",
                professionKey="COOKING",skill=skill,recipeID=candidate.spellID,
                recipe=candidate.name,guideMinimumSkill=candidate.guideMinimumSkill,
                recipeSourceURL=candidate.sourceURL,
                guideWindowBasis="PUBLIC_FOREVER_MINIMUM_NOT_SKILLUP_CURVE",
                selectionBasis="DETERMINISTIC_REFERENCE_NOT_OPTIMIZATION",
                learnedState="UNKNOWN",artisanQuestStatus="UNKNOWN",
                estimatedCrafts=nil,expectedCrafts=nil,skillUpChance=nil,
                expectedOutput=nil,materialBudget=nil,materials={},
                nativeDispatchAllowed=false,executionEligible=false,
                navigationStatus="LOCATION_UNVERIFIED",readOnly=true,
                replanAfter={"SKILL_CHANGE","RECIPE_LEARNED","INVENTORY_OBSERVED",
                    "CRAFT_EVENT_RECEIPT","PROFESSION_CHANGED","RELOAD"}}
            local seen={}
            local valid=true;local anyUnknown=false;local ready=true
            for _,mat in ipairs(candidate.reagents) do
                if type(mat.itemID)~="number" or mat.itemID<1 or
                    type(mat.quantity)~="number" or mat.quantity<1 or
                    mat.quantity~=math.floor(mat.quantity) or seen[mat.itemID] then
                    valid=false;break
                end
                seen[mat.itemID]=true
                local observation=options.inventoryByItemID and options.inventoryByItemID[mat.itemID]
                if type(observation)~="table" then
                    observation=inv and inv.GetOwned and inv:GetOwned(mat.itemID) or {}
                end
                local n=qualifiedStock(observation.bags)
                -- Bank-cache staleness does not invalidate a separately
                -- observed fresh bag count; only bag/session staleness does.
                local known=observation.bagKnown==true and n~=nil and
                    observation.snapshotStale~=true and observation.freshness~="STALE"
                if not known then anyUnknown=true;ready=false
                elseif n<mat.quantity then ready=false end
                step.materials[#step.materials+1]={itemID=mat.itemID,
                    perCraft=mat.quantity,bagsKnown=known,
                    bags=known and n or nil,
                    missing=known and math.max(0,mat.quantity-n) or nil,
                    quantityAuthority="HISTORICAL_DB70450_PER_CRAFT",
                    nativeDispatchAllowed=false,readOnly=true}
            end
            if valid then
                step.reagentStatus="DB70450_REFERENCE_NOT_LIVE"
                step.materialState=anyUnknown and "UNKNOWN" or
                    (ready and "REFERENCE_REAGENTS_PRESENT" or "REFERENCE_REAGENTS_MISSING")
            else
                step.materials={};step.reagentStatus="REAGENT_SOURCE_CONFLICT"
                step.materialState="UNKNOWN"
            end
            -- P0-208: Optional fresh live learned/yield context. Never native.
            local observer=JLP:GetModule("SecondaryVolatileAdvisory")
            if observer and type(observer.Observe)=="function" then
                local expectedOutputID=type(candidate.outputs)=="table" and
                    #candidate.outputs==1 and candidate.outputs[1].itemID or nil
                local live=observer:Observe(key,skill,step.recipeID,step.recipe,expectedOutputID)
                step.learnedState=live.learnedState
                step.liveEvidenceSource=live.source
                step.liveEvidenceReason=live.reason
                step.liveYieldState=live.yieldState
                step.liveOutputMin=live.outputMin
                step.liveOutputMax=live.outputMax
                step.liveOutputItemID=live.outputItemID
            end
            step.nextAction=step.learnedState=="NOT_LEARNED" and
                "VERIFY_EXACT_RECIPE_LEARNING_SOURCE" or
                step.learnedState=="LEARNED" and
                (step.materialState=="REFERENCE_REAGENTS_PRESENT" and
                    "VERIFY_ARTISAN_THEN_MANUAL_CRAFT_ONE" or
                    "VERIFY_INVENTORY_THEN_MANUAL_CRAFT") or
                "VERIFY_ARTISAN_QUEST_RECIPE_LEARNED_AND_MATERIALS"
            result.advancedCurrentStep=step
            result.advancedNextAction=step.nextAction
        else
            result.advancedCurrentStep=nil
            result.advancedNextAction="VERIFY_RECIPE_SOURCE_AND_SKILL"
        end
        result.advancedGuideComplete=false
        result.advancedCraftCountKnown=false
    end
    -- P0-205: expose exact 225-300 FIRST_AID recipe identities and public
    -- learning references WITHOUT replacing the 1-225 guide or making an
    -- unauthorised craft-count/material budget for the unfinished segment.
    if key=="FIRST_AID" and skill>=225 then
        result.advancedReferences={}
        result.advancedReferenceState="SOURCE_FIELDS_PARTIALLY_QUALIFIED"
        local catalogue=JLP:GetModule("Build70450RecipeCatalogue")
        for _,hint in ipairs(data.advancedFirstAidReferences or {}) do
            local recipe=catalogue and catalogue.GetRecipe and
                catalogue:GetRecipe("FIRST_AID",hint.spellID,70450)
            if recipe and recipe.spellID==hint.spellID and recipe.name==hint.name and
                recipe.professionKey=="FIRST_AID" and recipe.skillLineID==129 and
                recipe.recordKind=="RECIPE_CANDIDATE" and type(recipe.reagents)=="table" and
                #recipe.reagents>0 and recipe.nativeDispatchAllowed==false then
                local source="https://www.wowhead.com/forever/spell="..hint.spellID
                local exact=JLP:GetModule("CrossProfessionDependencyPlanner")
                local edge=exact and exact:Resolve("FIRST_AID",hint.spellID)
                local yieldVerified=edge and edge.outputPerCraft==hint.yieldFromForever
                result.advancedReferences[#result.advancedReferences+1]={
                    recipeID=hint.spellID,recipe=hint.name,professionKey="FIRST_AID",
                    suggestedAtSkill=hint.guideMinimumSkill,referenceWindowEnd=hint.sourceWindowEnd,
                    referenceAuthority=hint.learningSource,sourceURL=source,
                    learningStatus="VERIFY_AT_TRAINER",learnedState="UNKNOWN",
                    outputItemID=yieldVerified and edge.outputItemID or nil,
                    fixedOutput=yieldVerified and edge.outputPerCraft or nil,
                    yieldStatus=yieldVerified and "EXTERNAL_EXACT_NOT_LIVE" or "UNKNOWN",
                    ingredients=yieldVerified and edge.materials or nil,
                    reagentStatus=yieldVerified and "DB70450_REFERENCE" or "NOT_QUALIFIED",
                    expectedCrafts=nil,skillUpChance=nil,
                    requiredSkillAuthority="NOT_LIVE_VERIFIED",
                    navigationStatus="LOCATION_UNVERIFIED",nativeDispatchAllowed=false,
                    executionEligible=false,readOnly=true}
            else
                result.advancedReferenceState="PARTIAL_SOURCE_UNAVAILABLE"
            end
        end
        result.advancedGuideComplete=false
        result.advancedCraftCountKnown=false
        result.advancedAccessGate="ARTISAN_TRIAGE_QUEST_UNVERIFIED"
        -- Static guide target coordinates are deliberately not passed to travel.
    end
    -- P0-207: retain an independent NPC *identity* record when an existing
    -- Forever public guide crosscheck has the identical item/spell/name/scope.
    -- Source actors NEVER imply actual vendor stock or a canonical waypoint.
    local function cookingVendorIdentity(r)
        local source=JLP.data and JLP.data.build70450NPCSourceCrosschecks
        local entries=source and source.rows and source.rows[r.itemID]
        if type(entries)~="table" or #entries~=1 then return nil,"ACTOR_REFERENCE_UNKNOWN" end
        local actor=entries[1]
        if source.productionAuthority~=false or
           actor.source~="foreverCookingGuide" or
           actor.state~="WOWHEAD_FOREVER_HORDE_COOKING_GUIDE_2026_10_11" or
           actor.professionKey~="COOKING" or actor.faction~="Horde" or
           actor.kind~="vendor" or actor.spellID~=r.spellID or
           actor.skillRequired~=r.requiredSkill or actor.name~=r.seller or
           actor.itemPageURL~=("https://www.wowhead.com/forever/item="..r.itemID) or
           type(actor.npcID)~="number" or actor.npcID<1 or
           actor.npcID~=math.floor(actor.npcID) then
           return nil,"ACTOR_REFERENCE_CONFLICT"
        end
        return {npcID=actor.npcID,npcName=actor.name,
            evidenceState="FOREVER_PUBLIC_GUIDE_ACTOR_NOT_LIVE",
            sourceURL=source.citations and source.citations.foreverCookingGuide,
            vendorStock="UNKNOWN",canonicalWaypoint=nil,
            navigationEligible=false,readOnly=true},"ACTOR_IDENTITY_REFERENCE_ONLY"
    end
    -- P0-206: exact Cooking teaching-item links are separate from seller leads.
    -- Neither a public vendor name nor item identity authorizes inventory,
    -- purchasing, NPC coordinates or automated travel.
    if key=="COOKING" then
        local exact=JLP.data and JLP.data.secondaryRecipeLearning206
        result.learningReferences={}
        result.learningSourceState="EXACT_SOURCE_UNAVAILABLE"
        if exact and exact.contract=="JLP-SECONDARY-EXACT-TEACHING-ITEMS-206" and
           exact.nativeDispatchAllowed==false and exact.guideURL==data.guideURL and
           type(exact.professions)=="table" and type(exact.professions.COOKING)=="table" then
            local valid=true
            local source=exact.professions.COOKING
            local required={[7751]=1,[7753]=50,[7755]=100,[20916]=175}
            local expectedItem={[7751]=6325,[7753]=6328,[7755]=6330,[20916]=17062}
            local seen={}
            if #source~=4 then valid=false end
            for _,r in ipairs(source) do
                if type(r)~="table" or not required[r.spellID] or seen[r.spellID] or
                    r.requiredSkill~=required[r.spellID] or r.itemID~=expectedItem[r.spellID] or
                    r.faction~="Horde" or type(r.seller)~="string" or r.seller=="" or
                    type(r.teachingItemURL)~="string" or r.teachingItemURL~=
                    ("https://www.wowhead.com/forever/item="..r.itemID.."/recipe-"..
                     (r.spellID==7751 and "brilliant-smallfish" or
                      r.spellID==7753 and "longjaw-mud-snapper" or
                      r.spellID==7755 and "bristle-whisker-catfish" or "mithril-head-trout")) then
                    valid=false
                else seen[r.spellID]=true end
            end
            if valid then
                for _,r in ipairs(source) do
                    local row={spellID=r.spellID,teachingItemID=r.itemID,
                        requiredSkill=r.requiredSkill,recipeName=r.name,
                        sellerNameLead=r.seller,sellerZoneLead=r.vendorZone,
                        teachingItemSourceURL=r.teachingItemURL,guideURL=exact.guideURL,
                        sourceStatus="EXACT_ITEM_AND_PUBLIC_SELLER_NAME_ONLY",
                        vendorStock="UNKNOWN",npcID=nil,waypoint=nil,
                        learnedState="UNKNOWN",readOnly=true,nativeDispatchAllowed=false}
                    row.vendorIdentity,row.vendorIdentityState=cookingVendorIdentity(r)
                    -- Do not promote public NPC proof to row.npcID: this
                    -- field is reserved for travel-qualified action identity.
                    result.learningReferences[#result.learningReferences+1]=row
                    if result.currentStep and result.currentStep.recipe==r.name then
                        result.currentLearningReference=row
                    end
                end
                result.learningSourceState="EXACT_TEACHING_ITEM_NAME_ONLY"
            else result.learningSourceState="SOURCE_CONFLICT_UNKNOWN" end
        end
    end
    if key=="FIRST_AID" and skill>=225 and skill<300 then
        -- Build one skill-selected, recipe-linked advisory step. This is NOT
        -- a new guide estimate or a request to the protected crafting API.
        local candidate
        for _,row in ipairs(result.advancedReferences or {}) do
            if row.suggestedAtSkill<=skill and skill<(row.referenceWindowEnd or 300) then
                candidate=row;break
            end
        end
        if not candidate then
            result.advancedNextAction="VERIFY_SKILL_OR_RECIPE_SOURCE"
            result.advancedCurrentStep=nil
        else
            local receipt={contract="JLP-FIRST-AID-ADVANCED-ADVISORY-206",
                skill=skill,skillTarget=candidate.referenceWindowEnd,
                recipeID=candidate.recipeID,recipe=candidate.recipe,
                suggestedAtSkill=candidate.suggestedAtSkill,
                windowBasis="HISTORICAL_FOREVER_COMMENT_NOT_CLIENT_TESTED",
                sourceURL=candidate.sourceURL,recipeSourceAuthority=candidate.referenceAuthority,
                learnedState="UNKNOWN",artisanQuestStatus="UNKNOWN",
                expectedCrafts=nil,skillUpChance=nil,
                expectedOutput=nil,materialBudget=nil,
                materials={},navigationStatus="LOCATION_UNVERIFIED",
                nativeDispatchAllowed=false,executionEligible=false,readOnly=true,
                replanAfter={"SKILL_CHANGE","RECIPE_LEARNED","INVENTORY_OBSERVED",
                    "CRAFT_EVENT_RECEIPT","PROFESSION_CHANGED","RELOAD"}}
            -- Per-craft reagents are historical DB70450 references. No
            -- conversion from these into full-band estimates is permitted.
            local sourceCatalogue=JLP:GetModule("Build70450RecipeCatalogue")
            local recipe=sourceCatalogue and sourceCatalogue.GetRecipe and
                sourceCatalogue:GetRecipe("FIRST_AID",candidate.recipeID,70450)
            if recipe and recipe.spellID==candidate.recipeID and recipe.name==candidate.recipe and
                recipe.professionKey=="FIRST_AID" and recipe.skillLineID==129 and
                type(recipe.reagents)=="table" and #recipe.reagents>0 then
                local valid=true
                local seen={}
                for _,mat in ipairs(recipe.reagents) do
                    if type(mat.itemID)~="number" or mat.itemID<1 or
                        type(mat.quantity)~="number" or mat.quantity<1 or
                        mat.quantity~=math.floor(mat.quantity) or seen[mat.itemID] then
                        valid=false;break
                    end
                    seen[mat.itemID]=true
                end
                if valid then
                    receipt.reagentStatus="DB70450_HISTORICAL_PER_CRAFT"
                    local ready=true;local anyUnknown=false
                    for _,mat in ipairs(recipe.reagents) do
                        local observation=options.inventoryByItemID and
                            options.inventoryByItemID[mat.itemID]
                        if type(observation)~="table" then
                            observation=inv and inv.GetOwned and inv:GetOwned(mat.itemID) or {}
                        end
                        local n=qualifiedStock(observation.bags)
                        local known=observation.bagKnown==true and n~=nil and
                            observation.snapshotStale~=true and
                            observation.freshness~="STALE"
                        if not known then anyUnknown=true;ready=false
                        elseif n<mat.quantity then ready=false end
                        receipt.materials[#receipt.materials+1]={itemID=mat.itemID,
                            perCraft=mat.quantity,required=mat.quantity,
                            bagsKnown=known,bags=known and n or nil,
                            missing=known and math.max(0,mat.quantity-n) or nil,
                            quantityAuthority="HISTORICAL_DB70450_REAGENT",
                            readOnly=true,nativeDispatchAllowed=false}
                    end
                    receipt.materialState=anyUnknown and "UNKNOWN" or
                        (ready and "REFERENCE_REAGENTS_PRESENT" or "REFERENCE_REAGENTS_MISSING")
                else receipt.reagentStatus="REAGENT_SOURCE_CONFLICT" end
            else receipt.reagentStatus="REAGENT_SOURCE_UNAVAILABLE" end
            -- At 225 Artisan quest completion is unknown; at all skill
            -- levels learned state is unknown until a fresh client receipt.
            local observer=JLP:GetModule("SecondaryVolatileAdvisory")
            if observer and type(observer.Observe)=="function" then
                local live=observer:Observe(key,skill,receipt.recipeID,receipt.recipe,
                    candidate.outputItemID)
                receipt.learnedState=live.learnedState
                receipt.liveEvidenceSource=live.source
                receipt.liveEvidenceReason=live.reason
                receipt.liveYieldState=live.yieldState
                receipt.liveOutputMin=live.outputMin
                receipt.liveOutputMax=live.outputMax
                receipt.liveOutputItemID=live.outputItemID
            end
            receipt.nextAction=receipt.learnedState=="NOT_LEARNED" and
                "VERIFY_EXACT_RECIPE_LEARNING_SOURCE" or
                receipt.learnedState=="LEARNED" and
                (receipt.materialState=="REFERENCE_REAGENTS_PRESENT" and
                    "VERIFY_ARTISAN_THEN_MANUAL_CRAFT_ONE" or
                    "VERIFY_INVENTORY_THEN_MANUAL_CRAFT") or
                (skill==225 and "VERIFY_ARTISAN_TRIAGE_AND_RECIPE" or
                    "VERIFY_LEARNED_AND_RECIPE_MATERIALS")
            result.advancedCurrentStep=receipt
            result.advancedNextAction=receipt.nextAction
        end
    end
    for _,r in ipairs(result.materials) do
        local observation=options.inventoryByItemID and options.inventoryByItemID[r.itemID]
        if type(observation)~="table" then
            observation=inv and inv.GetOwned and inv:GetOwned(r.itemID) or {}
        end
        local rawBags=qualifiedStock(observation.bags)
        local rawBank=qualifiedStock(observation.bank)
        local stale=stockStale(observation)
        r.bagsKnown=observation.bagKnown==true and rawBags~=nil and
            observation.snapshotStale~=true and observation.freshness~="STALE"
        r.bags=r.bagsKnown and rawBags or nil
        r.bankKnown=observation.bankKnown==true and rawBank~=nil and not stale
        r.bank=r.bankKnown and rawBank or nil
        r.bankStale=stale
        r.snapshotStale=observation.snapshotStale==true
        r.ownAvailable=r.bankKnown and r.bagsKnown and
            math.min(r.guideEstimate,r.bags+r.bank) or nil
        r.bankRetrieve=r.bankKnown and r.bagsKnown and
            math.min(r.bank, math.max(0,r.guideEstimate-r.bags)) or nil
        -- Legacy aggregate route field remains a conditional upper bound when
        -- the bank is UNKNOWN. Step-specific material receipts still return
        -- nil for missing, and the common widget never displays this bound
        -- as a qualified acquisition quantity.
        r.externalNeededIfGuideEstimateHolds=r.bagsKnown and r.bankKnown and
            math.max(0,r.guideEstimate-r.bags-r.bank) or nil
        r.externalUpperBoundIfBankUnknown=(not r.bankKnown and r.bagsKnown) and
            math.max(0,r.guideEstimate-r.bags) or nil
        r.altBankAdvisory=0
        local alts=options.altByItemID and options.altByItemID[r.itemID]
        if not alts then alts=inv and inv.GetAltBankAvailability and inv:GetAltBankAvailability(r.itemID,{sameRealm=true}) or {} end
        for _,alt in ipairs(alts) do
            if alt.requiresTransfer~=false and alt.currentAccessible~=true and alt.bankKnown~=false then
                r.altBankAdvisory=r.altBankAdvisory+nat(alt.count)
            end
        end
        -- Alt availability never reduces externalRequired or increases craft readiness.
        r.externalIfTransferConfirmed=r.externalNeededIfGuideEstimateHolds and
            math.max(0,r.externalNeededIfGuideEstimateHolds-r.altBankAdvisory) or nil
    end
    table.sort(result.materials,function(a,b) return a.itemID<b.itemID end)
    if skill>=data.coverageEnd then result.status="PUBLIC_GUIDE_END" else result.status="ADVISORY_GUIDE_ESTIMATE" end
    return result
end
-- A selected *single* already-qualified guide step, never an independent
-- planner or a native craft request. Public reagent quantities/yield are
-- source facts; expectedCrafts and derived gross/missing remain estimates.
function P:BuildStepPlan(plan,ordinal)
    if type(plan)~="table" or plan.nativeDispatchAllowed~=false or
       (plan.professionKey~="COOKING" and plan.professionKey~="FIRST_AID") or
       type(plan.steps)~="table" then return nil,"PLAN_UNAVAILABLE" end
    local data,err=self:GetData(plan.professionKey)
    if not data then return nil,err end
    if plan.sourceURL~=data.guideURL then return nil,"SOURCE_CHANGED" end
    local proofs,reason=recipeEvidence(plan.professionKey,data)
    if not proofs then return nil,reason end
    local index=tonumber(ordinal)
    if not index or index~=index or index==math.huge or index==-math.huge or
        index~=math.floor(index) or index<1 or index>#plan.steps then
        return nil,"STEP_UNAVAILABLE" end
    local step=plan.steps[index]
    if type(step)~="table" then return nil,"STEP_UNAVAILABLE" end
    local selected,proof
    for i,s in ipairs(data.steps) do
        if s.skillMin==step.skillMin and s.skillMax==step.skillMax and
           s.recipe==step.recipe and proofs[i].recipeID==step.recipeID then
            selected=s;proof=proofs[i];break
        end
    end
    if not selected or not proof or step.recipeSourceURL~=proof.evidenceURL or
       step.estimatedCrafts~=selected.estimatedCrafts or
       step.outputQuantity~=proof.outputQuantity or
       type(proof.outputQuantity)~="number" or proof.outputQuantity<1 or
       proof.outputQuantity~=math.floor(proof.outputQuantity) then
        return nil,"STEP_SOURCE_CHANGED" end
    local estimate=nat(selected.estimatedCrafts)
    if estimate<1 then return nil,"ESTIMATE_UNAVAILABLE" end
    local existing={}
    for _,row in ipairs(plan.materials or {}) do
        if type(row)=="table" and type(row.itemID)=="number" then existing[row.itemID]=row end
    end
    local parts={plan.professionKey,tostring(plan.skill),plan.sourceURL,
        tostring(selected.skillMin),tostring(selected.skillMax),tostring(proof.recipeID),
        proof.evidenceURL,tostring(proof.outputQuantity),tostring(estimate)}
    local rows={}
    for _,mat in ipairs(proof.materials) do
        local perCraft=nat(mat.quantity)
        if perCraft<1 or type(mat.evidenceURL)~="string" or mat.evidenceURL=="" or
           not existing[mat.itemID] then return nil,"REAGENT_SOURCE_UNAVAILABLE" end
        local owned=existing[mat.itemID]
        local gross=perCraft*estimate
        local rawBags=qualifiedStock(owned.bags)
        local rawBank=qualifiedStock(owned.bank)
        local stale=owned.bankStale==true or owned.snapshotStale==true
        local bagsKnown=owned.bagsKnown==true and rawBags~=nil and
            owned.snapshotStale~=true
        local bankKnown=owned.bankKnown==true and rawBank~=nil and not stale
        local bags=bagsKnown and rawBags or 0
        local bank=bankKnown and rawBank or 0
        rows[#rows+1]={itemID=mat.itemID,name=mat.name,source=mat.source,
            sourceURL=mat.evidenceURL,guideEstimate=gross,perCraft=perCraft,
            expectedCrafts=estimate,outputQuantity=proof.outputQuantity,
            grossEstimate=gross,bags=bags,bagsKnown=bagsKnown,
            bankKnown=bankKnown,bank=bank,bankStale=stale,
            snapshotStale=owned.snapshotStale==true,
            bankRetrieve=math.min(bank,math.max(0,gross-bags)),
            -- Only bags are confirmed with unknown bank; do not report
            -- the unobserved bank as a verified zero/fully-known shortfall.
            externalNeededIfGuideEstimateHolds=bankKnown and bagsKnown and
                math.max(0,gross-bags-bank) or nil,
            externalUpperBoundIfBankUnknown=(not bankKnown and bagsKnown) and
                math.max(0,gross-bags) or nil,
            materialDecisionStatus=not bagsKnown and "BAGS_UNKNOWN" or
                stale and "STALE" or not bankKnown and "BANK_UNKNOWN" or
                (bank>0 and "BANK_POSITIVE" or "BANK_KNOWN_ZERO"),
            altBankAdvisory=owned.altBankAdvisory or 0,
            recipeBands={{recipe=selected.recipe,recipeID=proof.recipeID,
                skillMin=selected.skillMin,skillMax=selected.skillMax,
                sourceURL=proof.evidenceURL,perCraft=perCraft,craftsEstimate=estimate}},
            nativeDispatchAllowed=false,readOnly=true}
        parts[#parts+1]=tostring(mat.itemID)..":"..tostring(perCraft)..":"..
            tostring(mat.source)..":"..mat.evidenceURL
    end
    table.sort(rows,function(a,b)return a.itemID<b.itemID end)
    return {contract="forever-secondary-selected-step-v1",professionKey=plan.professionKey,
        skill=plan.skill,sourceURL=plan.sourceURL,coverageEnd=plan.coverageEnd,
        currentStep=selected,steps={step},materials=rows,stepOrdinal=index,
        stepCount=#plan.steps,stepIdentity=table.concat(parts,"|"),
        recipeID=proof.recipeID,recipeSourceURL=proof.evidenceURL,
        outputQuantity=proof.outputQuantity,expectedCrafts=estimate,
        status="SOURCE_QUALIFIED_STEP_ESTIMATE",estimated=true,
        nativeDispatchAllowed=false,executionEligible=false,readOnly=true},nil
end

-- Bounded read-only material browsing over the existing verified 1-225 plan.
-- The plan remains a guide estimate, never a craft/purchase instruction.
function P:MaterialPage(plan,requested,pageSize)
    if type(plan)~="table" or plan.nativeDispatchAllowed~=false or
       (plan.professionKey~="COOKING" and plan.professionKey~="FIRST_AID") or
       type(plan.materials)~="table" then
        return {status="REFERENCE_UNAVAILABLE",rows={},page=1,pageCount=0,total=0,
            canPrevious=false,canNext=false,readOnly=true,nativeDispatchAllowed=false}
    end
    local size=math.max(1,math.min(3,nat(pageSize or 1)))
    local total=#plan.materials
    local pages=math.ceil(total/size)
    local page=math.min(math.max(1,nat(requested or 1)),math.max(1,pages))
    local rows={}
    for index=(page-1)*size+1,math.min(total,page*size) do
        local row=plan.materials[index]
        if type(row)=="table" then
            rows[#rows+1]={itemID=row.itemID,name=row.name,source=row.source,
                sourceURL=row.sourceURL,guideEstimate=row.guideEstimate,
                perCraft=row.perCraft,expectedCrafts=row.expectedCrafts,
                outputQuantity=row.outputQuantity,grossEstimate=row.grossEstimate,
                bags=row.bags,bagsKnown=row.bagsKnown,bank=row.bank,bankKnown=row.bankKnown,
                bankStale=row.bankStale,snapshotStale=row.snapshotStale,
                bankRetrieve=row.bankRetrieve,
                materialDecisionStatus=row.materialDecisionStatus,
                externalUpperBoundIfBankUnknown=row.externalUpperBoundIfBankUnknown,
                externalNeededIfGuideEstimateHolds=row.externalNeededIfGuideEstimateHolds,
                altBankAdvisory=row.altBankAdvisory,
                recipeBands=row.recipeBands}
        end
    end
    return {status=total>0 and "ADVISORY_GUIDE_ESTIMATE" or "EMPTY",
        rows=rows,page=page,pageCount=pages,total=total,
        canPrevious=page>1,canNext=page<pages,readOnly=true,
        nativeDispatchAllowed=false,estimated=true,
        sourceURL=plan.sourceURL,professionKey=plan.professionKey}
end

function P:GetFishingGuidance(skill)
    local data=JLP.data and JLP.data.foreverSecondaryLeveling and JLP.data.foreverSecondaryLeveling.fishing
    if not data then return nil,"FISHING_REFERENCE_UNAVAILABLE" end
    skill=tonumber(skill)
    if not skill then return nil,"SKILL_UNAVAILABLE" end
    local result={contract="forever-fishing-zone-guidance-v1",skill=skill,sourceURL=data.guideURL,
        nativeDispatchAllowed=false,mapPinsAvailable=false,zoneRequirementsAreNotCoordinates=true,
        full225To300Guide=false,zones={},note=data.note,
        suggestedLure=(skill<data.starterLure.untilSkill and data.starterLure.name or nil),
        expert=(skill>=150 and data.expert or nil)}
    for _,zone in ipairs(data.tiers or {}) do
        if skill>=zone.skillMin and skill<zone.skillMax then
            result.zones[#result.zones+1]={name=zone.zone,minSkill=zone.minSkill,
                guaranteedCatchSkill=zone.guaranteedCatchSkill,
                meetsMinimum=skill>=zone.minSkill,needsBoostForMinimum=skill<zone.minSkill,
                below100PercentThreshold=skill<zone.guaranteedCatchSkill}
        end
    end
    local zones=JLP:GetModule("ForeverFishingZoneModel")
    if zones then
        local mapModel=zones:Lookup(nil,skill,0)
        result.zoneModel=mapModel
    end
    return result
end
function P:Validate()
    local errors={}
    for _,key in ipairs({"COOKING","FIRST_AID"}) do
        local _,reason=self:GetData(key)
        if reason then errors[#errors+1]=key..":"..reason end
    end
    local fish=JLP.data and JLP.data.foreverSecondaryLeveling and JLP.data.foreverSecondaryLeveling.fishing
    if not fish or #fish.tiers~=4 then errors[#errors+1]="fishing-source" end
    return errors
end

-- Presentation adapter for the existing selected-step/material receipt, not a planner.
function P:BuildOperationalStepPlan(plan)
 local c=plan and plan.recommendedCurrentStep
 if not c or c.kind~="craft"then return nil end
 local rows={};local inv=JLP:GetModule("Inventory")
 for _,m in ipairs(c.materials or {})do
  local n=m.batchRequired or m.required;local o=inv and inv:GetOwned(m.itemID)or {}
  local bags=qualifiedStock(o.bags);local bank=qualifiedStock(o.bank)
  local bk=o.bagKnown==true and bags~=nil;local nk=o.bankKnown==true and bank~=nil and not stockStale(o)
  rows[#rows+1]={itemID=m.itemID,name=m.name or("Item "..m.itemID),source=m.source,
   sourceURL=c.wowheadLookupURL,recipeID=c.recipeID,perCraft=m.perCraft or m.quantity,guideEstimate=n,
   expectedCrafts=c.remainingCrafts,bags=bk and bags or nil,bagsKnown=bk,bank=nk and bank or nil,bankKnown=nk,
   bankStale=stockStale(o),externalNeededIfGuideEstimateHolds=bk and nk and type(n)=="number"and math.max(0,n-bags-bank)or nil,
   externalUpperBoundIfBankUnknown=bk and not nk and type(n)=="number"and math.max(0,n-bags)or nil,
   materialDecisionStatus=not bk and "BAGS_UNKNOWN"or not nk and "BANK_UNKNOWN"or bank>0 and "BANK_POSITIVE"or "BANK_KNOWN_ZERO",
   recipeBands={{recipe=c.recipe,recipeID=c.recipeID,skillMin=c.skill,skillMax=c.skillTarget,sourceURL=c.wowheadLookupURL,perCraft=m.perCraft or m.quantity,craftsEstimate=c.remainingCrafts}},
   evidenceClass="DB2_INPUTS_AND_CURRENT_SCENARIO_NOT_HISTORICAL_GUIDE_COUNT",readOnly=true,nativeDispatchAllowed=false}
 end
 return {contract="forever-secondary-selected-step-v1",operational=true,professionKey=plan.key,skill=c.skill,
  recipeID=c.recipeID,recipe=c.recipe,stepOrdinal=1,stepCount=1,sourceURL=c.wowheadLookupURL,
  stepIdentity=table.concat({plan.key,c.recipeID,c.skill,c.remainingCrafts,c.strategy or "unknown"},":"),
  expectedCrafts=c.remainingCrafts,outputQuantity=c.expectedOutputQuantity,materials=rows,readOnly=true,nativeDispatchAllowed=false}
end

-- Cooking/Fishing access uses the existing secondary workspace and destination
-- owner. Static actors are not current offers, inventory or learned receipts.
local secondaryActors={
 ZAMJA={npcID=3399,name="Zamja",zone="Orgrimmar",mapID=1454,x=.576,y=.536,kind="trainer",faction="Horde",url="https://www.icy-veins.com/wow-forever/cooking",positionEvidence="FOREVER_GUIDE_REFERENCE"},
 WULAN={npcID=12033,name="Wulan",zone="Desolace",mapID=1443,x=.262,y=.698,kind="vendor",faction="Horde",url="https://www.wow-professions.com/forever/npc/wulan",positionEvidence="EXISTING_FOREVER_REFERENCE"},
 DIRGE={npcID=8125,name="Dirge Quikcleave",zone="Tanaris",mapID=1446,x=.526,y=.28,kind="quest_giver",faction="Neutral",url="https://www.wow-professions.com/forever/cooking-leveling-guide",positionEvidence="EXISTING_GUIDE_REFERENCE_NOT_CURRENT_BETA_QUEST"},
 SEWA={npcID=3029,name="Sewa Mistrunner",zone="Thunder Bluff",mapID=1456,x=.5579,y=.4702,kind="vendor",faction="Horde"},
 NAAL={npcID=3027,name="Naal Mistrunner",zone="Thunder Bluff",mapID=1456,x=.5099,y=.5245,kind="vendor",faction="Horde"},
 SHANKYS={npcID=3333,name="Shankys",zone="Orgrimmar",mapID=1454,x=.6999,y=.2977,kind="vendor",faction="Horde"},
 GIKKIX={npcID=8137,name="Gikkix",zone="Tanaris",mapID=1446,x=.6664,y=.2208,kind="vendor",faction="Neutral"},
 KELSEY={npcID=2664,name="Kelsey Yance",zone="Stranglethorn Vale",kind="vendor",faction="Neutral",url="https://www.wow-professions.com/forever/npc/kelsey-yance"},
 HEMING={npcID=2626,name="Old Man Heming",zone="Stranglethorn Vale",mapID=1434,x=.2742,y=.7716,kind="vendor",faction="Neutral"},
 LAUTIKI={npcID=5941,name="Lau'Tiki",zone="Durotar",mapID=1411,x=.5325,y=.8159,kind="trainer",faction="Horde"},
 NAT={npcID=12919,name="Nat Pagle",zone="Dustwallow Marsh",mapID=1445,x=.5876,y=.6017,kind="quest_giver",faction="Neutral"},
}
local function secondaryWhole(n)return type(n)=="number"and n==n and n>=0 and n<math.huge and n==math.floor(n)end
local function secondaryBags(id)
 local inv=JLP:GetModule("Inventory");local r=inv and inv:GetOwned(id)or {}
 return r.bagKnown==true and secondaryWhole(r.bags)and r.bags or nil,r.bankKnown==true and secondaryWhole(r.bank)and not r.bankStale and r.bank or nil
end
local function secondaryQuest(fn,id)
 local q=type(C_QuestLog)=="table"and C_QuestLog
 if q and type(q[fn])=="function"then local ok,v=pcall(q[fn],id);if ok and type(v)=="boolean"then return v end end
end
function P:GetOperationalAccess(key,profession,recipeID)
 if key~="COOKING"and key~="FISHING"then return nil end
 local a={profession=key,recipeID=recipeID,status="VERIFY",readOnly=true,nativeDispatchAllowed=false}
 if not profession or profession.cached or not secondaryWhole(profession.skill)then a.status="OBSERVE_PROFESSION";return a end
 if recipeID then
  local facts=JLP:GetModule("ProfessionPlanningFacts");local f=facts and facts:GetAlchemyContract(recipeID,key)
  local live=f and facts:Observe(key,recipeID)
  if not live or not live.observed or type(live.learned)~="boolean"then a.status="OBSERVE_LEARNED";return a end
  if live.learned then a.status="LEARNED";return a end
  a.minimum=f.minimum;a.learningMinimum=f.learningMinimum;a.actor=f.sourceActor
  if profession.skill<f.minimum then a.status="SKILL_UNMET";a.actor=nil;return a end
  if not a.actor then a.status="VERIFY_RECIPE_SOURCE";return a end
  a.itemID=f.recipeItemID;a.trainingSpellID=recipeID
  a.teachingRelation=facts:GetQualifiedTeachingRelation(key,recipeID);a.teachingSpellID=a.teachingRelation and a.teachingRelation.spellID
 else
  local cap=profession.maxSkill
  if cap~=75 and cap~=150 and cap~=225 and cap~=300 then a.status="OBSERVE_CAP";return a end
  if profession.skill<cap or cap==300 then return nil end
  a.rank=cap==75 and "Journeyman"or cap==150 and "Expert"or "Artisan"
  a.minimum=cap==75 and 50 or cap==150 and 125 or 225
  a.requiredCharacterLevel=key=="FISHING"and (cap==75 and 10 or cap==150 and 20 or 35)or cap==225 and 35 or nil
  if a.requiredCharacterLevel then
   local level=type(UnitLevel)=="function"and UnitLevel("player")
   if not secondaryWhole(level)or level<a.requiredCharacterLevel then a.status="VERIFY_CHARACTER_LEVEL";return a end
  end
  if cap==75 then a.actor=key=="COOKING"and "ZAMJA"or "LAUTIKI";a.trainingSpellID=key=="COOKING"and 3102 or 7731
  elseif cap==150 then a.actor=key=="COOKING"and "WULAN"or "HEMING";a.itemID=key=="COOKING"and 16072 or 16083
  else
   a.actor=key=="COOKING"and "DIRGE"or "NAT";a.questID=key=="COOKING"and 6610 or 6607
   local done=secondaryQuest("IsQuestFlaggedCompleted",a.questID)
   if done==true then a.status="OBSERVE_CAP_AFTER_QUEST";a.actor=nil
   elseif done==nil then a.status="VERIFY_CURRENT_QUEST_STATUS"
   else
    local active=secondaryQuest("IsOnQuest",a.questID)
    a.status=active==false and "INSPECT_ACCEPT_QUEST"or active==true and (secondaryQuest("ReadyForTurnIn",a.questID)==true and "RETURN_QUEST"or "MANUAL_QUEST_OBJECTIVES")or "VERIFY_CURRENT_QUEST_LOG"
   end
   if a.status=="MANUAL_QUEST_OBJECTIVES"then
    a.currentObjectives=self:ObserveArtisanObjectives(a.questID)
    if a.questID==6607 then self:BindFishingQuestAreas(a)end
   end
   -- Reference objectives never invent a current quest, inventory or catches.
   a.questReferenceOnly=true;if type(UnitFactionGroup)~="function"or UnitFactionGroup("player")~="Horde"then a.status="VERIFY_FACTION_SOURCE";a.actor=nil end;return a
  end
 end
 if type(UnitFactionGroup)~="function"or UnitFactionGroup("player")~="Horde"then a.status="VERIFY_FACTION_SOURCE";a.actor=nil;return a end
 local actor=secondaryActors[a.actor];local evidence=JLP:GetModule("RecipeAccessEvidence")
 if a.itemID then
  local bags,bank=secondaryBags(a.itemID);a.bags=bags;a.bank=bank
  if bags and bags>0 then a.status="USE_BOOK_MANUALLY";a.actor=nil
  elseif bags==0 and bank and bank>0 then a.status="RETRIEVE_BOOK_BANK";a.actor=nil
  elseif bags~=0 or bank~=0 then a.status="OBSERVE_BOOK_INVENTORY";a.actor=nil
  else
   a.offer=evidence and evidence:GetMerchantPlanningHint(a.itemID,actor.npcID)or {status="UNKNOWN"}
   if a.offer.status=="OUT_OF_STOCK"or a.offer.status=="NOT_OFFERED"or a.offer.status=="INELIGIBLE"or a.offer.recentUnavailable then a.status="RECHECK_BOOK_SOURCE";a.actor=nil
   elseif a.offer.status=="AVAILABLE"then
    a.purchase=evidence:GetMerchantPurchaseAdvice(a.itemID,actor.npcID,1)
    a.status=(a.purchase.status=="READY_MANUAL_PURCHASE"or a.purchase.status=="VERIFY_LIMITED_STOCK")and "BUY_BOOK_MANUALLY"or "VERIFY_BOOK_PURCHASE_REQUIREMENTS"
   else a.status="VERIFY_CURRENT_BOOK_OFFER"end
  end
 else
  a.offer=evidence and evidence:GetRecipeLearningPlanningHint(key,a.trainingSpellID,actor.npcID)or {status="UNKNOWN"}
  a.status=a.offer.status=="AVAILABLE"and "LEARN_MANUALLY"or "VERIFY_CURRENT_TRAINER_OFFER"
  if a.offer.status=="NOT_OFFERED"or a.offer.status=="INELIGIBLE"or a.offer.recentUnavailable then a.actor=nil end
 end
 return a
end
function P:OperationalInstruction(a)
 local target=a.itemID and ("recipe/book "..a.itemID)or a.recipeID and ("recipe "..a.recipeID)or a.rank or a.profession
 local actor=secondaryActors[a.actor];local place=actor and (actor.name..", "..actor.zone)or "the current qualified source"
 if a.status=="USE_BOOK_MANUALLY"then return "Use the observed "..target.." manually; wait for separate learned-state/cap observation. Possession is not learning."end
 if a.status=="RETRIEVE_BOOK_BANK"then return "Withdraw the observed "..target.." from bank; observe bags, use manually, then observe learning separately."end
 if a.status=="BUY_BOOK_MANUALLY"then return "Buy ONE "..target.." manually from the exact current offer at "..place.."; recheck funds/stock, observe delivery and learning separately."end
 if a.status=="LEARN_MANUALLY"then return "Learn "..target.." manually from the exact observed offering at "..place.."; observe recipe/cap separately."end
 if a.status=="MANUAL_QUEST_OBJECTIVES"then
  if a.questObjective then
   local r=a.questObjective;local ref=r.areaReference
   return "Quest 6607: "..r.text.." ("..r.numFulfilled.."/"..r.numRequired.."). Fish manually in "..ref.area..", "..ref.zone..
    ". A qualified zone approach is not the fishing location; inspect safe water in the named area. Observe quest progress separately; no catch count, item ID or rank is inferred."
  end
  for _,r in ipairs(a.currentObjectives or {})do if r.finished~=true then return "Quest "..a.questID..": "..r.text.." ("..r.numFulfilled.."/"..r.numRequired.."). Follow this observed objective manually; text does not qualify item IDs, location or cap. Observe results separately."end end
  if a.currentObjectives then return "The observed quest objectives are finished. Verify current quest readiness; do not return or assume cap300 until the separate ready/cap observations confirm them."end
  return "Inspect the current quest "..a.questID.." objectives; no stable objective snapshot is available. Do not assume the reference items/counts or return to the quest giver before readiness is observed."
 end
 if a.questID then return "Verify "..place.." and quest "..a.questID.." ("..a.status.."). Follow current quest objectives manually; beta/historical reference is not current server access. Quest completion does not prove profession cap300. Observe both separately."end
 return "Verify "..target.." at "..place..": "..a.status..". UNKNOWN is not missing, stock, access or learning. "..(a.requiredCharacterLevel and ("Character level "..a.requiredCharacterLevel.." required. ")or "").."No protected action is authorized."
end
function P:GetOperationalRankStep(key,profession)
 local a=self:GetOperationalAccess(key,profession,nil);if not a then return nil end
 return {kind=a.rank and "train"or "verify",profession=key,skill=profession and profession.skill,cap=profession and profession.maxSkill,rank=a.rank,secondaryAccess=a,nextAction=self:OperationalInstruction(a),requiredNextAction="verify",readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
end
function P:AnnotateOperational(key,output,row,profession)
 output.secondaryPrerequisites=output.alchemyPrerequisites;output.alchemyPrerequisites=nil
 output.learningMinimum=row.sourceFact.learningMinimum;output.minimumStatus=row.sourceFact.minimumStatus
 if output.learned~=true then
  local a=self:GetOperationalAccess(key,profession,row.recipeID);output.secondaryAccess=a;output.nextAction=self:OperationalInstruction(a)
  output.requiredNextAction=(a.status=="USE_BOOK_MANUALLY"or a.status=="LEARN_MANUALLY")and "learn-recipe"or (a.status=="BUY_BOOK_MANUALLY"or a.status=="RETRIEVE_BOOK_BANK")and "acquire-recipe"or "verify"
  output.manualCraftBlockedByRecipePrerequisite=true
 end
 local cap=profession.maxSkill;local threshold=cap==75 and 50 or cap==150 and 125 or cap==225 and 225
 if threshold and profession.skill>=threshold and profession.skill<cap then output.rankOpportunity={rank=cap==75 and "Journeyman"or "Expert",necessaryNow=false,requiredSkill=threshold,trainingObserved=false,readOnly=true}end
 local facts=JLP:GetModule("ProfessionPlanningFacts");local live=facts and facts:Observe(key,row.recipeID)
 output.expectedOutputQuantity=live and live.output and live.output.fixed and live.output.itemID==row.sourceFact.output and live.output.minimum or nil
 output.outputYieldStatus=output.expectedOutputQuantity and "CURRENT_FIXED_SCHEMATIC_NOT_OBSERVED_INVENTORY"or "UNKNOWN"
 output.skillGainGuaranteed=false;output.inventoryOutputAllowed=false
 self:AnnotateCookingStation(output,profession)
end
function P:GetOperationalWaypoint(a)
 if type(a)=="table"and a.status=="MANUAL_QUEST_OBJECTIVES"then return self:GetFishingQuestWaypoint(a)end
 local r=type(a)=="table"and secondaryActors[a.actor]
 if not r or not r.mapID or not r.x or not r.y then return nil end
 if type(UnitFactionGroup)~="function"or UnitFactionGroup("player")~="Horde"then return nil end
 return {serviceID="SECONDARY_"..a.actor,kind=r.kind,name=r.name,zone=r.zone,npcID=r.npcID,faction=r.faction,profession=a.profession,recipeID=a.recipeID,teachingItemID=a.itemID,secondaryAccess=true,accessStage=a.status,accessQuestID=a.questID,accessRank=a.rank,sourceQualified=true,state="SOURCE_QUALIFIED",ownerAuthority="FOREVER_ACTOR_REFERENCE_CLASSIC_GEOGRAPHY_NOT_LIVE_ACCESS",sourceURL=r.url or ("https://classicdb.ch/?npc="..r.npcID),nativeDispatchAllowed=false,
  nav={mapID=r.mapID,x=r.x,y=r.y,mapDomain="UI_MAP_ID",evidence=r.positionEvidence or "CLASSIC_ZONE_NORMALIZED_EXPLICIT_70532_UIMAP_JOIN_NOT_CURRENT_FOREVER"}}
end
function P:GetCanonicalWaypoint(source)
 local api=JLP:GetModule("ProfessionAPI");local a=self:GetOperationalAccess(source.profession,api and api:Get(source.profession),source.recipeID)
 if not a or a.status~=source.accessStage or a.itemID~=source.teachingItemID or a.rank~=source.accessRank or a.questID~=source.accessQuestID then return nil end
 return self:GetOperationalWaypoint(a)
end

-- Fishing is an area/manual gathering workflow, never a color/craft forecast.
function P:GetFishingPlan(profession,context)
 local shared=JLP:GetModule("GatheringSharedMapState");local snapshot=shared and shared:GetSnapshot()
 local goal=snapshot and snapshot.supplyGoal;local bridge=JLP:GetModule("GatheringMaterialBridge")
 local supply=goal and goal.professionKey=="FISHING"and bridge and bridge:RefreshSupply(goal)
 local c;local skill=profession and not profession.cached and profession.skill
 if supply then
  -- Producer cap/rank/tool requirements do not gate bank/trade/return actions.
  c={kind=supply.status=="BAGS_READY"and "verify"or "gather",profession="FISHING",skill=skill,
   materialSupply=supply,nextAction=supply.nextAction,requiredNextAction=supply.status=="FISHING_AREA"and "manual-gather"or "verify",
   consumerProfession=goal.ownerProfession,consumerRecipeID=goal.ownerRecipeID}
 elseif not secondaryWhole(skill)then
  c={kind="verify",profession="FISHING",nextAction="Observe current Fishing skill/cap; UNKNOWN is not Apprentice or unlearned."}
 elseif skill>=300 then c={kind="complete",profession="FISHING",skill=skill,nextAction="Fishing skill goal reached. Explicit material gathering remains available."}
 else
  c=self:GetOperationalRankStep("FISHING",profession)
  if not c then
   local map=JLP:GetModule("ForeverFishingMapCanvas");local current=map and map:GetCurrentZone()
   local model=JLP:GetModule("ForeverFishingZoneModel");local ctx=JLP:GetModule("FishingSkillContext")
   local observed=ctx and ctx:FromSnapshot(profession)
   local candidates={};local identities=JLP.data and JLP.data.foreverFishingMapIdentity
   for id in pairs(identities and identities.byMapID or {})do
    local ref=model and model:LookupMap(id,skill,observed and observed.observedBonus or 0)
    if ref and ref.selected and ref.selected.meetsMinimum then candidates[#candidates+1]={mapID=id,reference=ref.selected}end
   end
   table.sort(candidates,function(a,b)
    local al=current and current.mapID==a.mapID;local bl=current and current.mapID==b.mapID
    if al~=bl then return al==true end
    if a.reference.minSkill~=b.reference.minSkill then return a.reference.minSkill>b.reference.minSkill end
    return a.mapID<b.mapID
   end)
   local area=candidates[1]
   c={kind="gather",profession="FISHING",skill=skill,cap=profession.maxSkill,fishingContext=observed,
    fishingArea=area,requiredNextAction=area and "manual-gather"or "verify",expectedCasts=nil,skillUpProbability=nil,
    catchRate=nil,skillGainGuaranteed=false,outputQuantity=nil,sourceStatus="STATIC_ZONE_ELIGIBILITY_NOT_INTERVAL_SKILLUP_PROOF",
    nextAction=area and ("Fish manually in eligible water in "..area.reference.name.."; find a safe accessible bank. Zone eligibility/historical catch areas are not a positive skill-up guarantee or a precise pool/standing point. Observe loot, bags and skill separately; replan after each observation.")or
     "Verify an eligible Fishing area and raw/bonus skill. No qualified precise pool or safe-standing point is available; no cast count or skill-up chance is invented."}
  end
 end
 c.readOnly=true;c.nativeDispatchAllowed=false;c.executionEligible=false
 local travel=JLP:GetModule("CurrentStepTravelBridge");if travel then travel:Attach("FISHING",c)end
 if c.fishingArea and c.navigation and c.navigation.waypointQualified then c.nextAction=c.nextAction.." Qualified approach: "..c.navigation.source.name.."; inspect adjacent eligible water manually. The approach is not a pool or guaranteed physical transport."end
 return {key="FISHING",profession=profession,status=c.kind=="complete"and "complete"or "fishing-advisory",actionKind=c.kind,
  action=c.nextAction,recommendedCurrentStep=c,step=c,materials={},readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  strategy=JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy or "economical",skillUpProbability=nil,expectedCasts=nil}
end


-- Secondary access remains advice. Item creation, placement and consumer focus
-- are separate observations; none of these methods dispatches a native action.
local function accessInventory(id)
 local inv=JLP:GetModule("Inventory");local r=inv and inv:GetOwned(id)or {}
 return r.bagKnown==true and secondaryWhole(r.bags)and r.bags or nil,
  r.bankKnown==true and not r.bankStale and secondaryWhole(r.bank)and r.bank or nil
end
local function accessCall(fn,...)
 if type(fn)~="function"then return nil end
 local ok,a,b,c=pcall(fn,...);if ok then return a,b,c end
end
local function currentIdentity()
 local id=accessCall(UnitGUID,"player")
 return type(id)=="string"and id:match("^Player%-")and id or nil
end
function P:ObserveArtisanObjectives(id)
 if id~=6610 and id~=6607 then return nil end
 local q=type(C_QuestLog)=="table"and C_QuestLog;local fn=q and q.GetQuestObjectives
 local observer=currentIdentity()
 if not observer or secondaryQuest("IsOnQuest",id)~=true or type(fn)~="function"then return nil end
 local function read()
  local rows=accessCall(fn,id);if type(rows)~="table"or #rows==0 then return nil end
  local out={}
  for _,r in ipairs(rows)do
   if type(r)~="table"or type(r.text)~="string"or r.text==""or type(r.type)~="string"or
    type(r.finished)~="boolean"or not secondaryWhole(r.numFulfilled)or not secondaryWhole(r.numRequired)or r.numRequired==0 then return nil end
   out[#out+1]={text=r.text,type=r.type,finished=r.finished,numFulfilled=r.numFulfilled,numRequired=r.numRequired}
  end
  return out
 end
 local a,b=read(),read()
 if not a or not b or #a~=#b or currentIdentity()~=observer or C_QuestLog~=q or q.GetQuestObjectives~=fn or secondaryQuest("IsOnQuest",id)~=true then return nil end
 for i,r in ipairs(a)do for k,v in pairs(r)do if b[i][k]~=v then return nil end end end
 return a -- public API has no itemID; do not infer one from localized text/index
end
local function kitRequirements(id,ordinaryToolItemID)
 local t=type(C_TradeSkillUI)=="table"and C_TradeSkillUI
 local fn=t and t.GetRecipeRequirements;local cd=t and t.GetRecipeCooldown
 if type(fn)~="function"or type(cd)~="function"then return "UNKNOWN"end
 local function read()
  local rows=accessCall(fn,id);if type(rows)~="table"then return "UNKNOWN"end
  local enum=type(Enum)=="table"and type(Enum.RecipeRequirementType)=="table"and Enum.RecipeRequirementType
  for _,r in ipairs(rows)do
   -- DB2 Totem4471 is the ordinary reusable Flint and Tinder for this kit.
   -- Public runtime enum classifies the requirement; no name/locale guessing.
   local ordinary=ordinaryToolItemID==4471 and enum and type(enum.Totem)=="number"and r.type==enum.Totem
   if not ordinary then
    if r.met==false then return "UNMET"elseif r.met~=true then return "UNKNOWN"end
   end
  end
  local remaining=accessCall(cd,id)
  if type(remaining)~="number"or remaining~=remaining or remaining<0 or remaining==math.huge then return "UNKNOWN"end
  return remaining>0 and "COOLDOWN_ACTIVE"or "MET"
 end
 local a,b=read(),read()
 return a==b and C_TradeSkillUI==t and t.GetRecipeRequirements==fn and t.GetRecipeCooldown==cd and a or "UNKNOWN"
end
function P:BuildCookingStationPreparation(c,profession)
 local f=c and c.secondaryPrerequisites;local definitions=JLP.data and JLP.data.cooking and JLP.data.cooking.stationPreparation
 local d=f and definitions and definitions[f.focusID]
 if not d or c.stationStatus=="MET"or c.learned~=true or c.bagReady~=true or c.manualCraftBlockedBySourceConflict or c.manualCraftBlockedByOutputConflict then return nil end
 local mode=JLP.DB and JLP.DB.profile and JLP.DB.profile.cookingStationPreparation or "EXISTING"
 local r={focusID=f.focusID,itemID=d.itemID,craftSpellID=d.craftSpellID,useSpellID=d.useSpellID,
  mode=mode,materials={},status="INSPECT_EXISTING_STATION",nativeDispatchAllowed=false,readOnly=true,consumerReadiness=c.stationStatus,
  sourceURL=d.sourceURL,inventoryOutputAllowed=false,skillGainGuaranteed=false}
 local closure=JLP.data and JLP.data.foreverSecondaryLeveling
 local reference=closure and closure.professions and closure.professions.COOKING and closure.professions.COOKING.kitUseReference
 if d.itemID==279981 and reference and reference.itemID==d.itemID and reference.useSpellID==d.useSpellID then r.useReference=reference end
 if mode~="KIT"then return r end
 if not profession or profession.cached or not secondaryWhole(profession.skill)then r.status="OBSERVE_PROFESSION";return r end
 if profession.skill<d.useMinimum then r.status="PLACEMENT_SKILL_UNMET";return r end
 local workspace=JLP:GetModule("SecondaryWorkspace")
 local receipt=workspace and workspace.GetCookingUseReceipt and workspace:GetCookingUseReceipt(c,d)
 if receipt then r.status="VERIFY_CONSUMER_AFTER_KIT_USE";r.useReceipt=receipt;return r end
 local bags,bank=accessInventory(d.itemID);r.bags=bags;r.bank=bank
 if bags==nil then r.status="OBSERVE_KIT_INVENTORY";return r end
 if bags>0 then
  if d.itemID==279981 and (not r.useReference or r.useReference.allowsCooking~=true)then r.status="VERIFY_KIT_USE_PURPOSE";return r end
  local item=type(C_Item)=="table"and C_Item
  local _,spell=accessCall(item and item.GetItemSpell,d.itemID)
  if spell~=d.useSpellID then r.status="VERIFY_CURRENT_ITEM_USE";return r end
  local start,duration,enabled=accessCall(item and item.GetItemCooldown,d.itemID)
  local clock=accessCall(GetTime)
  if type(start)~="number"or type(duration)~="number"or start~=start or duration~=duration or start<0 or duration<0 or start==math.huge or duration==math.huge or enabled~=true or type(clock)~="number"or clock~=clock or clock<0 or clock==math.huge then r.status="VERIFY_ITEM_COOLDOWN";return r end
  if start>0 and start+duration>clock then r.status="PLACEMENT_COOLDOWN_ACTIVE";return r end
  local usable=accessCall(item and item.IsUsableItem,d.itemID)
  r.status=usable==true and "PLACE_MANUALLY_VERIFY_LOCATION"or usable==false and "ITEM_CURRENTLY_UNUSABLE"or "VERIFY_ITEM_USABILITY"
  r.placementFocusID=d.placementFocusID
  return r -- usability is not ground-location or consumer-station readiness
 end
 if bank==nil then r.status="OBSERVE_KIT_BANK";return r end
 if bank>0 then r.status="RETRIEVE_KIT_BANK";return r end
 local facts=JLP:GetModule("ProfessionPlanningFacts");local live=facts and facts:Observe("COOKING",d.craftSpellID)
 if not live or not live.observed or live.learned~=true then r.status="VERIFY_KIT_LEARNING";return r end
 local inputs=live.requiredReagents;local count=0
 for _ in pairs(inputs or {})do count=count+1 end
 if count~=#d.reagents then r.status="VERIFY_KIT_INPUTS";return r end
 for _,v in ipairs(d.reagents)do if inputs[v.itemID]~=v.quantity then r.status="VERIFY_KIT_INPUTS";return r end end
 if not live.output or not live.output.fixed or live.output.itemID~=d.itemID then r.status="VERIFY_KIT_OUTPUT";return r end
 r.expectedOutputQuantity=live.output.minimum;r.casts=1
 local ready=true;local known=true;local bankAvailable=false;local bankUnknown=false
 for _,v in ipairs(d.reagents)do
  local n,b=accessInventory(v.itemID)
  r.materials[#r.materials+1]={itemID=v.itemID,name=v.name,quantity=v.quantity,required=v.quantity,source=v.source,bags=n,bank=b,bagsKnown=n~=nil,missing=n and math.max(0,v.quantity-n)or nil}
  if n==nil then known=false elseif n<v.quantity then ready=false;if b and b>0 then bankAvailable=true elseif b==nil then bankUnknown=true end end
 end
 r.status=not known and "OBSERVE_PREPARATION_INVENTORY"or not ready and (bankAvailable and "RETRIEVE_PREPARATION_BANK"or bankUnknown and "OBSERVE_PREPARATION_BANK"or "ACQUIRE_PREPARATION_MATERIALS")or "CRAFT_KIT_MANUALLY"
 if r.status=="CRAFT_KIT_MANUALLY"then local requirement=kitRequirements(d.craftSpellID,d.ordinaryToolItemID);if requirement~="MET"then r.status="VERIFY_KIT_REQUIREMENTS_"..requirement end end
 -- Re-read the current panel/recipe after prerequisites; a character/panel
 -- change cannot turn a previously observed kit recipe into craft advice.
 local after=facts:Observe("COOKING",d.craftSpellID)
 local sameInputs=type(after.requiredReagents)=="table";local afterCount=0
 for _ in pairs(after.requiredReagents or {})do afterCount=afterCount+1 end
 if afterCount~=#d.reagents then sameInputs=false end
 for _,v in ipairs(d.reagents)do if not after.requiredReagents or after.requiredReagents[v.itemID]~=v.quantity then sameInputs=false end end
 if not sameInputs or not after.observed or after.learned~=true or after.skill~=live.skill or not after.output or not after.output.fixed or after.output.itemID~=d.itemID or after.output.minimum~=r.expectedOutputQuantity then r.status="REOBSERVE_KIT_RECIPE";r.materials={} end
 return r
end
function P:GetCookingStationPreparation(c,profession)
 local observer=currentIdentity()
 local r=self:BuildCookingStationPreparation(c,profession)
 if r and r.mode=="KIT"and (not observer or currentIdentity()~=observer)then
  r.status="REOBSERVE_CHARACTER";r.materials={};r.expectedOutputQuantity=nil
 end
 return r
end
function P:AnnotateCookingStation(c,profession)
 local r=self:GetCookingStationPreparation(c,profession);if not r then return end
 c.stationPreparation=r;c.requiredNextAction="verify";c.manualCraftBlockedByRecipePrerequisite=true
 local goal=c.craftInstruction or ("Craft "..tostring(c.remainingCrafts or 1).." "..tostring(c.recipe))
 local instruction
 if r.mode~="KIT"then instruction="Inspect an existing required cooking station; or explicitly select Prepare station kit in Cooking. Trainer location alone is not station proof."
 elseif r.status=="PLACE_MANUALLY_VERIFY_LOCATION"then instruction=(r.itemID==279981 and "Use Basic Campfire Kit manually to place a cooking campfire"or "Place item "..r.itemID.." manually").." at a location allowed by the game"..(r.placementFocusID and ("; placement itself requires focus "..r.placementFocusID)or "")..". Then observe the CONSUMER recipe requirements again; placement/cast success is not station readiness."
 elseif r.status=="VERIFY_CONSUMER_AFTER_KIT_USE"then instruction="A matched manual kit-use cast was observed. Reopen/inspect this consumer recipe's current station requirement. UNKNOWN/UNMET is not MET; do not produce another kit automatically. To retry preparation explicitly choose Prepare station kit again."
 elseif r.status=="CRAFT_KIT_MANUALLY"then instruction="Craft ONE station kit (spell "..r.craftSpellID..") manually; observe item "..r.itemID.." in bags before placement. Expected output is not inventory."
 elseif r.status=="ACQUIRE_PREPARATION_MATERIALS"then instruction="Acquire the listed materials for ONE selected station-kit cast manually; use qualified vendor/bank/trade sources, observe delivery."
 elseif r.status=="RETRIEVE_KIT_BANK"or r.status=="RETRIEVE_PREPARATION_BANK"then instruction="Withdraw the observed station kit/materials from bank manually; observe bags before crafting or placement."
 else instruction="Verify selected station preparation: "..r.status..". Do not assume placement, output or station readiness."end
 c.nextAction=goal..". Prerequisite: "..instruction
end
function P:GetFishingApproach(mapID,itemID,serviceID,required,consumer)
 local rows=JLP.data and JLP.data.fishingCatchAreaReference and JLP.data.fishingCatchAreaReference.approaches
 local identities=JLP.data and JLP.data.foreverFishingMapIdentity
 if not identities or not identities.byMapID or not identities.byMapID[mapID]or type(UnitFactionGroup)~="function"or UnitFactionGroup("player")~="Horde"then return nil end
 local api=JLP:GetModule("ProfessionAPI");local p=api and api:Get("FISHING")
 if not p or p.cached or not secondaryWhole(p.skill)then return nil end
 local model=JLP:GetModule("ForeverFishingZoneModel");local ctx=JLP:GetModule("FishingSkillContext");local skill=ctx and ctx:FromSnapshot(p)
 local ref=model and model:LookupMap(mapID,p.skill,skill and skill.observedBonus or 0)
 if not ref or not ref.selected or not ref.selected.meetsMinimum then return nil end
 local keys={};for id in pairs(rows or {})do keys[#keys+1]=id end;table.sort(keys)
 for _,id in ipairs(keys)do
  local r=rows[id];local match=itemID==nil
  for _,v in ipairs(r.items or {})do if v==itemID then match=true end end
  if match and r.mapID==mapID and (not serviceID or serviceID=="FISH_APPROACH_"..id)then
   return {serviceID="FISH_APPROACH_"..id,name=r.name,zone=r.zone,kind="fishing_approach",profession="FISHING",npcID=r.npcID,
    fishingApproach=true,pointType=r.pointType,materialItemID=itemID,materialRequired=required,materialConsumer=consumer,
    geometryType="QUALIFIED_APPROACH_NOT_POOL",sourceURL=r.sourceURL,sourceQualified=true,state="SOURCE_QUALIFIED",
    ownerAuthority="FOREVER_GUIDE_APPROACH_CLASSIC_NORMALIZED_POSITION_NOT_CURRENT_CATCH_OR_SAFE_TRANSPORT",
    nativeDispatchAllowed=false,nav={mapID=r.mapID,x=r.x,y=r.y,mapDomain="UI_MAP_ID",evidence=r.positionEvidence}}
  end
 end
 if itemID then
  for _,r in ipairs(self:GetFishingSpeciesZones(itemID))do
   if r.mapID==mapID then
    local s=self:GetFishingZoneApproach(mapID,{materialItemID=itemID,materialRequired=required,materialConsumer=consumer})
    if s and (not serviceID or s.serviceID==serviceID)then return s end
   end
  end
 end
end
function P:GetCanonicalFishingApproach(source)
 if type(source)~="table"or source.fishingApproach~=true then return nil end
 if source.questID==6607 then
  local api=JLP:GetModule("ProfessionAPI");local a=self:GetOperationalAccess("FISHING",api and api:Get("FISHING"))
  return self:GetFishingQuestWaypoint(a)
 end
 if source.materialItemID then
  local shared=JLP:GetModule("GatheringSharedMapState");local snapshot=shared and shared:GetSnapshot();local goal=snapshot and snapshot.supplyGoal
  if not goal or goal.professionKey~="FISHING"or goal.itemID~=source.materialItemID or goal.required~=source.materialRequired then return nil end
  local bridge=JLP:GetModule("GatheringMaterialBridge");local current=bridge and bridge:RefreshSupply(goal)
  if not current or current.status~="FISHING_AREA"or current.mapID~=source.nav.mapID or source.materialConsumer~=current.consumerProfession then return nil end
 else
  local api=JLP:GetModule("ProfessionAPI");local p=api and api:Get("FISHING");local plan=self:GetFishingPlan(p)
  local c=plan and plan.recommendedCurrentStep
  if not c or not c.fishingArea or c.fishingArea.mapID~=source.nav.mapID then return nil end
 end
 return self:GetFishingApproach(source.nav.mapID,source.materialItemID,source.serviceID,source.materialRequired,source.materialConsumer)
end

function P:GetFishingSpeciesZones(itemID)
 local f=JLP.data and JLP.data.foreverSecondaryLeveling and JLP.data.foreverSecondaryLeveling.fishing
 local r=f and f.speciesZoneReferences and f.speciesZoneReferences[itemID]
 local out={}
 if not r or r.operationalAreaQualified~=true then return out end
 for _,mapID in ipairs(r and r.mapIDs or {})do
  out[#out+1]={mapID=mapID,itemID=itemID,name=r.name,zoneRelationQualified=true,
   zoneRelationURL=r.sourceURL,zoneRelationEvidence=r.evidence,geometryType="NAMED_ZONE_AREA"}
 end
 return out
end
function P:GetFishingZoneApproach(mapID,scope)
 local f=JLP.data and JLP.data.foreverSecondaryLeveling and JLP.data.foreverSecondaryLeveling.fishing
 local r=f and f.zoneApproachReferences and f.zoneApproachReferences[mapID]
 if not r or type(UnitFactionGroup)~="function"or UnitFactionGroup("player")~="Horde"then return nil end
 local api=JLP:GetModule("ProfessionAPI");local p=api and api:Get("FISHING")
 if not p or p.cached or not secondaryWhole(p.skill)then return nil end
 local ctx=JLP:GetModule("FishingSkillContext");local obs=ctx and ctx:FromSnapshot(p)
 local model=JLP:GetModule("ForeverFishingZoneModel");local ref=model and model:LookupMap(mapID,p.skill,obs and obs.observedBonus or 0)
 -- A quest-zone approach is geography, not permission to fish in every water
 -- subtype (STV/Jaguero deliberately has no whole-zone eligibility binding).
 if (not ref or not ref.selected or not ref.selected.meetsMinimum)and not(scope and scope.questID==6607)then return nil end
 local resolver=JLP:GetModule("SourceResolver");local base
 if r.provider=="OWNER_SERVICE"then base=resolver and resolver:GetQualifiedServiceWaypoint(r.category,r.serviceID)
 elseif r.provider=="SECONDARY_ACTOR"then
  local a=secondaryActors[r.actor]
  if a then base={name=a.name,npcID=a.npcID,serviceID="SECONDARY_"..r.actor,nav={mapID=a.mapID,x=a.x,y=a.y,mapDomain="UI_MAP_ID",evidence=a.positionEvidence or "CLASSIC_ZONE_NORMALIZED_EXPLICIT_70532_UIMAP_JOIN_NOT_CURRENT_FOREVER"}}end
 end
 local n=base and base.nav
 if not n or n.mapID~=mapID or n.mapDomain~="UI_MAP_ID"or type(n.x)~="number"or type(n.y)~="number"then return nil end
 local s={serviceID="FISH_ZONE_"..mapID.."_"..base.serviceID,kind="fishing_approach",name=r.zone.." zone approach near "..base.name,
  zone=r.zone,npcID=base.npcID,profession="FISHING",faction="Horde",fishingApproach=true,zoneApproach=true,
  pointType="QUALIFIED_ZONE_APPROACH_NOT_SPECIES_PIN",geometryType="QUALIFIED_ZONE_APPROACH_NOT_SPECIES_PIN",
  sourceQualified=true,state="SOURCE_QUALIFIED",ownerAuthority="EXISTING_CANONICAL_GEOGRAPHY_ZONE_APPROACH_NOT_WATER_POOL_OR_SAFE_ROUTE",
  nativeDispatchAllowed=false,nav={mapID=n.mapID,x=n.x,y=n.y,mapDomain=n.mapDomain,evidence=n.evidence}}
 for k,v in pairs(scope or {})do s[k]=v end
 return s
end
function P:BindFishingQuestAreas(a)
 local f=JLP.data and JLP.data.foreverSecondaryLeveling and JLP.data.foreverSecondaryLeveling.fishing
 local ref=f and f.artisanQuest and f.artisanQuest.objectiveReference
 if not ref then return end
 local map=type(C_Map)=="table"and accessCall(C_Map.GetBestMapForUnit,"player")
 for _,r in ipairs(a.currentObjectives or {})do
  local match
  for _,v in ipairs(ref.objectives)do
   if r.text:lower():find(v.name:lower(),1,true)then
    if match then match=nil;break end
    match=v
   end
  end
  if match then
   -- This text join qualifies a named AREA only, never a current objective itemID.
   r.areaReference={key=match.key,name=match.name,area=match.area,zone=match.zone,mapID=match.mapID,sourceURL=ref.sourceURL,evidence=ref.evidence}
   if not r.finished and (not a.questObjective or match.mapID==map and a.questObjective.areaReference.mapID~=map)then a.questObjective=r end
  end
 end
end
function P:GetFishingQuestWaypoint(a)
 local r=a and a.status=="MANUAL_QUEST_OBJECTIVES"and a.questID==6607 and a.questObjective
 local ref=r and r.areaReference
 local observer=currentIdentity()
 if not ref or not observer then return nil end
 return self:GetFishingZoneApproach(ref.mapID,{questID=6607,questObjectiveKey=ref.key,questObjectiveText=r.text,
  questNumFulfilled=r.numFulfilled,questNumRequired=r.numRequired,observerGUID=observer,sourceURL=ref.sourceURL})
end

JLP:RegisterModule("SecondaryLevelingPlanner",P)
