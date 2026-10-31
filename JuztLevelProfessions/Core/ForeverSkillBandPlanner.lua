local _, JLP = ...
-- Advisory skill-band view for the actual source-prioritized Forever route.
-- Recipe/reagent IDs and amounts come from curated Forever rows where available;
-- progression intervals, craft counts, and trainer detours are still RESEARCH estimates.
-- Unknown rows never become verified shopping requirements or native authority.
local S={contract="forever-skill-band-plan-v1",nativeDispatchAllowed=false,
    executionEligible=false,persisted=false,requiresLiveQA=false}
local function clone(v,limit)
    if type(v)~="table" then return v end
    limit=(limit or 0)+1
    if limit>20 then return nil end
    local copy={}
    for k,x in pairs(v) do copy[k]=clone(x,limit) end
    return copy
end
local function cleanmode(mode) return (mode=="aggressive" or mode=="fastest") and "aggressive" or "normal" end
local function isinteger(n) return type(n)=="number" and n==math.floor(n) end
local function appendRange(out,startSkill,stopSkill,state,step)
    if startSkill>=stopSkill then return end
    local last=out[#out]
    if last and last.toSkill==startSkill and last.state==state and last.stepIndex==step then
        last.toSkill=stopSkill
    else out[#out+1]={fromSkill=startSkill,toSkill=stopSkill,state=state,stepIndex=step} end
end
local function displayState(step)
    if step.referenceStatus=="WOWHEAD_FOREVER_AUTHORITATIVE" then
        if step.skillGateConflict then return "SOURCE_SKILL_GATE_CONFLICT" end
        if step.requiredSkillAuthority~="WOWHEAD_FOREVER" then return "FOREVER_MATERIALS_RESEARCH_SKILL" end
        return "FOREVER_MATERIALS_SOURCE_SKILL"
    end
    return "RESEARCH_ONLY"
end
function S:Build(professionKey,mode)
    local authority=JLP:GetModule("ForeverRecipeAuthority")
    local key=tostring(professionKey or ""):upper()
    local raw,err=authority and authority:GetEffectiveRoute(key,mode)
    if not raw then return nil,err or "NO_EFFECTIVE_RESEARCH_ROUTE" end
    local result={contract=self.contract,professionKey=key,mode=cleanmode(mode),
        source="WOWHEAD_FOREVER_RECIPE_FIRST",routeAuthority="RESEARCH_ESTIMATED_SKILL_BANDS",
        nativeDispatchAllowed=false,executionEligible=false,production=false,
        steps={},trainers={},coverage={},materials={},materialsByItemID={},
        sourceMatched=0,sourceOnlyMaterials=0,sourceSkillGates=0,sourceSkillConflicts=0,
        researchOnly=0,invalidSteps=0,gaps={},knownMaterialsComplete=false,
        estimatedSkillGainOnly=true,optimized=false}
    local coverageBySkill={}
    local totals={}
    for _,step in ipairs(raw.steps or {}) do
        if step.kind=="train" then
            result.trainers[#result.trainers+1]={tier=step.tier,skillCapFrom=step.skillCapFrom,
                skillCapTo=step.skillCapTo,minCharacterLevel=step.minCharacterLevel,
                authority="HISTORICAL_GUIDE_NOT_FOREVER_VERIFIED"}
        elseif step.kind=="craft" then
            local lo,hi=tonumber(step.skillMin),tonumber(step.skillTarget)
            local count=tonumber(step.expectedCrafts)
            local validRange=isinteger(lo) and isinteger(hi) and hi>lo and hi<=300 and lo>=0
            local validCount=isinteger(count) and count>0
            local state=displayState(step)
            if not validRange or not validCount then state="INVALID_RESEARCH_STEP";result.invalidSteps=result.invalidSteps+1 end
            local resolver=JLP:GetModule("RecipeDifficulty")
            local eligibility=resolver and resolver.AssessProgression and
                resolver:AssessProgression(key,step,lo,hi) or
                {status="MINIMUM_SKILL_UNVERIFIED",progressionAllowed=true,
                 progressionQualified=false}
            if eligibility.minimumSkill and eligibility.minimumSkill<300 and
               lo and eligibility.minimumSkill>lo and hi and eligibility.minimumSkill<hi then
                -- Only the remaining interval has qualified minimum-skill access.
                eligibility=resolver:AssessProgression(key,step,eligibility.minimumSkill,hi)
            end
            if not eligibility.progressionAllowed then
                state="SKILL_ELIGIBILITY_GAP"
                result.invalidSteps=result.invalidSteps+1
            end
            local row={kind="craft",recipe=step.recipe,recipeID=step.recipeID,
                skillMin=lo,skillTarget=hi,expectedCrafts=count,
                estimatedCrafts=true,skillBandProvenance="HISTORICAL_RESEARCH",
                referenceStatus=step.referenceStatus,sourceRequirement=clone(step.sourceRequirement),recipeSource=clone(step.recipeSource),sourceURL=step.recipeReferenceURL,
                sourceBuild=step.recipeReferenceBuild,requiredSkill=step.requiredSkill,
                requiredSkillAuthority=step.requiredSkillAuthority,
                gateConflict=step.skillGateConflict==true,state=state,
                skillEligibility=clone(eligibility),skillEligibilityStatus=eligibility.status,
                nativeDispatchAllowed=false,executionEligible=false,materials={},
                materialTotalsVerified=step.referenceStatus=="WOWHEAD_FOREVER_AUTHORITATIVE" and validCount and
                    validRange and eligibility.progressionAllowed and
                    (not eligibility.minimumSkill or eligibility.minimumSkill<=lo)}
            if row.materialTotalsVerified then
                -- Counts are incremented only AFTER the full reagent set
                -- has passed the atomic-validation stage below.
                -- P0-223: stage the entire reagent set before committing ANY
                -- total.  One malformed/duplicate entry must not silently
                -- reduce the forecast's material needs or poison other rows.
                -- Quantities are research-CRAFT-COUNT estimates, not owned
                -- stock, verified consumption or a native material receipt.
                local pending,seen={},{}
                if type(step.requirements)~="table" or #step.requirements==0 then
                    row.materialTotalsVerified=false
                else
                    for _,m in ipairs(step.requirements) do
                        if type(m)=="table" and isinteger(m.itemID) and m.itemID>0 and
                            isinteger(m.quantity) and m.quantity>0 and
                            isinteger(m.perCraft) and m.perCraft>0 and
                            m.perCraft<=100000 and count<=100000 and
                            m.perCraft*count==m.quantity and not seen[m.itemID] then
                            seen[m.itemID]=true
                            pending[#pending+1]={itemID=m.itemID,name=m.name,
                                quantity=m.quantity,perCraft=m.perCraft,
                                sourceURL=m.sourceURL,authority="WOWHEAD_FOREVER",
                                quantityProvenance="HISTORICAL_EXPECTED_CRAFTS_ESTIMATE"}
                        else
                            row.materialTotalsVerified=false
                            break
                        end
                    end
                end
                if row.materialTotalsVerified then
                    result.sourceMatched=result.sourceMatched+1
                    if step.requiredSkillAuthority=="WOWHEAD_FOREVER" then
                        result.sourceSkillGates=result.sourceSkillGates+1
                    else result.sourceOnlyMaterials=result.sourceOnlyMaterials+1 end
                    if step.skillGateConflict then result.sourceSkillConflicts=result.sourceSkillConflicts+1 end
                    row.materials=pending
                    for _,m in ipairs(pending) do
                        local total=totals[m.itemID]
                        if not total then
                            total={itemID=m.itemID,name=m.name,quantity=0,
                                source="WOWHEAD_FOREVER_REFERENCED_STEPS",
                                quantityProvenance="HISTORICAL_EXPECTED_CRAFTS_ESTIMATE"}
                            totals[m.itemID]=total
                        end
                        total.quantity=total.quantity+m.quantity
                    end
                else
                    row.materials={}
                    row.materialsUnknown=true
                    state="REAGENT_PROOF_INCOMPLETE"
                    row.state=state
                    result.researchOnly=result.researchOnly+1
                end
            else
                result.researchOnly=result.researchOnly+1
                row.legacyRequirementsAvailable=type(step.requirements)=="table"
                row.materialsUnknown=true
            end
            result.steps[#result.steps+1]=row
            local index=#result.steps
            if validRange then
                for skill=math.max(lo,1),math.min(hi-1,299) do
                    local allowed=eligibility.progressionAllowed and
                        (not eligibility.minimumSkill or skill>=eligibility.minimumSkill)
                    local positionState=allowed and state or "SKILL_ELIGIBILITY_GAP"
                    if coverageBySkill[skill]==nil then
                        coverageBySkill[skill]={state=positionState,stepIndex=allowed and index or nil}
                    else coverageBySkill[skill]={state="OVERLAPPING_RESEARCH_STEPS",stepIndex=nil} end
                end
            end
        end
    end
    for skill=1,299 do
        local slot=coverageBySkill[skill] or {state="RESEARCH_GAP",stepIndex=nil}
        appendRange(result.coverage,skill,skill+1,slot.state,slot.stepIndex)
    end
    local covered=0
    for _,range in ipairs(result.coverage) do
        if range.state=="RESEARCH_GAP" or range.state=="SKILL_ELIGIBILITY_GAP" or
            range.state=="OVERLAPPING_RESEARCH_STEPS" or range.state=="REAGENT_PROOF_INCOMPLETE" then
            result.gaps[#result.gaps+1]=clone(range)
        elseif range.state:find("FOREVER_MATERIALS",1,true) then covered=covered+(range.toSkill-range.fromSkill) end
    end
    result.foreverReferencedSkillSpan=covered
    for _,row in pairs(totals) do result.materials[#result.materials+1]=row;result.materialsByItemID[row.itemID]=row end
    table.sort(result.materials,function(a,b) return a.itemID<b.itemID end)
    result.knownMaterialsComplete=result.researchOnly==0 and result.invalidSteps==0 and #result.gaps==0 and result.sourceSkillConflicts==0
    -- "complete" means only all rows of a research plan have curated direct reagent totals.
    -- Never call it a verified, optimized 1-300 leveling guide.
    result.routeOptimized=false
    return result
end
-- Compare an external reagent window with the separately shipped DB70450
-- recipe relation, if available. A source/DB conflict is a reason for manual
-- verification, NOT a claim that the historical DB overrides Forever.
-- This is a field-parity check, not a build allowlist or execution gate.
local function reagentDBParity(key,recipeID,materials)
    local raw=JLP.data and JLP.data.build70450Recipes
    local profession=raw and raw.professions and raw.professions[key]
    if not profession or type(profession.packed)~="string" then return "NOT_AVAILABLE" end
    for line in profession.packed:gmatch("[^\n]+") do
        if tonumber(line:match("^(%d+)%^"))==recipeID then
            local parts={}
            for col in (line.."^"):gmatch("([^%^]*)%^") do parts[#parts+1]=col end
            local field=parts[10]
            if type(field)~="string" or field=="" then return "DB70450_REAGENT_UNPARSEABLE" end
            local expected={};local n=0
            for token in field:gmatch("[^,]+") do
                local id,qty=token:match("^(%d+):(%d+)$")
                id,qty=tonumber(id),tonumber(qty)
                if not id or not qty or qty<1 or expected[id] then return "DB70450_REAGENT_UNPARSEABLE" end
                expected[id]=qty;n=n+1
            end
            if n~=#materials then return "DB70450_REAGENT_CONFLICT" end
            for _,m in ipairs(materials) do
                if expected[m.itemID]~=m.quantity then return "DB70450_REAGENT_CONFLICT" end
            end
            return "DB70450_REAGENT_PARITY"
        end
    end
    return "DB70450_RECIPE_NOT_FOUND"
end

-- P0-220: a bounded, source-labeled chain of FUTURE RESEARCH windows.  This
-- does not invent a path across missing research, skill-gate conflicts or
-- missing reagents.  A fixed recipe minimum is NOT an orange/yellow/green
-- probability and a research window is not a verified skill-up progression.
-- Call on demand (PlanTo300 / route view), never in each Current Step repaint.
function S:BuildContinuity(key,fromSkill,mode)
    fromSkill=tonumber(fromSkill)
    if not isinteger(fromSkill) or fromSkill<1 or fromSkill>299 then
        return nil,"SKILL_OUTSIDE_1_299" end
    local plan,err=self:Build(key,mode)
    if not plan then return nil,err end
    local out={contract="JLP-SOURCE-WINDOW-CONTINUITY-220",professionKey=plan.professionKey,
        fromSkill=fromSkill,targetSkill=300,readOnly=true,forecastOnly=true,
        skillUpGuaranteed=false,nativeDispatchAllowed=false,executionEligible=false,
        verifiedSkillUps=0,segments={},sourceSkillPositions=0,
        materialOnlyPositions=0,unqualifiedPositions=0,
        firstUnresolved=nil,continuousVerifiedRoute=false,
        sourceWindowCoverageIsNotLiveSkillUp=true}
    for _,range in ipairs(plan.coverage or {}) do
        if range.toSkill>fromSkill then
            local lo=math.max(fromSkill,range.fromSkill)
            local hi=range.toSkill
            local step=range.stepIndex and plan.steps[range.stepIndex] or nil
            local tier=(range.state=="FOREVER_MATERIALS_SOURCE_SKILL" and
                step and step.materialTotalsVerified and
                step.requiredSkillAuthority=="WOWHEAD_FOREVER") and
                "SOURCE_SKILL_AND_REAGENTS" or
                (range.state=="FOREVER_MATERIALS_RESEARCH_SKILL" and
                "REAGENTS_ONLY_WINDOW_UNVERIFIED") or "SOURCE_OR_SKILL_GAP"
            local item={fromSkill=lo,toSkill=hi,referenceState=range.state,
                proofTier=tier,recipeID=step and step.recipeID or nil,
                recipe=step and step.recipe or nil,
                recipeSourceURL=step and step.sourceURL or nil,
                learningState="NOT_OBSERVED",skillUpOutcome="UNVERIFIED",
                researchWindow=true,estimatedCraftsOnly=true,
                manualVerificationRequired=true,navigationQualified=false,
                nativeDispatchAllowed=false,reagentsPerCraft={}}
            -- Per-craft ingredients are only displayable when a source-backed
            -- step survived the complete public-route check.  Historical
            -- total budgets and actual inventory never appear as owned stock.
            if step and step.materialTotalsVerified and tier~="SOURCE_OR_SKILL_GAP" then
                local valid=true
                for _,mat in ipairs(step.materials or {}) do
                    if not (isinteger(mat.itemID) and mat.itemID>0 and
                      isinteger(mat.perCraft) and mat.perCraft>0 and
                      type(mat.sourceURL)=="string") then valid=false;break end
                    item.reagentsPerCraft[#item.reagentsPerCraft+1]={
                        itemID=mat.itemID,name=mat.name,quantity=mat.perCraft,
                        sourceURL=mat.sourceURL,knownInBags=false,
                        nativeDispatchAllowed=false}
                end
                if not valid or #item.reagentsPerCraft==0 then
                    item.reagentsPerCraft={};item.proofTier="SOURCE_OR_SKILL_GAP"
                    item.referenceState="REAGENT_PROOF_INCOMPLETE"
                else
                    item.dbReagentParity=reagentDBParity(key,item.recipeID,item.reagentsPerCraft)
                    if item.dbReagentParity=="DB70450_REAGENT_CONFLICT" or
                        item.dbReagentParity=="DB70450_REAGENT_UNPARSEABLE" then
                        item.reagentsPerCraft={};item.proofTier="SOURCE_OR_SKILL_GAP"
                        item.referenceState="EXTERNAL_DB70450_REAGENT_CONFLICT_VERIFY"
                    end
                end
            end
            -- P0-224: join existing exact source-output/learning references on
            -- demand. Never promote a historical skill window to a verified route.
            if item.recipeID and item.proofTier~="SOURCE_OR_SKILL_GAP" then
                local graph=JLP:GetModule("CrossProfessionDependencyPlanner")
                if graph and type(graph.Resolve)=="function" then
                    local ok,producer=pcall(graph.Resolve,graph,key,item.recipeID)
                    if ok and producer and producer.primarySourceParity=="EXACT_SPELL_OUTPUT_REAGENTS_NAME" and
                       producer.primarySourceURL==item.recipeSourceURL then
                        item.outputEvidence={itemID=producer.outputItemID,
                            perCraft=producer.outputPerCraft,
                            proof="EXACT_EXTERNAL_DB_SOURCE_PARITY",
                            quantityVerifiedLive=false,readOnly=true}
                    end
                end
                local sources=JLP:GetModule("RecipeSourcePlanningBridge")
                if sources and type(sources.ForRecipe)=="function" then
                    local ok,lead=pcall(sources.ForRecipe,sources,key,item.recipeID,item.recipe)
                    if ok and type(lead)=="table" and lead.recipeID==item.recipeID and
                       lead.professionKey==key then
                        item.learningEvidence={state=lead.state,
                            teachingItemCount=lead.teachingItemCount or 0,
                            sourceCandidateCount=lead.sourceCandidateCount or 0,
                            navigationQualified=false,trainerStockVerified=false,
                            readOnly=true}
                    end
                end
            end
            -- P0-225: explicit field-by-field readiness of the SAME contiguous
            -- research window. The actor identity does not prove inventory,
            -- trainer stock, navigation, actual difficulty or a skill gain.
            -- This record is never a production permission or an optimised route.
            local matrix={recipeIdentity=item.recipeID and item.recipeSourceURL and
                    "EXTERNAL_RECIPE_REFERENCE" or "MISSING",
                skillMinimum=item.proofTier=="SOURCE_SKILL_AND_REAGENTS" and
                    "FOREVER_MINIMUM_REFERENCED" or "UNQUALIFIED",
                reagentSet=#item.reagentsPerCraft>0 and
                    item.proofTier~="SOURCE_OR_SKILL_GAP" and
                    "SOURCE_DB_PARITY_CHECKED" or "UNQUALIFIED",
                outputYield=item.outputEvidence and "EXACT_SOURCE_YIELD" or "UNKNOWN",
                learningAccess="UNVERIFIED",workstation="UNKNOWN",
                liveDifficulty="NOT_OBSERVED",craftEvent="NOT_OBSERVED",
                skillUp="NOT_OBSERVED",routeVerified=false}
            if item.dbReagentParity=="NOT_AVAILABLE" or
               item.dbReagentParity=="DB70450_RECIPE_NOT_FOUND" then
                matrix.reagentSet="SOURCE_ONLY_DB_JOIN_UNAVAILABLE"
            end
            if item.outputEvidence then
                matrix.workstation="SOURCE_STATION_UNKNOWN"
                local graph=JLP:GetModule("CrossProfessionDependencyPlanner")
                local ok,producer=false,nil
                if graph and type(graph.Resolve)=="function" then
                    ok,producer=pcall(graph.Resolve,graph,key,item.recipeID)
                end
                if ok and producer and producer.primarySourceURL==item.recipeSourceURL and
                    producer.primarySourceParity=="EXACT_SPELL_OUTPUT_REAGENTS_NAME" then
                    if type(producer.primarySourceStationKind)=="string" and
                        producer.primarySourceStationKind~="" then
                        matrix.workstation="EXTERNAL_STATION_REFERENCE"
                        item.workstationReference={kind=producer.primarySourceStationKind,
                            verifiedLive=false,navigationQualified=false,readOnly=true}
                    end
                    local actors={};local seen={}
                    for _,actor in ipairs(producer.primarySourcePartialNPCReferences or {}) do
                        if type(actor)=="table" and type(actor.npcID)=="number" and
                            actor.npcID>0 and type(actor.name)=="string" and
                            actor.name~="" and not seen[actor.npcID] then
                            seen[actor.npcID]=true
                            actors[#actors+1]={npcID=actor.npcID,name=actor.name,
                                faction=actor.faction,zone=actor.zone,
                                referenceURL=actor.referenceURL or item.recipeSourceURL,
                                identityVerifiedReference=true,trainerStockVerified=false,
                                teachingVerifiedLive=false,navigationQualified=false,readOnly=true}
                        end
                    end
                    if #actors>0 then
                        item.learningActorReferences=actors
                        matrix.learningAccess="PARTIAL_EXACT_ACTOR_IDENTITY"
                    elseif type(producer.primarySourceTrainerNames)=="table" and
                           #producer.primarySourceTrainerNames>0 then
                        matrix.learningAccess="TRAINER_NAMES_ONLY"
                    end
                end
            end
            if item.learningEvidence and item.learningEvidence.teachingItemCount>0 then
                matrix.learningAccess="EXACT_DB70450_TEACHING_ITEM_ADVISORY"
            end
            item.evidenceMatrix=matrix
            item.routeVerified=false
            local span=hi-lo
            if item.proofTier=="SOURCE_SKILL_AND_REAGENTS" then
                out.sourceSkillPositions=out.sourceSkillPositions+span
            elseif item.proofTier=="REAGENTS_ONLY_WINDOW_UNVERIFIED" then
                out.materialOnlyPositions=out.materialOnlyPositions+span
            else out.unqualifiedPositions=out.unqualifiedPositions+span end
            -- Even a perfect reagent+minimum window is NOT a qualified
            -- progression path without observed recipe access and difficulty.
            if not out.firstUnresolved then
                local required=item.proofTier~="SOURCE_SKILL_AND_REAGENTS" and
                    "EXACT_RECIPE_ACCESS_DIFFICULTY_AND_SKILLUP_PROOF" or
                    "OBSERVED_RECIPE_LEARNING_DIFFICULTY_CRAFT_AND_SKILLUP"
                out.firstUnresolved={atSkill=lo,
                    reason=item.proofTier~="SOURCE_SKILL_AND_REAGENTS" and
                        item.referenceState or "LIVE_PROGRESSION_EVIDENCE_MISSING",
                    required=required}
            end
            out.segments[#out.segments+1]=item
        end
    end
    -- 299 -> 300 included in half-open skill intervals; no missing tail can
    -- inadvertently be advertised as qualified.
    if #out.segments==0 or out.segments[#out.segments].toSkill~=300 then
        out.firstUnresolved=out.firstUnresolved or {atSkill=fromSkill,
            reason="COVERAGE_TERMINATES_EARLY"}
    end
    out.coveredPositions=out.sourceSkillPositions+out.materialOnlyPositions+out.unqualifiedPositions
    return out
end

-- P0-221: derive the FIRST unblocker of the current source window, not an
-- executable queue. A research window is never proof of learned status,
-- inventory, difficulty, an NPC location, a craft or a skill-up receipt.
-- Do not jump across an unresolved earlier interval to a later "nice" recipe.
-- Current-panel learned evidence is supplied only by UniversalCurrentStep's
-- guarded liveLearned() path. Test/fixture overrides remain scenarios.
function S:CurrentWindowChecklist(continuity,observed)
    if type(continuity)~="table" or continuity.contract~="JLP-SOURCE-WINDOW-CONTINUITY-220" then
        return nil,"INVALID_WINDOW_CONTRACT" end
    observed=type(observed)=="table" and observed or {}
    local segment=continuity.segments and continuity.segments[1]
    if not segment or segment.fromSkill~=continuity.fromSkill then
        return nil,"CURRENT_WINDOW_MISSING" end
    local result={contract="JLP-SOURCE-WINDOW-UNBLOCKER-221",professionKey=continuity.professionKey,
        atSkill=continuity.fromSkill,windowEnd=segment.toSkill,recipeID=segment.recipeID,
        recipe=segment.recipe,proofTier=segment.proofTier,readOnly=true,
        nativeDispatchAllowed=false,executionEligible=false,navigationQualified=false,
        skillGainGuaranteed=false,craftReceiptObserved=false,skillUpReceiptObserved=false,
        expectedCraftsQualified=false,perCraftMaterials={},
        action="VERIFY_SOURCE_GAP",reason=segment.referenceState,
        nextObservationRequired="EXACT_SKILL_WINDOW_AND_RECIPE_SOURCE"}
    if segment.proofTier~="SOURCE_SKILL_AND_REAGENTS" or not segment.recipeID or
        not segment.recipeSourceURL or #(segment.reagentsPerCraft or {})==0 then
        return result
    end
    -- Observations and read-only references are NOT authority to navigate or craft.
    -- Advisory fixtures/overrides can never masquerade as CURRENT_PANEL_STABLE.
    local learned
    if type(observed.learnedRecipes)=="table" then
        learned=observed.learnedRecipes[segment.recipeID]
    end
    if observed.learnedSource~="CURRENT_PANEL" or type(learned)~="boolean" then
        result.action="VERIFY_RECIPE_LEARNED"
        result.reason="CURRENT_PANEL_LEARNED_NOT_OBSERVED"
        result.nextObservationRequired="FRESH_PROFESSION_PANEL_RECIPE_STATE"
        return result
    end
    if learned==false then
        result.action="LEARN_RECIPE"
        result.reason="CURRENT_PANEL_NOT_LEARNED"
        result.nextObservationRequired="LEARNED_RECIPE_AND_EXACT_LEARNING_SOURCE"
        return result
    end
    local inv=JLP:GetModule("Inventory")
    local ready=true
    local inventoryUnknown=false
    for _,mat in ipairs(segment.reagentsPerCraft) do
        local owned
        if inv and type(inv.GetOwned)=="function" then
            local ok,value=pcall(inv.GetOwned,inv,mat.itemID)
            if ok then owned=value end
        end
        local known=type(owned)=="table" and owned.bagKnown==true and
            isinteger(owned.bags) and owned.bags>=0
        local available=known and owned.bags or nil
        local missing=available and math.max(0,mat.quantity-available) or nil
        result.perCraftMaterials[#result.perCraftMaterials+1]={itemID=mat.itemID,
            required=mat.quantity,bagKnown=known,bags=available,missing=missing,
            sourceURL=mat.sourceURL}
        if not known then inventoryUnknown=true;ready=false
        elseif missing>0 then ready=false end
    end
    if inventoryUnknown then
        result.action="VERIFY_INVENTORY";result.reason="CURRENT_BAGS_UNKNOWN"
        result.nextObservationRequired="FRESH_BAG_COUNTS"
        return result
    end
    if not ready then
        result.action="ACQUIRE_MATERIALS";result.reason="OBSERVED_REAGENT_SHORTAGE"
        result.nextObservationRequired="BAG_BEFORE_AFTER_ACQUISITION"
        return result
    end
    -- Only stable, actual observed non-grey recipe color permits a manual
    -- one-craft *suggestion*; no historical yellow/grey cutoff can substitute.
    local facts=JLP:GetModule("ProfessionPlanningFacts")
    local observation
    if facts and type(facts.Observe)=="function" then
        local ok,value=pcall(facts.Observe,facts,continuity.professionKey,segment.recipeID)
        if ok and type(value)=="table" then observation=value end
    end
    local tier=observation and observation.observed==true and observation.skillup
        and observation.skillup.tier or nil
    if tier=="GRAY" or (observation and observation.observed==true and
        observation.skillup and observation.skillup.canSkillUp==false) then
        result.action="VERIFY_ALTERNATIVE_RECIPE"
        result.reason="CURRENT_RECIPE_CANNOT_SKILLUP"
        result.nextObservationRequired="ALTERNATIVE_LIVE_SKILLUP_CANDIDATE"
    elseif tier~="ORANGE" and tier~="YELLOW" and tier~="GREEN" then
        result.action="VERIFY_RECIPE_DIFFICULTY"
        result.reason="CURRENT_DIFFICULTY_NOT_OBSERVED"
        result.nextObservationRequired="STABLE_CURRENT_RECIPE_COLOR"
    else
        result.action="MANUAL_ONE_CRAFT_VERIFY_RECEIPTS"
        result.reason="SOURCE_AND_CURRENT_READ_ONLY_CHECKS_READY"
        result.nextObservationRequired="SEPARATE_CRAFT_EVENT_AND_SKILL_BEFORE_AFTER"
        result.observedDifficulty=tier
    end
    return result
end

function S:GetAtSkill(key,skill,mode)
    local plan,err=self:Build(key,mode)
    if not plan then return nil,err end
    skill=tonumber(skill)
    if not skill or skill<1 or skill>299 then return nil,"SKILL_OUTSIDE_1_299" end
    for _,range in ipairs(plan.coverage) do
        if skill>=range.fromSkill and skill<range.toSkill then
            local issue
            if range.state=="SKILL_ELIGIBILITY_GAP" then
                for _,row in ipairs(plan.steps) do
                    if row.skillMin and row.skillTarget and skill>=row.skillMin and skill<row.skillTarget and
                        row.skillEligibility and (row.skillEligibility.minimumSkill or
                            row.skillEligibility.status=="INVALID_MINIMUM_SKILL_EVIDENCE") then
                        issue=row.skillEligibility
                        break
                    end
                end
            end
            return {professionKey=plan.professionKey,mode=plan.mode,skill=skill,
                state=range.state,fromSkill=range.fromSkill,toSkill=range.toSkill,
                step=range.stepIndex and clone(plan.steps[range.stepIndex]) or nil,
                skillEligibility=clone(issue),
                nativeDispatchAllowed=false,executionEligible=false}
        end
    end
    return nil,"NO_BAND"
end
function S:GetSummary(key,mode,skill)
    local plan,err=self:Build(key,mode)
    if not plan then return "Forever skill-band plan: "..tostring(err) end
    local lines={string.format("%s %s: %d Forever reagent-backed steps / %d total craft steps",
        plan.professionKey,plan.mode,plan.sourceMatched,#plan.steps),
        string.format("Forever recipe-material coverage: %d/299 research skill positions; unknown skill gates %d; source gate conflicts %d; research-only %d",
        plan.foreverReferencedSkillSpan,plan.sourceOnlyMaterials,plan.sourceSkillConflicts,plan.researchOnly),
        string.format("Direct reagent total (%d unique items) covers referenced steps ONLY; trainer/skill bands and craft counts remain research estimates",
        #plan.materials)}
    if skill then
        local point=self:GetAtSkill(key,skill,mode)
        if point then lines[#lines+1]=string.format("Skill %d: %s%s",skill,point.state,point.step and " · "..tostring(point.step.recipe) or "") end
    end
    for _,gap in ipairs(plan.gaps) do lines[#lines+1]=string.format("Unresolved %d-%d: %s",gap.fromSkill,gap.toSkill,gap.state) end
    lines[#lines+1]="Reference-first, advisory only; no native craft or Live-QA requirement"
    return table.concat(lines,"\n")
end
JLP:RegisterModule("ForeverSkillBandPlanner",S)
