local _, JLP = ...
-- P0.2A: Skill minimum is a different evidence field from raw 70450
-- difficulty cutoffs and historical craft-count estimates. Presentation only.
local function recipeSkillEvidenceLabel(plan)
    if plan and plan.step and plan.step.p1OneCraft then
        return " | P1 observed one-craft fallback: "..tostring(plan.step.recipe)..
            " | Learned and non-gray difficulty observed on build70450 | TOTAL crafts UNKNOWN"..
            " | Recheck actual skill after EACH manual craft | NO native dispatch"
    end
    local evidence=plan and plan.step and plan.step.skillEligibility
    -- P0.2I: show the actual source conflict in BOTH guide layouts when the
    -- Planner returns VERIFY for historical 137-143. Never show craft options
    -- or mark learned/native authorization from this advisory reference.
    local checkStep=plan and plan.step
    local raw=checkStep and (checkStep.rawStep or checkStep) or nil
    if checkStep and checkStep.kind=="verify" and raw and
       raw.sourceQualificationContract=="tailoring-silk-headband-field-evidence-p02i-v1" then
        local min=evidence and evidence.minimumSkill or raw.requiredSkill or "?"
        local candidate=raw.gapResolutionCandidate
        local candidateNote=""
        if type(candidate)=="table" and candidate.advisoryOnly==true and
           candidate.routeQualified==false and candidate.recipeID==3852 then
            candidateNote=" | VERIFY CANDIDATE: Gloves of Meditation (3852)"..
                " external minimum 130 (not live observed), DB70450 raw difficulty 125/155"..
                " | Per craft: 4 Wool Bolts (2997), 3 Fine Thread (2321), 1 Elixir of Wisdom (3383)"..
                " | Output Item 4318 (not live yield)"..
                " | Candidate trainer/learned/skill-up UNVERIFIED; 137-143 craft count UNKNOWN"..
                " | Silk Headband's 13 crafts MUST NOT transfer to candidate"
        end
        return " | Silk Headband RECIPE GATE: source minimum "..tostring(min)..
            " (Wowhead Forever; external) vs raw DB70450 difficulty 135/145"..
            " | ROUTE GAP 137-143: verify access/choose a qualified alternative"..
            " | Crafts 13 ESTIMATE (70009; rate 137-143 UNVERIFIED)"..
            " | Yield CONFLICT: 1 vs 2 (external, not live verified)"..
            candidateNote..
            " | Recipe learned/access UNVERIFIED | NO native execution"
    end
    -- P0.2L: the 143-145 historical Gloves step must never display as
    -- craft while access/rate lack evidence. Use Planner's count status,
    -- not a raw flag that mocks may contradict.
    if checkStep and checkStep.kind=="verify" and raw and
       raw.sourceQualificationContract=="tailoring-143-145-gloves-evidence-p02l-v1" then
        local countStatus=checkStep.craftEstimateEvidenceStatus
        if countStatus~="UNVERIFIED" and countStatus~="INVALID" and
           countStatus~="UNKNOWN" then countStatus="UNKNOWN" end
        return " | ROUTE GAP 143-145: Gloves of Meditation (3852) VERIFY"..
            " | External minimum 130 (Wowhead Forever; not live verified)"..
            " | DB70450 raw difficulty 125/155 (not minimum/skill-up-rate)"..
            " | Per craft: 4 Wool Bolts (2997), 3 Fine Thread (2321), 1 Elixir of Wisdom (3383)"..
            " | Output item 4318 (live yield UNKNOWN)"..
            " | Crafts 6 ESTIMATE (70009; "..countStatus.."; NOT qualified budget)"..
            " | Trainer/learned/skill-ups at 143-145 NOT OBSERVED"..
            " | NO native execution"
    end
    -- P0.2M: source conflict is in the learning minimum itself. Always
    -- render both source builds and the Planner's separate count status.
    if checkStep and checkStep.kind=="verify" and raw and
       raw.sourceQualificationContract=="tailoring-145-153-formal-white-shirt-evidence-p02m-v1" then
        local countStatus=checkStep.craftEstimateEvidenceStatus
        if countStatus~="UNVERIFIED" and countStatus~="INVALID" and
            countStatus~="UNKNOWN" then countStatus="UNKNOWN" end
        return " | ROUTE GAP 145-153: Formal White Shirt (3871) VERIFY"..
            " | Minimum CONFLICT: Wowhead Forever 170 vs older ForeverDB70425 145"..
            " | DB70450 raw difficulty 145/155 (NOT minimum)"..
            " | Per craft: 3 Silk Bolts (4305), 2 Bleach (2324), 1 Fine Thread (2321)"..
            " | Nested: 4 Silk Cloth (4306) per Bolt; no double-counting"..
            " | Output item 4334 (reference yield CONFLICT 2 vs 1, live UNKNOWN)"..
            " | Crafts 15 ESTIMATE (70009; "..countStatus.."; NOT qualified budget)"..
            " | Trainer/learned/skill-ups NOT OBSERVED | NO native execution"
    end
    -- P0.2N: source minimum and raw difficulty alone cannot promote
    -- historical Small Silk Pack to a craftable, budgeted route.
    if checkStep and checkStep.kind=="verify" and raw and
       raw.sourceQualificationContract=="tailoring-153-160-small-silk-pack-evidence-p02n-v1" then
        local countStatus=checkStep.craftEstimateEvidenceStatus
        if countStatus~="UNVERIFIED" and countStatus~="INVALID" and
            countStatus~="UNKNOWN" then countStatus="UNKNOWN" end
        return " | ROUTE GAP 153-160: Small Silk Pack (3813) VERIFY"..
            " | External minimum 150 (Wowhead Forever; not live observed)"..
            " | DB70450 raw difficulty 145/175 (NOT minimum or skill-up rate)"..
            " | Classic 150/170/185/200 is cross-build ONLY"..
            " | Per craft: 3 Silk Bolts (4305), 2 Heavy Leather (4234), 3 Fine Thread (2321)"..
            " | Nested: 4 Silk Cloth (4306) per Bolt; no double-counting"..
            " | Output item 4245 (reference yield CONFLICT 2 vs 1; live UNKNOWN)"..
            " | Crafts 12 ESTIMATE (70009; "..countStatus.."; NOT qualified budget)"..
            " | Trainer/learned/skill-ups NOT OBSERVED | NO native execution"
    end
    if evidence and evidence.progressionQualified and evidence.minimumSkill then
        local suffix=" | Source minimum "..tostring(evidence.minimumSkill)
        -- Explicit advisory uncertainty for the single P0.2B field-qualified
        -- Tailoring segment. Do not imply that the 70009 estimate is proven.
        local step=plan and plan.step
        -- P0.2C: consume the Planner's authoritative evidence status, NOT
        -- the raw craftCountQualified flag (true with historical authority
        -- is still UNVERIFIED). Missing Planner proof is never positive.
        local countStatus=step and step.craftEstimateEvidenceStatus
        if step and (step.craftCountQualified~=true or countStatus~="QUALIFIED") then
            if countStatus~="UNVERIFIED" and countStatus~="INVALID" and
                countStatus~="UNKNOWN" then countStatus="UNKNOWN" end
            suffix=suffix.." | Craft count "..countStatus.." (advisory estimate)"
        end
        if step and step.sourceQualificationContract=="tailoring-bolt-linen-field-evidence-p02b-v1" then
            if step.craftCountQualified==false then
                suffix=suffix.." | Crafts ESTIMATE (70009; rate 25-31 unverified)"
            end
            if step.outputQuantityReference then
                suffix=suffix.." | Yield "..tostring(step.outputQuantityReference).." REFERENCE (not live verified)"
            end
            if step.outputQuantityConflictingReference then
                suffix=suffix.." | Yield CONFLICT: "..tostring(step.outputQuantityConflictingReference)..
                    " vs "..tostring(step.outputQuantityReference).." (external; unverified)"
            end
            suffix=suffix.." | Recipe source trainer/auto UNVERIFIED"
            suffix=suffix.." | Recipe learned/access UNVERIFIED"
        elseif step and step.sourceQualificationContract==
            "tailoring-simple-linen-pants-field-evidence-p02c-v1" then
            suffix=suffix.." | Crafts ESTIMATE (70009; rate 40-50 unverified)"
            suffix=suffix.." | Yield "..tostring(step.outputQuantityReference or "?")..
                " REFERENCE (not live verified)"
            if step.outputQuantityConflictingReference then
                suffix=suffix.." | Yield CONFLICT: "..
                    tostring(step.outputQuantityConflictingReference).." vs "..
                    tostring(step.outputQuantityReference or "?").." (external; unverified)"
            end
            suffix=suffix.." | Difficulty-source CONFLICT (Forever external references)"
            suffix=suffix.." | Recipe source trainer/auto UNVERIFIED"
            suffix=suffix.." | Recipe learned/access UNVERIFIED"
        elseif step and step.sourceQualificationContract==
            "tailoring-linen-belt-field-evidence-p02d-v1" then
            suffix=suffix.." | Crafts ESTIMATE (70009; rate 50-77 unverified)"
            suffix=suffix.." | Yield "..tostring(step.outputQuantityReference or "?")..
                " REFERENCE (not live verified)"
            if step.outputQuantityConflictingReference then
                suffix=suffix.." | Yield CONFLICT: "..
                    tostring(step.outputQuantityConflictingReference).." vs "..
                    tostring(step.outputQuantityReference or "?").." (external; unverified)"
            end
            suffix=suffix.." | Difficulty-source CONFLICT (green cutoff: 67/68 external)"
            suffix=suffix.." | Recipe trainer reference UNVERIFIED (client access)"
            suffix=suffix.." | Recipe learned/access UNVERIFIED"
        elseif step and step.sourceQualificationContract==
            "tailoring-simple-kilt-field-evidence-p02e-v1" then
            suffix=suffix.." | Crafts ESTIMATE (70009; rate 77-102 unverified)"
            suffix=suffix.." | Yield "..tostring(step.outputQuantityReference or "?")..
                " REFERENCE (not live verified)"
            if step.outputQuantityConflictingReference then
                suffix=suffix.." | Yield CONFLICT: "..
                    tostring(step.outputQuantityConflictingReference).." vs "..
                    tostring(step.outputQuantityReference or "?").." (external; unverified)"
            end
            suffix=suffix.." | Classic difficulty 75/100/117/135 is cross-build, not Forever evidence"
            suffix=suffix.." | Recipe trainer/learning UNVERIFIED"
            suffix=suffix.." | Recipe learned/access UNVERIFIED"
        elseif step and step.sourceQualificationContract==
            "tailoring-woolen-cape-field-evidence-p02f-v1" then
            suffix=suffix.." | Crafts ESTIMATE (70009; rate 102-107 unverified)"
            suffix=suffix.." | Yield "..tostring(step.outputQuantityReference or "?")..
                " REFERENCE (not live verified)"
            if step.outputQuantityConflictingReference then
                suffix=suffix.." | Yield CONFLICT: "..
                    tostring(step.outputQuantityConflictingReference).." vs "..
                    tostring(step.outputQuantityReference or "?").." (external; unverified)"
            end
            suffix=suffix.." | Raw difficulty 80/115 (DB70450; not learning minimum)"
            suffix=suffix.." | Trainer reference external; actual recipe access UNVERIFIED"
            suffix=suffix.." | Recipe learned/access UNVERIFIED"
        elseif step and step.sourceQualificationContract==
            "tailoring-green-woolen-vest-field-evidence-p02g-v1" then
            suffix=suffix.." | Crafts ESTIMATE (70009; rate 107-110 unverified)"
            suffix=suffix.." | Yield "..tostring(step.outputQuantityReference or "?")..
                " REFERENCE (not live verified)"
            if step.outputQuantityConflictingReference then
                suffix=suffix.." | Yield CONFLICT: "..
                    tostring(step.outputQuantityConflictingReference).." vs "..
                    tostring(step.outputQuantityReference or "?").." (external; unverified)"
            end
            suffix=suffix.." | Raw difficulty 85/120 (DB70450; not learning minimum)"
            suffix=suffix.." | Trainer reference external; actual recipe access UNVERIFIED"
            suffix=suffix.." | Recipe learned/access UNVERIFIED"
        elseif step and step.sourceQualificationContract==
            "tailoring-silk-headband-field-evidence-p02i-v1" then
            suffix=suffix.." | Crafts 13 ESTIMATE (70009; rate 137-143 UNVERIFIED)"..
                " | Yield CONFLICT: 1 vs 2 (external, not live verified)"..
                " | Raw DB70450 difficulty 135/145 vs external minimum 160: CONFLICT"..
                " | Recipe learned/access UNVERIFIED"
        elseif step and step.sourceQualificationContract==
            "tailoring-double-stitched-woolen-shoulders-field-evidence-p02h-v1" then
            suffix=suffix.." | Crafts ESTIMATE (70009; rate 110-137 unverified)"
            suffix=suffix.." | Yield "..tostring(step.outputQuantityReference or "?")..
                " REFERENCE (not live verified)"
            if step.outputQuantityConflictingReference then
                suffix=suffix.." | Yield CONFLICT: "..
                    tostring(step.outputQuantityConflictingReference).." vs "..
                    tostring(step.outputQuantityReference or "?").." (external; unverified)"
            end
            suffix=suffix.." | Raw difficulty 110/145 (DB70450; not learning minimum)"
            suffix=suffix.." | Classic difficulty is cross-build, not Forever evidence"
            suffix=suffix.." | Trainer reference external; actual recipe access UNVERIFIED"
            suffix=suffix.." | Recipe learned/access UNVERIFIED"
        end
        return suffix
    end
    return " | Recipe minimum UNVERIFIED"
end

local Page={name="Guide", mode="dual",referenceSkillOverride={}}
-- Source-qualified research step navigation is transient UI state only. It
-- never changes character skill, learned recipes or crafting authority.
function Page:SelectNextQualifiedBand(key,currentSkill,mode,preview)
    if key~="BLACKSMITHING" and key~="LEATHERWORKING" then return false,"PROFESSION_UNAVAILABLE" end
    local planner=JLP:GetModule("ForeverSkillBandPlanner")
    if not planner or type(planner.Build)~="function" or type(planner.GetAtSkill)~="function" then
        return false,"REFERENCE_UNAVAILABLE"
    end
    local value=tonumber(currentSkill)
    if not value or value~=value or value<1 or value>=300 then return false,"SKILL_INVALID" end
    local ok,plan=pcall(planner.Build,planner,key,mode)
    if not ok or type(plan)~="table" or type(plan.steps)~="table" then
        return false,"REFERENCE_UNAVAILABLE"
    end
    local nextSkill=nil
    for _,step in ipairs(plan.steps) do
        if step.materialTotalsVerified==true and step.nativeDispatchAllowed==false and
            type(step.skillMin)=="number" and step.skillMin>value and step.skillMin>=1 and
            step.skillMin<300 and (not nextSkill or step.skillMin<nextSkill) then
            nextSkill=step.skillMin
        end
    end
    if not nextSkill then return false,"NO_NEXT_QUALIFIED_BAND" end
    local okPoint,point=pcall(planner.GetAtSkill,planner,key,nextSkill,mode)
    if not okPoint or not point or not point.step or
        point.step.materialTotalsVerified~=true or point.step.nativeDispatchAllowed~=false or
        type(point.step.sourceURL)~="string" or point.step.sourceURL=="" then
        return false,"SOURCE_BAND_UNAVAILABLE"
    end
    if not preview then self.referenceSkillOverride[key]=nextSkill end
    return true,nextSkill,point.step.recipeID
end
-- Backward source navigation uses exactly the same real reference planner
-- and source gates as Next. This permits revisiting an earlier verified
-- recipe after Bank/AH without making any native crafting claim.
function Page:SelectPreviousQualifiedBand(key,currentSkill,mode,preview)
    if key~="BLACKSMITHING" and key~="LEATHERWORKING" then return false,"PROFESSION_UNAVAILABLE" end
    local planner=JLP:GetModule("ForeverSkillBandPlanner")
    if not planner or type(planner.Build)~="function" or type(planner.GetAtSkill)~="function" then
        return false,"REFERENCE_UNAVAILABLE"
    end
    local value=tonumber(currentSkill)
    if not value or value~=value or value<1 or value>=300 then return false,"SKILL_INVALID" end
    local ok,plan=pcall(planner.Build,planner,key,mode)
    if not ok or type(plan)~="table" or type(plan.steps)~="table" then return false,"REFERENCE_UNAVAILABLE" end
    -- A skill inside a sourced band must rewind from that band's START,
    -- not from the arbitrary current skill (26 -> 25 would stay on 3320).
    -- A gap has no active step: only then rewind from the requested skill.
    local okCurrent,current=pcall(planner.GetAtSkill,planner,key,value,mode)
    if not okCurrent then return false,"REFERENCE_UNAVAILABLE" end
    local anchor=value
    if current and type(current.step)=="table" and
        type(current.step.skillMin)=="number" then
        anchor=current.step.skillMin
    end
    local previous
    for _,step in ipairs(plan.steps) do
        if step.materialTotalsVerified==true and step.nativeDispatchAllowed==false and
            type(step.sourceURL)=="string" and step.sourceURL~="" and
            type(step.skillMin)=="number" and step.skillMin<anchor and step.skillMin>=1 and
            (not previous or step.skillMin>previous) then previous=step.skillMin end
    end
    if not previous then return false,"NO_PREVIOUS_QUALIFIED_BAND" end
    local okPoint,point=pcall(planner.GetAtSkill,planner,key,previous,mode)
    if not okPoint or not point or not point.step or
        point.step.materialTotalsVerified~=true or point.step.nativeDispatchAllowed~=false or
        type(point.step.sourceURL)~="string" or point.step.sourceURL=="" then
        return false,"SOURCE_BAND_UNAVAILABLE" end
    if not preview then self.referenceSkillOverride[key]=previous end
    return true,previous,point.step.recipeID
end
-- First qualified recipe is a research-only manual navigation shortcut.
-- Traverses the existing planner, never creates a recipe or craft authority.
function Page:SelectFirstQualifiedBand(key,mode,preview)
    if key~="BLACKSMITHING" and key~="LEATHERWORKING" then
        return false,"PROFESSION_UNAVAILABLE" end
    local planner=JLP:GetModule("ForeverSkillBandPlanner")
    if not planner or type(planner.Build)~="function" or
        type(planner.GetAtSkill)~="function" then return false,"REFERENCE_UNAVAILABLE" end
    local ok,plan=pcall(planner.Build,planner,key,mode)
    if not ok or type(plan)~="table" or type(plan.steps)~="table" then
        return false,"REFERENCE_UNAVAILABLE" end
    local first
    for _,step in ipairs(plan.steps) do
        if step.materialTotalsVerified==true and step.nativeDispatchAllowed==false and
            type(step.skillMin)=="number" and step.skillMin>=1 and step.skillMin<300 and
            type(step.sourceURL)=="string" and step.sourceURL~="" and
            (not first or step.skillMin<first) then first=step.skillMin end
    end
    if not first then return false,"SOURCE_UNAVAILABLE" end
    local valid,point=pcall(planner.GetAtSkill,planner,key,first,mode)
    if not valid or not point or not point.step or
        point.step.materialTotalsVerified~=true or point.step.nativeDispatchAllowed~=false then
        return false,"SOURCE_UNAVAILABLE" end
    if not preview then self.referenceSkillOverride[key]=first end
    return true,first,point.step.recipeID
end
-- Direct research-only navigation to the final *qualified* recipe band.
-- It cannot fill data gaps, persist skill, or enable native crafting.
function Page:SelectLastQualifiedBand(key,mode,preview)
    if key~="BLACKSMITHING" and key~="LEATHERWORKING" then
        return false,"PROFESSION_UNAVAILABLE" end
    local planner=JLP:GetModule("ForeverSkillBandPlanner")
    if not planner or type(planner.Build)~="function" or
        type(planner.GetAtSkill)~="function" then return false,"REFERENCE_UNAVAILABLE" end
    local ok,plan=pcall(planner.Build,planner,key,mode)
    if not ok or type(plan)~="table" or type(plan.steps)~="table" then
        return false,"REFERENCE_UNAVAILABLE" end
    local last
    for _,step in ipairs(plan.steps) do
        if step.materialTotalsVerified==true and step.nativeDispatchAllowed==false and
            type(step.skillMin)=="number" and step.skillMin>=1 and step.skillMin<300 and
            type(step.sourceURL)=="string" and step.sourceURL~="" and
            (not last or step.skillMin>last) then last=step.skillMin end
    end
    if not last then return false,"SOURCE_UNAVAILABLE" end
    local valid,point=pcall(planner.GetAtSkill,planner,key,last,mode)
    if not valid or not point or not point.step or
        point.step.materialTotalsVerified~=true or point.step.nativeDispatchAllowed~=false or
        type(point.step.sourceURL)~="string" or point.step.sourceURL=="" then
        return false,"SOURCE_UNAVAILABLE" end
    if not preview then self.referenceSkillOverride[key]=last end
    return true,last,point.step.recipeID
end
function Page:ResetQualifiedBand(key)
    if key~="BLACKSMITHING" and key~="LEATHERWORKING" then return false end
    self.referenceSkillOverride[key]=nil
    self.referenceBandFeedback=nil
    return true
end

-- Transient, verified character scope is part of the material source receipt.
-- A new character with the same recipe and counts is still a different owner.
function Page:MaterialOwnerSignature()
    local inventory=type(JLP.GetModule)=="function" and JLP:GetModule("Inventory") or nil
    if type(inventory)~="table" or type(inventory.GetCharacterKey)~="function" then
        return "OWNER_UNKNOWN"
    end
    local ok,key=pcall(inventory.GetCharacterKey,inventory)
    if not ok or type(key)~="string" or key=="" then return "OWNER_UNKNOWN" end
    return key
end
-- Explicit user-click handler for the Mining advisory material branch.
-- It does not trigger a scan, craft, purchase, withdrawal or native gathering.
function Page:InspectSmeltingMaterial(target,holder)
    if target~="Bank" and target~="Auction House" then return false,"TARGET_UNAVAILABLE" end
    local frame=self.frame
    if self.mode~="MINING" and self.mode~="mining" then return false,"PROFESSION_CHANGED" end
    if not frame or not frame.single or frame.single.materials~=holder then
        return false,"ORIGIN_NOT_CURRENT"
    end
    local ref=holder.__smeltingReference
    if not ref or ref.readOnly~=true or ref.nativeDispatchAllowed~=false or
        not ref.itemID then return false,"SOURCE_UNAVAILABLE" end
    local owner=self:MaterialOwnerSignature()
    if owner=="OWNER_UNKNOWN" or owner~=holder.__smeltingOwner then
        return false,"OWNER_UNKNOWN"
    end
    local main=JLP.MainWindow
    if not main or not main.BeginMaterialReference then return false,"NAVIGATION_UNAVAILABLE" end
    local ok,reason=main:BeginMaterialReference(target,"Guide",ref,holder)
    if not ok and holder.smeltingStatus and holder.smeltingStatus.SetText then
        holder.smeltingStatus:SetText("Material inspection unavailable: "..tostring(reason))
    end
    return ok,reason
end
local function workspace() return JLP:GetModule("ProfessionWorkspace") end
local function maturityStatus(key)
    local presenter=JLP:GetModule("ProfessionMaturityPresentation")
    return presenter and presenter:Build(key) or {label="RESEARCH · UNVERIFIED",detail="Capability unknown.",tone="warn"}
end
local function setMaturityText(label,key)
    local state=maturityStatus(key)
    if label and label.SetText then label:SetText(state.label.." · "..state.detail) end
    if label and label.SetTextColor then label:SetTextColor(JLP.UITheme:Color(state.tone)) end
    return state
end

local function gatheringEvidenceLabel()
    local service=JLP:GetModule("GatheringSourceEvidenceSummary")
    return service and service:Label() or "Smart gathering: source coverage unknown"
end


local function getPair()
    local ws=workspace()
    return ws and ws:GetPrimaryLearned() or {}
end

local function isReadOnlyPlan(plan)
    local policy=JLP:GetModule("PlanAuthorityPolicy")
    if not policy or not policy.IsReadOnlyConsumable then return false,nil end
    return policy:IsReadOnlyConsumable(plan)
end

local function isGatheringProfession(key)
    key=tostring(key or ""):upper()
    return key=="HERBALISM" or key=="MINING" or key=="SKINNING" or key=="FISHING"
end
local function suppressReadOnlyPresentation(key,authorityClass)
    return tostring(key or ""):upper()=="ALCHEMY" and authorityClass and authorityClass.category=="PRODUCTION_CANDIDATE_READONLY"
end

local function allowResearchConsumer(key)
    local reg=JLP:GetModule("ProfessionRegistry")
    local def=reg and reg:Get(key) or nil
    -- A current production-candidate dataset must be the user-facing current
    -- view. Historical research remains evidence/audit only for that key.
    return not (def and def.maturity and def.maturity.candidate==true)
end


local function statusTone(plan,readiness,machine)
    if machine and machine.tone then return machine.tone end
    if plan and plan.actionKind=="train" then return "gold" end
    local s=readiness and readiness.status or "blocked"
    if s=="ready" or s=="complete" then return "good" end
    if s=="prepare" or s=="bank" or s=="verify" or s=="materials" then return "warn" end
    return "bad"
end

local function statusLabel(plan,readiness,machine)
    if machine and machine.label then return machine.label end
    if plan and plan.actionKind=="train" then return "TRAINER" end
    if plan and plan.actionKind=="complete" then return "COMPLETE" end
    return string.upper(tostring(readiness and readiness.status or "BLOCKED"))
end

local function bundle(key,plan)
    local sm=JLP:GetModule("ProfessionState")
    local machine,readiness,queue,tracking
    if sm then machine,readiness,queue,tracking=sm:Get(key,plan) end
    local action=queue and queue.actions and queue.actions[tonumber(queue.currentIndex) or 0] or nil
    local am=JLP:GetModule("ActionAssist")
    local assist=am and am:Get(key,plan,queue) or nil
    local fm=JLP:GetModule("ExecutionFlow")
    local flow=fm and fm:Build(key,queue) or nil
    local scopeModule=JLP:GetModule("ProfessionGuideScope")
    local scope=scopeModule and scopeModule.Build and scopeModule:Build(key,plan,{queue=queue,action=action,assist=assist,context=flow and flow.currentContext or nil}) or {}
    local trm=JLP:GetModule("TransactionRecovery"); local etm=JLP:GetModule("RecipeTelemetry")
    return readiness, queue, assist, flow, machine, scope.workspace, scope.nextBest, scope.routeSession, scope.travelSession, scope.travelTransition, scope.navigationGuidance, scope.routeMarker, scope.destinationHandoff, scope.recovery, trm and trm:GetStatus(key) or nil, etm and etm:GetPlanStatus(key,plan) or nil, tracking
end

local function currentAction(queue)
    return queue and queue.actions and queue.actions[queue.currentIndex] or nil
end

local function researchConsumerSnapshot(key)
    local consumer=JLP:GetModule("ResearchPlannerConsumerBridge")
    if not consumer or not consumer.Build or not consumer.IsSupported or not consumer:IsSupported(key) then return nil,nil end
    local model=consumer:Build(key)
    local invalidation=JLP:GetModule("ResearchConsumerInvalidation")
    local state=invalidation and invalidation.TrackModel and invalidation:TrackModel(model,"guide-render") or nil
    if model and model.consumerAuthorityEnabled==true and model.state=="consumer-authority-active" then return model,state end
    return nil,state
end

local function consumerAuthorityRevoked(state)
    return state and state.active==false and state.hadAuthority==true and state.lastTransition=="revoked"
end

local function revokedAuthorityText(state)
    if not state then return "Controlled planner authority revoked." end
    local source=tostring(state.sourceAuthorityState or state.consumerState or "authority unavailable")
    return "Controlled planner authority revoked: "..source
end

local function currentSequenceBoundary(key)
    local stopPolicy=JLP:GetModule("ResearchSequentialStopPolicy")
    if not stopPolicy or not stopPolicy.IsCurrentHandoff then return nil end
    local autoRoute=JLP:GetModule("ResearchAutoRouteOrchestrator")
    local last=autoRoute and autoRoute.GetLast and autoRoute:GetLast(key) or nil
    if last then
        local current=stopPolicy:IsCurrentHandoff(last,key)
        if current then return current end
    end
    local legacy=JLP:GetModule("ResearchBoundedSequentialCraft")
    last=legacy and legacy.GetLast and legacy:GetLast(key) or nil
    return last and stopPolicy:IsCurrentHandoff(last,key) or nil
end

local function currentSequenceRestart(key)
    local production=JLP:GetModule("ResearchAutoRouteOrchestrator")
    local interruption=JLP:GetModule("ResearchAutoRouteInterruption")
    local hasProductionLifecycle=production and ((production.IsFeatureEnabled and production:IsFeatureEnabled(key)) or (production.GetSession and production:GetSession(key)) or (interruption and interruption.GetLast and interruption:GetLast(key)))
    local restart=hasProductionLifecycle and JLP:GetModule("ResearchAutoRouteRestart") or JLP:GetModule("ResearchBoundaryResolutionRestart")
    if not restart or not restart.Evaluate then return nil end
    local model=restart:Evaluate(key,"normal")
    return model and model.restartRequired and model or nil
end

local function sequenceRestartText(model)
    if not model or model.restartReady~=true then return nil end
    local recipe=tostring(model.currentRecipe or "the verified current route")
    if model.contract=="production-auto-route-fresh-click-restart-planner-v1" then
        local lineageNote=model.lineageDepth and (" The new session will be lineage generation "..tostring(model.lineageDepth).." with immediate predecessor "..tostring(model.lineageParentSessionToken or model.priorSessionToken or "unknown").."; older ancestors cannot authorize this restart.") or ""
        if model.routeChanged==true then
            return "Auto Route interruption resolved with route-change proof ("..tostring(model.routeChangeBasis or "unresolved").."). Stale execution authority was purged and the new Planner route, snapshot and execution readiness were revalidated for "..recipe..". Start a fresh Auto Route session with a new explicit click; the previous session cannot resume."..lineageNote
        end
        return "Auto Route interruption resolved. Current Planner route, snapshot and execution readiness revalidated for "..recipe..". Start a fresh Auto Route session with a new explicit click; the previous session cannot resume."..lineageNote
    end
    return "Boundary resolved. New route verified: "..recipe..". Start a new Auto Route session with a new explicit click."
end

local function currentCraftAllHandoff(key)
    local handoff=JLP:GetModule("ResearchNativeCraftAllHandoff")
    if not handoff or not handoff.GetCurrent then return nil end
    local model=handoff:GetCurrent(key,"normal")
    return model and model.active==true and model or nil
end

local function craftAllRestartModuleForKey(key)
    key=tostring(key or ""):upper()
    if key=="TAILORING" then return JLP:GetModule("ProductionTailoringCraftAllRestart") end
    return JLP:GetModule("ResearchNativeCraftAllRestart")
end

local function currentCraftAllRestart(key)
    local restart=craftAllRestartModuleForKey(key)
    if not restart or not restart.Evaluate then return nil end
    local model=restart:Evaluate(key,"normal")
    return model and model.restartRequired and model or nil
end

local function craftAllRestartText(model)
    if not model or model.restartReady~=true then return nil end
    return "Craft All interruption resolved. Same recipe and target revalidated: "..tostring(model.currentRecipe or "current recipe")..". Start a fresh Craft All transaction with a new explicit click."
end

local function currentCraftAllResolution(key)
    local matrix=JLP:GetModule("ResearchNativeCraftAllResolutionMatrix")
    if not matrix or not matrix.Analyze then return nil end
    local model=matrix:Analyze(key,"normal")
    return model and model.disposition~="not-applicable" and model or nil
end

local function craftAllResolutionBadge(model)
    if not model then return nil,nil end
    if model.disposition=="planner-handoff-required" then return "CRAFT ALL REPLAN","gold" end
    if model.disposition=="wait-for-resolution" then return "CRAFT ALL BLOCKED","gold" end
    return nil,nil
end

local function craftAllResolutionText(model)
    if not model then return nil end
    if model.disposition=="planner-handoff-required" or model.disposition=="wait-for-resolution" then
        return tostring(model.detail or model.label or "Craft All restart requires a fresh Planner evaluation.")
    end
    return nil
end

local function craftAllHandoffBadge(model)
    if not model then return nil,nil end
    if model.handoffKind=="TARGET_REACHED" then return "TARGET REACHED","good" end
    if model.handoffKind=="MATERIALS" then return "MATERIALS NEEDED","gold" end
    return "CRAFT ALL STOP","gold"
end

local function hideContextCTA(card)
    if not card or not card.contextCTA then return end
    card.contextCTA.__jlpContextAction=nil
    card.__contextAction=nil
    card.contextCTA:Hide()
end

local function actionDisplay(action,plan)
    if not action then return "No pending action", "" end
    local kind=tostring(action.kind or "")
    local qty=math.max(1,math.floor(tonumber(action.quantity) or 1))
    local name=action.itemName
    if kind=="train-rank" then
        local gate=plan and plan.step and plan.step.trainer
        return "Train "..tostring(gate and gate.rank or "next profession rank"), gate and ("Result: Unlock skill cap "..tostring(gate.nextCap or 300)) or ""
    elseif kind:match("^retrieve") and name then
        return "Retrieve "..tostring(name)..(qty>1 and (" x"..tostring(qty)) or ""), "From: Bank"
    elseif kind:match("^acquire") and name then
        local source=action.source=="vendor" and "Vendor" or action.source=="auction" and "Auction House" or "External source"
        return "Acquire "..tostring(name)..(qty>1 and (" x"..tostring(qty)) or ""), "Source: "..source
    elseif kind:match("^craft") and name then
        return "Craft "..tostring(name)..(qty>1 and (" x"..tostring(qty)) or ""), action.detail or ""
    end
    return tostring(action.text or "Continue the current profession plan."), tostring(action.detail or "")
end

local function stringHeight(region, fallback)
    if region and region.GetStringHeight then
        local ok,value=pcall(region.GetStringHeight,region)
        if ok and tonumber(value) and value>0 then return value end
    end
    return fallback or 18
end

-- One spacing contract for both crafting Guide modes. The heading's visual
-- line is 18 units tall; both the first row and subsequent 22-unit rows have
-- exactly 8 logical units of free space underneath the preceding element.
-- It also governs the gap above/below Readiness CTAs and Step Progression
-- buttons, and is now shared by Gathering Readiness sections as well.
local GUIDE_SECTION_LINE_HEIGHT=18
local GUIDE_SECTION_GAP=8
local GUIDE_READINESS_MIN_HEIGHT=22

local function layoutGuideReadinessRow(row,y)
    local measured=GUIDE_READINESS_MIN_HEIGHT
    if row and row.value then
        measured=math.max(measured,math.ceil(stringHeight(row.value,GUIDE_READINESS_MIN_HEIGHT))+4)
    end
    if row and row.label then
        measured=math.max(measured,math.ceil(stringHeight(row.label,GUIDE_READINESS_MIN_HEIGHT))+4)
    end
    -- Fontstrings may be unmeasurable until their first in-game paint. Keep
    -- a finite bound rather than allowing stale or unusually long strings to
    -- explode the layout; the scrollframe remains responsible for overflow.
    measured=math.min(2000,measured)
    row:SetHeight(measured)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT",0,-y)
    return y+measured+GUIDE_SECTION_GAP
end

local function shown(widget)
    return widget and widget.IsShown and widget:IsShown()==true
end

-- TextBlocks are shared between the Alchemy trainer state and gathering
-- states. The compact trainer renderer changes child anchors, widths and icon
-- dimensions: restore the *component* contract before any gathering re-use.
-- Merely calling SetBlock does not restore those visual properties.
local function restoreGatheringSourceBlock(block)
    if not block then return end
    if block.SetHeight then block:SetHeight(68) end
    if block.icon then
        block.icon:ClearAllPoints()
        block.icon:SetPoint("TOPLEFT",block,"TOPLEFT",0,-2)
        block.icon:SetSize(32,32)
    end
    if block.title and block.icon then
        block.title:ClearAllPoints()
        block.title:SetPoint("TOPLEFT",block.icon,"TOPRIGHT",12,0)
        block.title:SetPoint("TOPRIGHT",block,"TOPRIGHT",-2,0)
        if block.title.SetHeight then block.title:SetHeight(17) end
    end
    if block.body and block.title then
        block.body:ClearAllPoints()
        block.body:SetPoint("TOPLEFT",block.title,"BOTTOMLEFT",0,-6)
        block.body:SetPoint("BOTTOMRIGHT",block,"BOTTOMRIGHT",-2,0)
    end
end

local function layoutGuideTrainerMaterials(materials)
    if not (materials and materials.scroll) then return end
    local y=0
    local function placeLabel(widget)
        if not shown(widget) then return end
        if widget.ClearAllPoints then widget:ClearAllPoints() end
        widget:SetPoint("TOPLEFT",0,-y)
        y=y+GUIDE_SECTION_LINE_HEIGHT+GUIDE_SECTION_GAP
    end
    local function placeRow(widget)
        if not shown(widget) then return end
        if widget.ClearAllPoints then widget:ClearAllPoints() end
        widget:SetPoint("TOPLEFT",0,-y)
        y=y+GUIDE_READINESS_MIN_HEIGHT+GUIDE_SECTION_GAP
    end
    local function placeCompactBlock(widget)
        if not shown(widget) then return end
        if widget.icon then
            if widget.icon.ClearAllPoints then widget.icon:ClearAllPoints() end
            widget.icon:SetPoint("TOPLEFT",0,-2)
            widget.icon:SetSize(24,24)
        end
        if widget.title then
            if widget.title.ClearAllPoints then widget.title:ClearAllPoints() end
            widget.title:SetPoint("TOPLEFT",widget.icon,"TOPRIGHT",10,0)
            widget.title:SetPoint("TOPRIGHT",widget,"TOPRIGHT",-2,0)
            widget.title:SetText("")
            if widget.title.SetHeight then widget.title:SetHeight(1) end
        end
        if widget.body then
            if widget.body.ClearAllPoints then widget.body:ClearAllPoints() end
            widget.body:SetPoint("TOPLEFT",widget.icon,"TOPRIGHT",10,-1)
            widget.body:SetPoint("TOPRIGHT",widget,"TOPRIGHT",-2,-1)
            -- Width belongs to the TextBlock's two anchors; never pin it to
            -- a fixed 255 units, as the widget is reused by Gathering pages.
        end
        if widget.SetHeight then widget:SetHeight(44) end
        if widget.ClearAllPoints then widget:ClearAllPoints() end
        widget:SetPoint("TOPLEFT",0,-y)
        widget:SetPoint("TOPRIGHT",0,-y)
        y=y+44+GUIDE_SECTION_GAP
    end

    placeLabel(materials.trainerLabel)
    for _,row in ipairs(materials.trainerRows or {}) do placeRow(row) end
    if y>0 then y=y+GUIDE_SECTION_GAP end
    placeLabel(materials.processLabel)
    placeCompactBlock(materials.process1)
    placeCompactBlock(materials.process2)
    materials.scroll:SetContentHeight(math.max(1,y+4),true)
end

local function setReadinessRows(rows,readiness,tracking,flow,machine,workspace,nextBest,routeSession,travelSession,travelTransition,navigationGuidance,routeMarker,destinationHandoff,recovery,transactionRecovery,telemetryStatus,key)
    local recipe,tone="-","muted"
    if readiness and readiness.recipe then
        recipe=readiness.recipeKnowledge=="known" and "Learned" or readiness.recipeKnowledge=="not-known" and "Not learned" or "Not verified"
        tone=readiness.recipeKnowledge=="known" and "good" or readiness.recipeKnowledge=="not-known" and "bad" or "warn"
    elseif readiness and readiness.blocker=="trainer" then recipe="Profession rank training required"; tone="warn" end
    if rows[1] then rows[1]:SetRow(readiness and readiness.blocker=="trainer" and "state" or "recipe",readiness and readiness.blocker=="trainer" and "State" or "Recipe",recipe,tone) end
    if rows[2] then
        if readiness and readiness.blocker=="trainer" then rows[2]:SetRow("waiting","Live","Waiting for profession rank update...")
        else rows[2]:SetRow("bag","Bag estimate",(readiness and readiness.immediateBagsKnown == false and "UNKNOWN" or string.format("%d from bags",tonumber(readiness and readiness.immediateBags) or 0))) end
    end
    if rows[3] then
        if readiness and readiness.blocker=="trainer" then rows[3]:SetRow("workspace","Next workspace",flow and (flow.nextStationLabel or "Trainer / Recipe Source") or "Trainer / Recipe Source","cyan")
        else rows[3]:SetRow("bank","Storage estimate",(readiness and readiness.preparedStorageKnown == false and "UNKNOWN" or string.format("%d with bags + bank",tonumber(readiness and readiness.preparedStorage) or 0))) end
    end
    if rows[4] then
        local execution=machine and machine.execution or nil
        if execution and execution.active then
            rows[4]:SetRow("execution","Action progress",tostring(execution.progressText or "In progress"),"cyan")
        else
            local live="No live craft progress"
            if tracking and tracking.actionKind=="craft" then
                if (tonumber(tracking.stepConfirmedCrafts) or 0)>0 then
                    live=string.format("%d confirmed | +%d skill | %d no-skill",tonumber(tracking.stepConfirmedCrafts) or 0,tonumber(tracking.stepConfirmedSkillGains) or 0,tonumber(tracking.stepNoSkillCrafts) or 0)
                else
                    live=string.format("%d crafts observed | +%d skill",tracking.stepCraftsObserved or 0,tracking.stepSkillGains or 0)
                end
            end
            rows[4]:SetRow("live","Live",live)
        end
    end
    if rows[5] then
        if workspace then
            rows[5]:SetRow("workspace","Workspace",tostring(workspace.guidance or workspace.requiredLabel or "Other"),workspace.tone or "cyan")
        else
            rows[5]:SetRow("workspace","Next workspace",flow and (flow.nextStationLabel or "Other") or "Other","cyan")
        end
    end
    if rows[6] then
        if machine then rows[6]:SetRow("state","Route state",tostring(machine.label or machine.state or "BLOCKED"),machine.tone or "text")
        else rows[6]:SetRow("switches","Switches",tostring(flow and flow.switchCount or 0)) end
    end
    if rows[7] then
        local selected=nextBest and nextBest.selected or nil
        if selected and selected.key==key then
            local value="NOW · "..tostring(selected.arrivalText or selected.requiredLabel or selected.actionKind or "Continue")
            rows[7]:SetRow("next","Next best",value,"gold")
        elseif selected then
            rows[7]:SetRow("next","Next best","Global · "..tostring(selected.profession or selected.key or "Other profession"),"cyan")
        else
            rows[7]:SetRow("next","Next best","Route complete","good")
        end
    end
    if rows[8] then
        local session=routeSession and routeSession.session or nil
        if session and (tonumber(routeSession.totalActions) or 0)>0 then
            local containsKey=false
            for _,entry in ipairs(session.actions or {}) do if entry.key==key then containsKey=true break end end
            local progress=string.format("%d / %d actions · %s",tonumber(routeSession.completedActions) or 0,tonumber(routeSession.totalActions) or 0,tostring(session.label or session.station or "Workspace"))
            rows[8]:SetRow("batch","Workspace batch",containsKey and progress or ("Global · "..progress),routeSession.status=="completed" and "good" or "cyan")
        else
            rows[8]:SetRow("batch","Workspace batch","No active batch","muted")
        end
    end
    if rows[9] then
        if travelSession and travelSession.plan and not travelSession.plan.routeComplete then
            local value=tostring(travelSession.guideText or travelSession.displayText or travelSession.chainText or "Route complete")
            rows[9]:SetRow("travel","Travel chain",value,"cyan")
        elseif travelSession and travelSession.status=="completed" then
            rows[9]:SetRow("travel","Travel chain","Route complete","good")
        else
            rows[9]:SetRow("travel","Travel chain","Planning...","muted")
        end
    end
    if rows[10] then
        if travelTransition then
            rows[10]:SetRow("journey","Journey step",tostring(travelTransition.guideText or travelTransition.instruction or travelTransition.stage or "Continue"),travelTransition.tone or "cyan")
        else
            rows[10]:SetRow("journey","Journey step","Planning...","muted")
        end
    end
    if rows[11] then
        if travelTransition and travelTransition.routeComplete then
            rows[11]:SetRow("confidence","Source confidence","Route complete","good")
        elseif travelTransition then
            rows[11]:SetRow("confidence","Source confidence",tostring(travelTransition.confidenceLabel or travelTransition.confidenceLevel or "Unavailable"),travelTransition.confidenceTone or "muted")
        else
            rows[11]:SetRow("confidence","Source confidence","Unavailable","muted")
        end
    end
    if rows[12] then
        if navigationGuidance and navigationGuidance.routeComplete then
            rows[12]:SetRow("navigation","Local guidance","Route complete","good")
        elseif navigationGuidance then
            rows[12]:SetRow("navigation","Local guidance",tostring(navigationGuidance.guideText or navigationGuidance.detail or "Unavailable"),navigationGuidance.tone or "muted")
        else
            rows[12]:SetRow("navigation","Local guidance","Unavailable","muted")
        end
    end
    if rows[13] then
        if routeMarker then
            rows[13]:SetRow("marker","Route marker",tostring(routeMarker.label or routeMarker.state or "Unavailable"),routeMarker.tone or "muted")
        else
            rows[13]:SetRow("marker","Route marker","Unavailable","muted")
        end
    end
    if rows[14] then
        if destinationHandoff then
            rows[14]:SetRow("handoff","Route handoff",tostring(destinationHandoff.guideText or destinationHandoff.label or destinationHandoff.stage or "Continue"),destinationHandoff.tone or "cyan")
        else
            rows[14]:SetRow("handoff","Route handoff","Unavailable","muted")
        end
    end
    if rows[15] then
        if recovery then
            rows[15]:SetRow("recovery","Recovery",tostring(recovery.label or recovery.state or "Live state"),recovery.tone or "muted")
        else
            rows[15]:SetRow("recovery","Recovery","Live state","muted")
        end
    end
    if rows[16] then
        if transactionRecovery then
            rows[16]:SetRow("txrecovery","Transaction recovery",tostring(transactionRecovery.label or transactionRecovery.state or "No interrupted transaction"),transactionRecovery.tone or "muted")
        else
            rows[16]:SetRow("txrecovery","Transaction recovery","No interrupted transaction","muted")
        end
    end
    if rows[17] then
        if telemetryStatus then
            rows[17]:SetRow("efficiency","Craft efficiency",tostring(telemetryStatus.label or "Static estimate"),telemetryStatus.tone or "muted")
        else
            rows[17]:SetRow("efficiency","Craft efficiency","Static estimate","muted")
        end
    end
end

local function setActionButtonEnabled(button, enabled)
    if not button then return end
    button.__jlpEnabled = enabled and true or false
    if button.SetEnabled then button:SetEnabled(button.__jlpEnabled) end
    if button.SetAlpha then button:SetAlpha(button.__jlpEnabled and 1 or 0.45) end
end

local function setActionFeedback(card,key,plan)
    if not card or not card.actionFeedback then return false end
    local crafting=JLP:GetModule("Crafting")
    local feedback=crafting and crafting.GetActionFeedback and crafting:GetActionFeedback(key,plan) or nil
    local visible=feedback and feedback.visible and feedback.text and feedback.text~="" or false
    local eta=JLP:GetModule("CraftPresentation")
    local currentEta=eta and eta.Get and eta:Get(card.__professionKey,plan) or nil
    if currentEta and currentEta.active and currentEta.etaText then
        feedback=feedback or {}
        feedback.text=tostring(feedback.text or "").."  ·  "..currentEta.etaText
        visible=true
    end
    card.actionFeedback.__jlpFeedback=feedback
    card.actionFeedback:SetShown(visible and true or false)
    if visible then
        card.actionFeedback:SetText(feedback.text)
        card.actionFeedback:SetTextColor(JLP.UITheme:Color(feedback.tone or "text"))
    else
        card.actionFeedback:SetText("")
    end
    return visible and true or false
end

-- A read-only presentation tick, never a native repeat scheduler. The strict
-- Craft All/Craft X dispatch owner remains Crafting's guarded ordinal service.
local function installCraftFeedbackClock(card)
    if not card or card.__craftFeedbackClock then return end
    local ticker=CreateFrame("Frame",nil,card)
    ticker.elapsed=0
    ticker:SetScript("OnUpdate",function(self,delta)
        self.elapsed=self.elapsed+(tonumber(delta) or 0)
        if self.elapsed<0.9 then return end
        self.elapsed=0
        if not card.__professionKey or not card.actionFeedback then return end
        local crafting=JLP:GetModule("Crafting")
        local pending=crafting and crafting.pendingCraft
        if type(pending)~="table" or pending.key~=card.__professionKey or
           pending.mode~="all" or pending.strictTargetSafeCraftAll~=true then return end
        local planner=JLP:GetModule("Planner")
        local plan=planner and planner.GetProfessionPlan and
            planner:GetProfessionPlan(card.__professionKey) or nil
        setActionFeedback(card,card.__professionKey,plan)
    end)
    card.__craftFeedbackClock=ticker
end

local function setEnchantActionButton(card,key,plan,readiness,target)
    if not card or not card.enchant then return end
    local crafting=JLP:GetModule("Crafting")
    local actionState=crafting and crafting.GetEnchantActionState and crafting:GetEnchantActionState(key,plan) or nil
    local status=actionState and actionState.status or "idle"
    local pending=status=="dispatching" or status=="pending" or status=="crafting" or status=="confirmation-required" or status=="recovery_unresolved"
    if card.enchant.SetText then
        card.enchant:SetText(status=="confirmation-required" and "Confirm Enchant" or (pending and "Enchanting" or "Enchant"))
    end
    card.enchant.__jlpEnchantState=actionState and actionState.status or "idle"
    setActionButtonEnabled(card.enchant,(not pending) and target~=nil and (not readiness or readiness.immediateBagsKnown ~= false) and (tonumber(readiness and readiness.immediateBags) or 0)>0)
end

local function setCraftActionButtons(card,key,plan,readiness)
    if not card or not card.craftOne or not card.craftAll then return end
    local crafting=JLP:GetModule("Crafting")
    local actionState=crafting and crafting.GetCraftActionState and crafting:GetCraftActionState(key,plan) or nil
    local status=actionState and actionState.status or "idle"
    local pending=status=="dispatching" or status=="pending" or status=="crafting" or status=="awaiting-user" or status=="recovery_unresolved"
    local mode=actionState and actionState.mode or nil
    if card.craftOne.SetText then card.craftOne:SetText(pending and mode=="one" and "Crafting" or "Craft One") end
    if card.craftAll.SetText then card.craftAll:SetText(pending and mode=="all" and "Crafting" or "Craft All") end
    card.craftOne.__jlpCraftState=status
    card.craftAll.__jlpCraftState=status
    card.craftOne.__jlpCraftToken=actionState and actionState.token or nil
    card.craftAll.__jlpCraftToken=actionState and actionState.token or nil
    card.craftAll.__jlpCraftProgress=actionState and {completed=actionState.completedCount or 0,requested=actionState.requestedCount or 0} or nil
    local canCraft=(not readiness or readiness.immediateBagsKnown ~= false) and (tonumber(readiness and readiness.immediateBags) or 0)>0
    setActionButtonEnabled(card.craftOne,(not pending) and canCraft)
    setActionButtonEnabled(card.craftAll,(not pending) and canCraft)
    if card.craftX then
        local waiting=key=="TAILORING" and actionState and actionState.strictAwaitingUserClick==true
        if card.craftX.SetText then card.craftX:SetText(waiting and "Next Craft" or "Craft X") end
        setActionButtonEnabled(card.craftX,waiting or (not pending and canCraft))
        if card.craftXInput and card.craftXInput.SetEnabled then card.craftXInput:SetEnabled(not waiting) end
    end
end

local function announce(ok, message)
    if message and JLP.Print then JLP:Print(message) end
    return ok
end

local function performCraft(key, plan, mode)
    if mode == "all" then return announce(false,"Craft All requires the guarded ordinal authority. Use /jlp craftingunlock on and verify current recipe eligibility.") end
    local crafting=JLP:GetModule("Crafting")
    if not crafting then return announce(false,"Direct profession crafting is unavailable.") end
    local ok,message=crafting:ExecuteCraft(key,plan,mode)
    local result=announce(ok,message)
    if Page.Refresh then Page:Refresh() end
    return result
end

local function controlledNativeAuthorityForProfession(key)
    key=tostring(key or ""):upper()
    if key=="TAILORING" then
        return JLP:GetModule("ProductionTailoringNativeExecutionAuthority"), "tailoringnative"
    elseif key=="ENCHANTING" then
        return JLP:GetModule("ProductionEnchantingNativeExecutionAuthority"), "enchantingnative"
    end
    return JLP:GetModule("ResearchNativeExecutionAuthority"), "nativeexecution"
end

local function performResearchPreDispatch(card)
    local key=card and card.__professionKey or nil
    local consumer=card and card.__consumerSnapshot or nil
    local mode=consumer and consumer.mode or nil
    local authorityGate=JLP:GetModule("ResearchExecutionAuthorityGate")
    local authorityEnabled=authorityGate and authorityGate.IsFeatureEnabled and authorityGate:IsFeatureEnabled() or false
    local nativeAuthority,nativeCommand=controlledNativeAuthorityForProfession(key)
    local nativeEnabled=nativeAuthority and nativeAuthority.IsFeatureEnabled and nativeAuthority:IsFeatureEnabled() or false
    local ok,state,report,message

    if authorityEnabled and nativeEnabled then
        local origin,originState=authorityGate:BeginClickOrigin(key,mode,"profession-guide")
        if not origin then
            ok=false; state=originState
        else
            ok,state,report=nativeAuthority:Request(key,mode,origin)
        end
        if ok then
            if tostring(key or ""):upper()=="ENCHANTING" then
                message=string.format("Guarded native Enchant One dispatched for %s to the selected Optional Target; any protected replace/bind confirmation remains a Blizzard secure-click boundary.",tostring(report and report.recipe or "the current enchant"))
            else
                message=string.format("Guarded native Craft One dispatched for %s; completion remains transaction-reconciled.",tostring(report and report.recipe or "the current recipe"))
            end
        else
            local detail=report and (report.blockedGate or report.blockedState or report.reservationValidationState or report.authorityState or report.detail) or nil
            message=(tostring(key or ""):upper()=="ENCHANTING" and "Guarded native Enchant One blocked: " or "Guarded native Craft One blocked: ")..tostring(detail or state or "current native execution authority did not pass").."."
        end
    elseif authorityEnabled then
        local origin,originState=authorityGate:BeginClickOrigin(key,mode,"profession-guide")
        if not origin then
            ok=false; state=originState
        else
            ok,state,report=authorityGate:Request(key,mode,"one",origin)
        end
        if ok then
            message=string.format("Execution-authority eligibility passed for %s; enable /jlp %s on to allow guarded Craft One dispatch.",tostring(report and report.recipe or "the current recipe"),tostring(nativeCommand or "nativeexecution"))
        else
            local detail=report and (report.blockedGate or report.blockedState or report.readinessState or report.reservationValidationState) or nil
            message="Execution-authority eligibility blocked: "..tostring(detail or state or "current guarded eligibility did not pass").."."
        end
    else
        local handoff=JLP:GetModule("ResearchExecutionIntentHandoff")
        if not handoff then return announce(false,"Research shadow pre-dispatch is unavailable.") end
        ok,state,report=handoff:Request(key,mode,"one")
        if ok then
            message=string.format("Shadow pre-dispatch validated for %s; native craft dispatch remains disabled.",tostring(report and report.recipe or "the current recipe"))
        else
            local detail=report and (report.blockedGate or report.blockedState or report.readinessState or report.intentValidationState) or nil
            message="Shadow pre-dispatch blocked: "..tostring(detail or state or "current execution-readiness did not pass").."."
        end
    end
    local result=announce(ok,message)
    if Page.Refresh then Page:Refresh() end
    return result
end



local function controlledCraftAllAuthorityForProfession(key)
    key=tostring(key or ""):upper()
    if key=="TAILORING" then return JLP:GetModule("ProductionTailoringCraftAllAuthority"), true end
    return JLP:GetModule("ResearchNativeCraftAllAuthority"), false
end

local function performResearchCraftAll(card, requestedCrafts)
    local key=card and card.__professionKey or nil
    local consumer=card and card.__consumerSnapshot or nil
    local mode=consumer and consumer.mode or nil
    local craftAll,isTailoring=controlledCraftAllAuthorityForProfession(key)
    if not craftAll then return announce(false,"Guarded Craft All authority is unavailable.") end
    local origin,originState=craftAll:BeginClickOrigin(key,mode,"profession-guide")
    local ok,state,report=false,originState,nil
    local restartAuthorization=nil
    if origin then
        local restart=craftAllRestartModuleForKey(key)
        local restartModel=restart and restart.Evaluate and restart:Evaluate(key,mode) or nil
        if restartModel and restartModel.restartReady==true and restart.PrepareAuthorization then
            local restartState
            restartAuthorization,restartState=restart:PrepareAuthorization(key,mode,origin)
            if not restartAuthorization then
                state=restartState or "craft-all-restart-authorization-unavailable"
            else
                ok,state,report=craftAll:Request(key,mode,origin,{restartAuthorization=restartAuthorization,requestedCrafts=requestedCrafts})
            end
        else
            ok,state,report=craftAll:Request(key,mode,origin,{requestedCrafts=requestedCrafts})
        end
    end
    local message
    if ok then
        local restartNote=report and report.freshRestartTransaction and (" Fresh restart after "..tostring(report.restartedFromInterruptionCategory or "interruption").."; the previous Craft All ledger was not reused.") or ""
        message=string.format("Guarded Craft All started for %s: up to %d crafts of this recipe only. Target skill %s has first stop priority. After each confirmed craft, another click on Next Craft is required for the next ordinal; no automatic protected continuation. Auto Route is separate.%s",tostring(report and report.recipe or "the current recipe"),tonumber(report and report.requestedCount) or 0,tostring(report and report.skillTarget or "?"),restartNote)
    else
        local detail=report and (report.authorizationValidationState or report.readinessState or report.detail or report.state) or state
        message="Guarded Craft All blocked: "..tostring(detail or "current-recipe authority did not pass").."."
    end
    local result=announce(ok,message)
    if Page.Refresh then Page:Refresh() end
    return result
end

local function performCraftX(card)
    local crafting=JLP:GetModule("Crafting")
    local pending=crafting and crafting.pendingCraft
    if pending and pending.key==card.__professionKey and pending.strictAwaitingUserClick==true then
        local planner=JLP:GetModule("Planner")
        local plan=planner and planner.GetProfessionPlan and planner:GetProfessionPlan(card.__professionKey)
        local ok,reason=crafting:ResumeStrictCraftAllFromGuide(card.__professionKey,plan)
        local result=announce(ok,ok and "Next guarded ordinal submitted; awaiting native confirmation." or
            ("Next craft blocked: "..tostring(reason or "UNKNOWN")))
        if Page.Refresh then Page:Refresh() end
        return result
    end
    local field=card and card.craftXInput
    local raw=field and field.GetText and field:GetText() or ""
    local number=tonumber(raw)
    if not raw:match("^%d+$") or not number or number<1 or number>9999 or number%1~=0 then
        return announce(false,"Craft X requires a whole number from 1 to 9999.")
    end
    if not card.__researchCraftAll or card.__professionKey~="TAILORING" then
        return announce(false,"Craft X requires enabled guarded Tailoring ordinal authority; no native batch fallback.")
    end
    return performResearchCraftAll(card,number)
end

local function addCraftXControl(holder,parent)
    local W=JLP.UIWidgets
    holder.craftX=W:Button(parent,"Craft X",70)
    holder.craftX:SetHeight(30);holder.craftX:Hide()
    local input=CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
    input:SetSize(52,28)
    if input.SetAutoFocus then input:SetAutoFocus(false) end
    if input.SetMaxLetters then input:SetMaxLetters(4) end
    input:SetText("1");input:Hide()
    input:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    holder.craftXInput=input
    holder.craftX:SetScript("OnClick",function() performCraftX(holder) end)
end

local function performResearchRouteAuto(card)
    local key=card and card.__professionKey or nil
    local consumer=card and card.__consumerSnapshot or nil
    local mode=consumer and consumer.mode or nil
    local production=JLP:GetModule("ResearchAutoRouteOrchestrator")
    local legacy=JLP:GetModule("ResearchBoundedSequentialCraft")
    local sequential=(production and production.IsFeatureEnabled and production:IsFeatureEnabled(key)) and production or legacy
    if not sequential then return announce(false,"Auto Route orchestration is unavailable.") end
    local ok,state,report
    if sequential==production then ok,state,report=sequential:Request(key,mode,"profession-guide") else ok,state,report=sequential:Request(key,mode,nil,"profession-guide") end
    local message
    if ok then
        local active=sequential:GetSession(key)
        local restartNote=active and active.restartedFromSessionToken and (" Restarted from resolved "..tostring(active.restartedFromBoundaryCategory or "boundary").." boundary using a new explicit Guide click. Lineage generation "..tostring(active.lineageDepth or "?").." is bound only to immediate predecessor "..tostring(active.lineageParentSessionToken or active.restartedFromSessionToken)..".") or ""
        if sequential==production then
            message=string.format("Auto Route started for %s toward target skill %s. It dispatches one Craft One at a time, revalidates after every settlement, and may cross to the next recipe only after the current target is reached and the route handoff is verified.%s",tostring(report and report.currentRecipe or (active and active.currentRecipe) or "the current route"),tostring(active and active.currentSkillTarget or report and report.currentSkillTarget or "?"),restartNote)
        else
            message=string.format("Auto Route started for %s: up to %d individually revalidated Craft One transactions. This is separate from Craft All and may move to the next route recipe only after a full replan.%s",tostring(report and report.currentRecipe or (active and active.currentRecipe) or "the current route"),tonumber(active and active.requestedCount) or sequential:GetConfiguredLimit(),restartNote)
        end
    else
        local detail=report and (report.stopReason or report.state) or state
        message="Auto Route blocked: "..tostring(detail or "current route-sequence authority did not pass").."."
    end
    local result=announce(ok,message)
    if Page.Refresh then Page:Refresh() end
    return result
end

local function setResearchPreDispatchControl(card,consumer,plan)
    if not card or not card.preDispatch then return end
    local visible=consumer~=nil and plan~=nil and plan.actionKind=="craft" and plan.step~=nil
    local authorityGate=JLP:GetModule("ResearchExecutionAuthorityGate")
    local authorityEnabled=authorityGate and authorityGate.IsFeatureEnabled and authorityGate:IsFeatureEnabled() or false
    local nativeAuthority=select(1,controlledNativeAuthorityForProfession(card.__professionKey))
    local nativeEnabled=nativeAuthority and nativeAuthority.IsFeatureEnabled and nativeAuthority:IsFeatureEnabled() or false
    card.preDispatch.__jlpConsumerSnapshot=consumer
    local nativeLabel=tostring(card.__professionKey or ""):upper()=="ENCHANTING" and "Guarded Enchant One" or "Guarded Craft One"
    card.preDispatch:SetText((authorityEnabled and nativeEnabled) and nativeLabel or (authorityEnabled and "Authority Check" or "Shadow Preflight"))
    card.preDispatch:SetShown(visible and true or false)
    setActionButtonEnabled(card.preDispatch,visible)
end


local function setResearchCraftAllControl(card,consumer,plan)
    if not card or not card.craftAll then return end
    local authority,isTailoring=controlledCraftAllAuthorityForProfession(card.__professionKey)
    local effective=authority and authority.IsEffectiveEnabled and authority:IsEffectiveEnabled() or false
    local supported=authority and authority.IsSupported and card.__professionKey and authority:IsSupported(card.__professionKey) or false
    local craftRoute=consumer~=nil and plan~=nil and plan.actionKind=="craft" and plan.step~=nil
    local crafting=JLP:GetModule("Crafting")
    local actionState=crafting and crafting.GetCraftActionState and card.__professionKey and crafting:GetCraftActionState(card.__professionKey,plan) or nil
    local pending=actionState and (actionState.researchNativeCraftAll==true or actionState.productionTailoringCraftAll==true) and (actionState.status=="dispatching" or actionState.status=="pending" or actionState.status=="crafting" or actionState.status=="awaiting-user" or actionState.status=="recovery_unresolved") or false
    local restart=card.__professionKey and currentCraftAllRestart(card.__professionKey) or nil
    local visible=(supported and effective and craftRoute) or (supported and pending) or (supported and restart and restart.restartReady==true)
    card.__researchCraftAllVisible=visible and true or false
    card.__researchCraftAll=visible and true or false
    card.__jlpCraftAllRestart=restart
    card.craftAll.__jlpConsumerSnapshot=consumer
    if pending then
        card.craftAll:SetText(string.format("Crafting %d/%d",tonumber(actionState.completedCount) or 0,math.max(1,tonumber(actionState.requestedCount) or 1)))
    elseif restart and restart.restartReady==true then
        card.craftAll:SetText("Continue Craft All")
    else
        card.craftAll:SetText("Craft All")
    end
    card.craftAll:SetShown(visible and true or false)
    local waitingForClick=pending and actionState and actionState.strictAwaitingUserClick==true
    local craftXEnabled=visible and isTailoring and effective and ((craftRoute and not pending) or waitingForClick)
    if card.craftX then card.craftX:SetShown(craftXEnabled and true or false) end
    if card.craftXInput then card.craftXInput:SetShown(craftXEnabled and not waitingForClick or false) end
    setActionButtonEnabled(card.craftX,craftXEnabled)
    setActionButtonEnabled(card.craftAll,visible and not pending)
end

local function setResearchRouteAutoControl(card,consumer,plan)
    if not card or not card.routeAuto then return end
    local sequenceBoundary=card.__professionKey and currentSequenceBoundary(card.__professionKey) or nil
    local sequenceRestart=(not sequenceBoundary) and card.__professionKey and currentSequenceRestart(card.__professionKey) or nil
    local production=JLP:GetModule("ResearchAutoRouteOrchestrator")
    local legacy=JLP:GetModule("ResearchBoundedSequentialCraft")
    local productionActive=production and card.__professionKey and production.GetSession and production:GetSession(card.__professionKey) or nil
    local useProduction=(production and production.IsFeatureEnabled and production:IsFeatureEnabled(card.__professionKey)) or (productionActive and productionActive.active)
    local sequential=useProduction and production or legacy
    local sequentialEnabled=sequential and sequential.IsEffectiveEnabled and sequential:IsEffectiveEnabled(card.__professionKey) or false
    local activeSequence=sequential and card.__professionKey and sequential.GetSession and sequential:GetSession(card.__professionKey) or nil
    local routeSupported=production and production.IsSupported and card.__professionKey and production:IsSupported(card.__professionKey) or false
    local craftRoute=consumer~=nil and plan~=nil and plan.actionKind=="craft" and plan.step~=nil
    local visible=(routeSupported and sequentialEnabled and craftRoute) or (routeSupported and sequenceBoundary~=nil) or (routeSupported and sequenceRestart and sequenceRestart.restartReady==true) or (routeSupported and activeSequence and activeSequence.active)
    card.__jlpSequenceBoundary=sequenceBoundary
    card.__jlpSequenceRestart=sequenceRestart
    card.routeAuto.__jlpConsumerSnapshot=consumer
    if activeSequence and activeSequence.active then
        if useProduction then card.routeAuto:SetText(string.format("Auto Route · %d casts",tonumber(activeSequence.settledCount) or 0))
        else card.routeAuto:SetText(string.format("Auto Route %d/%d",tonumber(activeSequence.settledCount) or 0,tonumber(activeSequence.requestedCount) or 0)) end
    elseif sequenceBoundary then
        card.routeAuto:SetText("Next: "..tostring(sequenceBoundary.label or "Resolve boundary"))
    elseif sequenceRestart and sequenceRestart.restartReady==true and sequentialEnabled then
        card.routeAuto:SetText(useProduction and "Restart Auto Route" or ("Restart Auto Route x"..tostring(sequential:GetConfiguredLimit())))
    elseif sequentialEnabled and craftRoute then
        card.routeAuto:SetText(useProduction and "Auto Route" or ("Auto Route x"..tostring(sequential:GetConfiguredLimit())))
    else
        card.routeAuto:SetText("Auto Route")
    end
    card.routeAuto:SetShown(visible and true or false)
    local restartBlocked=sequenceRestart and sequenceRestart.restartRequired==true and sequenceRestart.restartReady~=true
    setActionButtonEnabled(card.routeAuto,visible and not sequenceBoundary and not restartBlocked and not (activeSequence and activeSequence.active))
end

-- M1-EOW-MERGE: reviewed popup identity checks merged into M1D+QA002.
-- The documented native authority has confirmationAutomationAllowed=false.
-- This observer does not click protected controls or settle the transaction;
-- it can only identify a *fresh and bound* manual Blizzard confirmation.
-- TRADE_REPLACE_ENCHANT is intentionally excluded from this ordinary-item path.
local function inspectEnchantOverwrite(crafting,key,expected,preexistingPopup)
    if preexistingPopup or key~="ENCHANTING" or type(expected)~="table" then
        return false,"PREEXISTING_OR_UNBOUND"
    end
    local pending=crafting and crafting.pendingEnchant
    if type(pending)~="table" or pending.key~="ENCHANTING" or
       pending.token==nil or pending.token~=expected.token or
       pending.status~="confirmation-required" or
       pending.confirmationRequired~=true or
       pending.confirmationReason~="replace-existing-enchant" or
       pending.confirmationEvent~="REPLACE_ENCHANT" then
        return false,"PENDING_NOT_BOUND"
    end
    -- Bind to recipe and immutable target chosen BEFORE the dispatch. Never
    -- infer item identity from a generic REPLACE_ENCHANT popup name.
    if not expected.recipeID or not expected.targetGUID or
       tonumber(pending.recipeID)~=tonumber(expected.recipeID) or
       tostring(pending.targetGUID)~=tostring(expected.targetGUID) or
       (expected.targetItemID and tonumber(pending.targetItemID)~=tonumber(expected.targetItemID)) then
        return false,"RECIPE_TARGET_CHANGED"
    end
    local started=tonumber(pending.startedAt)
    -- Production confirmationAt is epoch seconds (time()), not GetTime().
    -- Ask Settlement for an independent *transient* GetTime observation bound
    -- to this exact live pending/event. On reload, fail closed. Legacy pending
    -- observations retain their historical same-clock check for manual UI only.
    local eventAt
    if pending.productionEnchantingNativeExecution == true then
        local settlement=JLP and JLP.GetModule and JLP:GetModule("ProductionEnchantingNativeSettlement")
        if not settlement or type(settlement.GetTransientConfirmationObservation)~="function" then
            return false,"TRANSIENT_CONFIRMATION_UNAVAILABLE"
        end
        local at,source=settlement:GetTransientConfirmationObservation(pending)
        if source~="TRANSIENT_EVENT_OBSERVED" then
            return false,"TRANSIENT_CONFIRMATION_UNAVAILABLE"
        end
        eventAt=tonumber(at)
    else
        eventAt=tonumber(pending.confirmationAt)
    end
    local origin=tonumber(expected.clickedAt)
    local now=(type(GetTime)=="function") and tonumber(GetTime()) or nil
    -- Missing timestamps and delayed events are UNKNOWN, never authorization.
    if not started or not eventAt or not origin or not now or
       started<=0 or origin<=0 or eventAt<=0 or now<=0 or
       started<origin or eventAt<started or now<eventAt or
       eventAt-origin>2 or now-origin>2 then
        return false,"STALE_CONFIRMATION"
    end
    local popup=StaticPopup1
    local accept=StaticPopup1Button1
    if not popup or not accept or type(popup.IsShown)~="function" or
       type(accept.IsShown)~="function" or not popup:IsShown() or
       not accept:IsShown() or popup.which~="REPLACE_ENCHANT" or
       (type(accept.IsEnabled)=="function" and not accept:IsEnabled()) or
       (type(accept.GetParent)=="function" and accept:GetParent()~=popup) then
        return false,"POPUP_UNRELATED"
    end
    -- This positive result only means manual confirmation is indicated.
    -- It is NEVER a token for protected Click, a success receipt or settlement.
    return true,"MANUAL_CONFIRMATION_REQUIRED"
end

local function performEnchant(key, plan, card)
    local crafting=JLP:GetModule("Crafting")
    if not crafting then return announce(false,"Direct profession crafting is unavailable.") end
    -- One physical Guide OnClick enters this function once. No separate
    -- Blizzard CreateButton click or popup click is attempted.
    local old=crafting.pendingEnchant
    local previousToken=old and old.token
    local shown=StaticPopup1 and type(StaticPopup1.IsShown)=="function" and StaticPopup1:IsShown() or false
    local target,recipeID=nil,nil
    if key=="ENCHANTING" and type(crafting.GetSelectedEnchantTarget)=="function" then
        target,recipeID=crafting:GetSelectedEnchantTarget(key,plan)
    end
    local clickedAt=(type(GetTime)=="function") and tonumber(GetTime()) or nil
    local sameClick=key=="ENCHANTING" and JLP:GetModule("EnchantOneSameClick70450") or nil
    local confirmationTicket=sameClick and sameClick.Begin and
        select(1,sameClick:Begin(crafting,recipeID,target)) or nil
    -- Production Enchant One must use the already implemented, target-bound
    -- guarded click-origin -> reservation -> NativeEnchantingSingleCraftBoundary.
    -- The legacy direct Enchant() path cannot authorize read-only planner plans.
    -- No authority is granted by this UI handler itself.
    local ok,message
    if key=="ENCHANTING" then
        local gate=JLP:GetModule("ResearchExecutionAuthorityGate")
        local native=JLP:GetModule("ProductionEnchantingNativeExecutionAuthority")
        if not gate or not native or not native.IsEffectiveEnabled or not native:IsEffectiveEnabled() then
            return announce(false,"Guarded Enchant One is not enabled. Use /jlp craftingunlock on, then select a valid Optional Target.")
        end
        local mode=card and card.__consumerSnapshot and card.__consumerSnapshot.mode or "normal"
        local origin,originState=gate:BeginClickOrigin(key,mode,"profession-guide")
        if not origin then
            ok=false
            message="Guarded Enchant One click origin unavailable: "..tostring(originState)
        else
            local state,report
            ok,state,report=native:Request(key,mode,origin)
            message=ok and "Guarded Enchant One dispatched; Blizzard may require a separate manual confirmation."
                or ("Guarded Enchant One blocked by runtime verification: "..tostring(report and (report.blockedGate or report.blockedState or report.state) or state))
        end
    else
        ok,message=crafting:Enchant(key,plan)
    end
    local pending=crafting.pendingEnchant
    if ok and pending and pending.token~=previousToken then
        local bound,why=inspectEnchantOverwrite(crafting,key,{
            token=pending.token,recipeID=recipeID,
            targetGUID=target and target.guid or nil,
            targetItemID=target and target.itemID or nil,
            clickedAt=clickedAt,
        },shown)
        if bound then
            -- Exactly this synchronous Guide click may request the *newly
            -- observed* REPLACE_ENCHANT confirmation. The same-click bridge
            -- refuses protected/tainted frames, unrelated dialogs, changed
            -- targets and any deferred event; manual confirmation remains.
            local accepted,confirmationState=false,"MANUAL_ONLY"
            if sameClick and confirmationTicket and sameClick.TrySameClick then
                accepted,confirmationState=sameClick:TrySameClick(confirmationTicket,true)
            end
            message=accepted and
                "Enchant overwrite confirmation requested from the same click; awaiting Blizzard's actual result event." or
                ("Enchant is awaiting Blizzard confirmation. Click Yes manually ("..tostring(confirmationState)..").")
        end
    end
    if sameClick and sameClick.Cancel then sameClick:Cancel(confirmationTicket) end
    local result=announce(ok,message)
    if Page.Refresh then Page:Refresh() end
    return result
end

local function syncEnchantSelectionUI(key,plan,target)
    local readiness=select(1,bundle(key,plan))
    local frame=Page.frame
    if not frame then return end
    local cards={
        frame.dual and frame.dual.left or nil,
        frame.dual and frame.dual.right or nil,
        frame.single and frame.single.plan or nil,
    }
    for _,card in pairs(cards) do
        if card and card.__professionKey==key and card.targetSlot then
            card.targetSlot:SetTarget(target)
            setEnchantActionButton(card,key,plan,readiness,target)
            setActionFeedback(card,key,plan)
        end
    end
end


local function ensureTargetPicker(owner)
    if Page.targetPicker then return Page.targetPicker end
    local W,L=JLP.UIWidgets,JLP.UILayout
    local popup=CreateFrame("Frame","JuztLevelProfessionsOptionalTargetPicker",UIParent or Page.frame or owner)
    popup:SetSize(360,258)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    if popup.SetClampedToScreen then popup:SetClampedToScreen(true) end
    if JLP.UILayout and JLP.UILayout.OverlayFrameLevel then
        popup:SetFrameLevel(JLP.UILayout:OverlayFrameLevel(Page.frame, "modal"))
    end
    popup.__jlpPageOwner=Page.name
    if JLP.UIWindowRegistry then
        JLP.UIWindowRegistry:Register("GuideOptionalTarget",popup,"Guide")
        JLP.UIWindowRegistry:RegisterSpecial("JuztLevelProfessionsOptionalTargetPicker")
    end
    if popup.EnableMouse then popup:EnableMouse(true) end

    -- Use the same skinned secondary-card language as the rest of JuztLevel
    -- instead of the temporary solid-black diagnostic popup used during the
    -- Optional Target interaction investigation.
    W:SkinPanel(popup,"secondary")
    popup.__jlpPickerStyled=true

    popup.title=W:Label(popup,"Optional Target","GameFontNormalLarge")
    popup.title:SetPoint("TOPLEFT",18,-15)
    popup.subtitle=W:Label(popup,"Choose an item to enchant","GameFontHighlightSmall")
    popup.subtitle:SetPoint("TOPLEFT",popup.title,"BOTTOMLEFT",0,-5)
    popup.subtitle:SetTextColor(JLP.UITheme:Color("muted"))
    popup.count=W:Label(popup,"","GameFontHighlightSmall")
    popup.count:SetPoint("TOPRIGHT",-44,-20)
    popup.count:SetTextColor(JLP.UITheme:Color("muted"))

    local rule=popup:CreateTexture(nil,"ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    rule:SetVertexColor(0.31,0.48,0.61,0.50)
    rule:SetPoint("TOPLEFT",18,-58)
    rule:SetPoint("TOPRIGHT",-18,-58)
    rule:SetHeight(1)
    popup.rule=rule

    popup.close=CreateFrame("Button",nil,popup)
    popup.close:SetSize(24,24)
    popup.close:SetPoint("TOPRIGHT",-10,-10)
    popup.close.icon=popup.close:CreateTexture(nil,"ARTWORK")
    popup.close.icon:SetAllPoints()
    popup.close.icon:SetTexture(JLP.UITheme:Asset("window\\close.tga"))
    popup.close:SetScript("OnEnter",function(self) self.icon:SetAlpha(0.78) end)
    popup.close:SetScript("OnLeave",function(self) self.icon:SetAlpha(1.00) end)
    popup.close:SetScript("OnClick",function() popup:Hide() end)

    popup.scroll=L:ScrollArea(popup,{width=336,height=178,contentWidth=322,scrollbarGutter=12,wheelStep=44})
    popup.scroll:SetPoint("TOPLEFT",12,-68)
    popup.rows={}
    popup:Hide()
    Page.targetPicker=popup
    return popup
end

local function setTargetPickerInteractive(popup, enabled)
    if not popup then return end
    if popup.EnableMouse then popup:EnableMouse(enabled and true or false) end
    for _,row in ipairs(popup.rows or {}) do
        if row.EnableMouse then row:EnableMouse(enabled and true or false) end
        if row.SetMouseClickEnabled then pcall(row.SetMouseClickEnabled,row,enabled and true or false) end
        if row.SetMouseMotionEnabled then pcall(row.SetMouseMotionEnabled,row,enabled and true or false) end
    end
    popup.__jlpInteractive=enabled and true or false
end

local function enchantTargetItemID(target)
    target=target or {}
    local itemID=tonumber(target.itemID)
    if not itemID and type(target.link)=="string" then
        itemID=tonumber(target.link:match("item:(%d+)"))
    end
    return itemID
end

local function validItemIcon(value)
    if value == nil or value == false or value == 0 or value == "" then return nil end
    return value
end

local function resolveEnchantTargetIcon(target)
    if JLP.UIIconResolver and JLP.UIIconResolver.GetEnchantTarget then
        return JLP.UIIconResolver:GetEnchantTarget(target,true)
    end
    target=target or {}
    local itemID=enchantTargetItemID(target)
    local icon=validItemIcon(target.icon)
    if not icon and itemID and type(C_Item)=="table" and type(C_Item.GetItemIconByID)=="function" then
        local ok,value=pcall(C_Item.GetItemIconByID,itemID)
        if ok then icon=validItemIcon(value) end
    end
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function refreshTargetPickerVisuals(popup, epoch)
    if not popup or not popup.IsShown or not popup:IsShown() then return end
    if epoch and popup.__jlpVisualEpoch~=epoch then return end
    local crafting=JLP:GetModule("Crafting")
    for _,row in ipairs(popup.rows or {}) do
        if row.__target and row.icon then
            local refreshed=crafting and crafting.RefreshEnchantTargetDescriptor and crafting:RefreshEnchantTargetDescriptor(row.__target) or row.__target
            if refreshed then row.__target=refreshed end
            row.icon:SetTexture(resolveEnchantTargetIcon(row.__target))
            row.icon:Show()
            if row.label and row.__target and row.__target.name then row.label:SetText(row.__target.name) end
        end
    end
end

function Page:RefreshEnchantTargetIcons()
    local popup=self.targetPicker
    if not popup or not popup.IsShown or not popup:IsShown() then return false end
    refreshTargetPickerVisuals(popup,popup.__jlpVisualEpoch)
    return true
end

local function openTargetPicker(anchor,key,plan,retrying)
    -- JuztLevel owns both the compact Optional Target button and this picker.
    -- No detached Blizzard profession template/transaction participates in the
    -- interaction path; the selected ItemLocation is passed directly to CraftEnchant.
    if anchor then
        anchor.__jlpCustomPickerCount=(anchor.__jlpCustomPickerCount or 0)+1
    end
    Page.__targetPickerOpenCalls=(Page.__targetPickerOpenCalls or 0)+1
    local crafting=JLP:GetModule("Crafting")
    if not crafting then return announce(false,"Direct profession crafting is unavailable.") end

    -- Compatibility fallback: show the JuztLevel picker immediately on every click. Target discovery can require
    -- the native profession context, but that should never make a re-click look
    -- like the Optional Target slot stopped responding.
    local popup=ensureTargetPicker(anchor)
    if not popup.__jlpHideGuard then
        popup.__jlpHideGuard=true
        popup:SetScript("OnHide",function(self) setTargetPickerInteractive(self,false) end)
    end
    popup:ClearAllPoints()
    -- Choose above/below and right/left without mixing coordinate spaces.
    -- WoW clamping is the last safeguard on smaller game windows.
    local aBottom=anchor and anchor.GetBottom and anchor:GetBottom() or nil
    local aTop=anchor and anchor.GetTop and anchor:GetTop() or nil
    local aRight=anchor and anchor.GetRight and anchor:GetRight() or nil
    local rootBottom=UIParent and UIParent.GetBottom and UIParent:GetBottom() or 0
    local rootLeft=UIParent and UIParent.GetLeft and UIParent:GetLeft() or 0
    local above=aBottom and (aBottom-rootBottom)<264 and aTop
    local leftward=aRight and (aRight-rootLeft)<360
    if above then
        popup:SetPoint(leftward and "BOTTOMLEFT" or "BOTTOMRIGHT",anchor,
            leftward and "TOPLEFT" or "TOPRIGHT",0,6)
    else
        popup:SetPoint(leftward and "TOPLEFT" or "TOPRIGHT",anchor,
            leftward and "BOTTOMLEFT" or "BOTTOMRIGHT",0,-6)
    end
    popup.title:SetText("Optional Target")
    popup.subtitle:SetText("Reading valid items from the client...")
    popup.count:SetText("")
    if not (JLP.UIWindowRegistry and JLP.UIWindowRegistry:OpenModal("Guide","GuideOptionalTarget")) then
        popup:Show()
    end
    setTargetPickerInteractive(popup,true)

    local targets,recipeID,needsContext=crafting:GetEnchantTargets(key,plan)
    if not recipeID or needsContext then
        for _,row in ipairs(popup.rows or {}) do row:Hide() end
        popup.scroll:SetContentHeight(34,true)
        if retrying then
            popup.title:SetText("No valid Optional Targets")
            popup.subtitle:SetText("No equipped or bag item is valid for this enchant")
            popup.count:SetText("")
            return announce(false,"Valid enchant targets are not available from the client yet.")
        end
        local api=JLP:GetModule("ProfessionAPI")
        local ok,message=false,"Profession API is unavailable."
        if api and api.Open then ok,message=api:Open(key) end
        if ok and type(C_Timer)=="table" and type(C_Timer.After)=="function" then
            C_Timer.After(0.12,function()
                local planner=JLP:GetModule("Planner")
                local livePlan=planner and planner:GetProfessionPlan(key) or plan
                if anchor and (not anchor.IsShown or anchor:IsShown()) then openTargetPicker(anchor,key,livePlan,true) end
            end)
            message="Loading valid enchant targets..."
        else
            popup.title:SetText("No valid Optional Targets")
            popup.subtitle:SetText("No equipped or bag item is valid for this enchant")
            popup.count:SetText("")
        end
        return announce(ok,message)
    end
    local W=JLP.UIWidgets
    local currentTarget=crafting:GetSelectedEnchantTarget(key,plan)
    while #popup.rows<#targets do
        local row=CreateFrame("Button",nil,popup.scroll.content)
        row:SetSize(popup.scroll.__contentWidth,42)
        if row.EnableMouse then row:EnableMouse(true) end
        if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp") end

        row.background=W:Fill(row,"panel","BACKGROUND")
        W:Border(row,"border",1)

        row.iconFrame=CreateFrame("Frame",nil,row)
        row.iconFrame:SetSize(34,34)
        row.iconFrame:SetPoint("LEFT",5,0)
        W:Fill(row.iconFrame,"window","BACKGROUND")
        W:Border(row.iconFrame,"border",1)
        local icon=row.iconFrame:CreateTexture(nil,"ARTWORK")
        icon:SetSize(30,30)
        icon:SetPoint("CENTER")
        row.icon=icon

        local selectedLabel=W:Label(row,"SELECTED","GameFontHighlightSmall")
        selectedLabel:SetPoint("RIGHT",-9,0)
        selectedLabel:SetTextColor(JLP.UITheme:Color("good"))
        selectedLabel:Hide()
        row.selectedLabel=selectedLabel

        local label=W:Label(row,"","GameFontHighlight")
        label:SetPoint("LEFT",row.iconFrame,"RIGHT",10,0)
        label:SetPoint("RIGHT",selectedLabel,"LEFT",-10,0)
        label:SetJustifyH("LEFT")
        row.label=label

        local hover=row:CreateTexture(nil,"ARTWORK")
        hover:SetAllPoints()
        hover:SetTexture("Interface\\Buttons\\WHITE8X8")
        hover:SetVertexColor(0.02,0.32,0.50,0)
        row.hover=hover

        row:SetScript("OnEnter",function(self)
            self.hover:SetVertexColor(0.02,0.32,0.50,0.16)
            local target=self.__target
            if target and JLP.UIInteraction then
                if JLP.UIInteraction.ShowItemLocation then JLP.UIInteraction:ShowItemLocation(self,target)
                else JLP.UIInteraction:ShowItem(self,target.itemID,target.name) end
            end
        end)
        row:SetScript("OnLeave",function(self)
            self.hover:SetVertexColor(0.02,0.32,0.50,0)
            if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self) end
        end)
        popup.rows[#popup.rows+1]=row
    end
    for i,row in ipairs(popup.rows) do
        local target=targets[i]
        row:SetShown(target~=nil)
        if not target then
            row.__target=nil
            if row.selectedLabel then row.selectedLabel:Hide() end
        end
        if target then
            local selectedTarget=target
            local selected=currentTarget and currentTarget.guid and currentTarget.guid==selectedTarget.guid
            row.__target=selectedTarget
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",0,-((i-1)*48))
            row.icon:SetTexture(resolveEnchantTargetIcon(selectedTarget))
            row.icon:Show()
            row.label:SetText(selectedTarget.name or "Enchant target")
            row.label:SetTextColor(JLP.UITheme:Color(selected and "cyan" or "text"))
            row.selectedLabel:SetShown(selected and true or false)
            row.background:SetVertexColor(JLP.UITheme:Color(selected and "panelAlt" or "panel"))
            W:Border(row,selected and "cyan" or "border",1)
            row:SetScript("OnClick",function()
                if anchor then anchor.__jlpCustomItemClickCount=(anchor.__jlpCustomItemClickCount or 0)+1 end
                if JLP.UIInteraction then JLP.UIInteraction:HideTooltip() end
                local ok = crafting.SelectEnchantTarget and crafting:SelectEnchantTarget(recipeID,selectedTarget) or crafting:SetEnchantTarget(recipeID,selectedTarget.guid)
                if not ok then
                    return announce(false,"That Optional Target could not be selected. Reopen Enchanting and try again.")
                end
                -- Release the picker and every row mouse surface BEFORE repainting
                -- the Optional Target control.  This prevents the just-clicked row
                -- from retaining input ownership across the selection transition on
                -- Forever clients.
                setTargetPickerInteractive(popup,false)
                popup:Hide()
                if anchor then anchor.__jlpCustomSelectionCount=(anchor.__jlpCustomSelectionCount or 0)+1 end
                syncEnchantSelectionUI(key,plan,selectedTarget)
            end)
        end
    end
    popup.__jlpVisualEpoch=(popup.__jlpVisualEpoch or 0)+1
    local visualEpoch=popup.__jlpVisualEpoch
    if #targets==0 then
        popup.title:SetText("No valid Optional Targets")
        popup.subtitle:SetText("No equipped or bag item is valid for this enchant")
        popup.count:SetText("")
    else
        popup.title:SetText("Optional Target")
        popup.subtitle:SetText("Choose an item to enchant")
        popup.count:SetText(string.format("%d target%s",#targets,#targets==1 and "" or "s"))
    end
    popup.scroll:SetContentHeight(math.max(42,#targets*48),true)
    refreshTargetPickerVisuals(popup,visualEpoch)
    if type(C_Timer)=="table" and type(C_Timer.After)=="function" then
        C_Timer.After(0.08,function() refreshTargetPickerVisuals(popup,visualEpoch) end)
        C_Timer.After(0.30,function() refreshTargetPickerVisuals(popup,visualEpoch) end)
    end
    return true
end

local function performContextCTA(card)
    if not card or not card.contextCTA then return announce(false,"Contextual action is unavailable.") end
    local model=card.contextCTA.__jlpContextAction
    if not model then return announce(false,"Contextual action is unavailable.") end
    local context=JLP:GetModule("ContextAction")
    local ok,message
    if model.kind=="CHOOSE_TARGET" then
        if not card.targetSlot or not card.__plan then return announce(false,"Optional Target is unavailable for the current step.") end
        openTargetPicker(card.targetSlot,card.__professionKey,card.__plan)
        ok,message=true,"Choose the item to enchant in Optional Target."
    elseif context and context.Execute then
        ok,message=context:Execute(model)
    else
        ok,message=false,"Contextual action layer is unavailable."
    end
    announce(ok,message)
    if Page.Refresh then Page:Refresh() end
    return ok
end

local function setContextCTA(card,nextBest,key,isDual)
    if not card or not card.contextCTA then return nil end
    local context=JLP:GetModule("ContextAction")
    local model=context and context:Build(nextBest,key) or nil
    local visible=model~=nil
    if model and model.kind=="COMPLETE" and isDual then visible=false end
    card.contextCTA.__jlpContextAction=model
    card.__contextAction=model
    if model and card.contextCTA.SetText then card.contextCTA:SetText(model.label or "Next Action") end
    setActionButtonEnabled(card.contextCTA,visible and model and model.enabled~=false)
    if card.contextCTA.SetActiveState then card.contextCTA:SetActiveState(visible and model and model.enabled~=false,model and model.tone or "gold") end
    if card.contextCTA.SetShown then card.contextCTA:SetShown(visible) elseif visible then card.contextCTA:Show() else card.contextCTA:Hide() end
    return model
end

local function sourceParts(source,professionKey,rankGate)
    source=source or {}
    local name,zone=source.name or "Profession trainer",source.zone or "Zone unavailable"
    local coord="Coordinates unavailable"
    local resolver=JLP:GetModule("SourceResolver")
    -- The imported Horde trainer source is consulted here, not only by a
    -- diagnostic slash command. NEVER use raw nav when map IDs conflict.
    if resolver and professionKey and rankGate and rankGate.rank and
        type(resolver.GetHordeTrainerResearch)=="function" then
        local catalog=resolver:GetHordeTrainerResearch(professionKey,rankGate.rank)
        local selected
        for _,record in ipairs(catalog and catalog.trainers or {}) do
            if record.name==name then selected=record;break end
        end
        -- Do not replace a runtime planner-selected trainer with a different
        -- imported NPC merely because that NPC is first in the research list.
        -- Only an exact name match can qualify the imported navigation.
        if not selected and name=="Profession trainer" then
            selected=catalog and catalog.trainers and catalog.trainers[1]
        end
        if selected then
            name=selected.name or name;zone=selected.zone or zone
            local qualified=resolver.GetQualifiedHordeTrainerNav and
                resolver:GetQualifiedHordeTrainerNav(professionKey,rankGate.rank,name)
            if qualified and selected.navigationMapIDQualified==true and
                type(qualified.x)=="number" and type(qualified.y)=="number" then
                -- Preserve existing planner precision/readout for known trainers.
                -- The adapter is still called to check qualification; only
                -- imported NPCs without a planner coordinate need its target.
                if not (source.nav and source.nav.x and source.nav.y) then
                    coord=string.format("Map %s · %.1f, %.1f · source waypoint (not client-tested)",
                        tostring(qualified.mapID),qualified.x*100,qualified.y*100)
                end
            else
                coord="MANUAL TRAINER LOCATION · "..tostring(selected.navigationStatus or "NAV_UNQUALIFIED")
            end
        end
    end
    if coord=="Coordinates unavailable" and source.nav and source.nav.x and source.nav.y then
        coord=string.format("%.1f, %.1f",source.nav.x*100,source.nav.y*100)
    end
    return name,source.area or "Area unavailable",zone,coord
end

local function ensureMaterialRows(card,count,detailed)
    local C=JLP.UIComponents
    card.materialRows=card.materialRows or {}
    while #card.materialRows<count do
        card.materialRows[#card.materialRows+1]=C:MaterialRow(card.scroll.content,card.scroll.__contentWidth,detailed,true)
    end
    for i,row in ipairs(card.materialRows) do row:SetShown(i<=count) end
end

local function ensureRequirementRows(card,count)
    local C=JLP.UIComponents
    card.requirementRows=card.requirementRows or {}
    while #card.requirementRows<count do
        card.requirementRows[#card.requirementRows+1]=C:RequirementRow(card.scroll.content,card.scroll.__contentWidth)
    end
    for i,row in ipairs(card.requirementRows) do row:SetShown(i<=count) end
end

local function requirementModel(key,plan)
    local module=JLP:GetModule("RequirementPlan")
    return module and module:Build(key,plan) or {rows={}}
end

local function layoutRequirementRows(card,model,startY)
    local y=startY
    local rows=model and model.rows or {}
    ensureRequirementRows(card,#rows)
    for i,rowWidget in ipairs(card.requirementRows or {}) do
        if rows[i] then
            rowWidget:ClearAllPoints(); rowWidget:SetPoint("TOPLEFT",0,-y); rowWidget:SetRequirement(rows[i]); rowWidget:Show()
            y=y+(rowWidget.__layoutHeight or (rowWidget.GetHeight and rowWidget:GetHeight()) or 64)+6
        else
            rowWidget:Hide()
        end
    end
    return y
end

local function hideRequirementRows(card)
    for _,row in ipairs(card.requirementRows or {}) do row:Hide() end
end

local function setDualDataset(card,key,description)
    local maturity=maturityStatus(key)
    card.dataset:SetText(maturity.label.." · "..tostring(description or ""))
    card.maturityExplanation=maturity.detail
end

local function buildDualProfessionCard(parent,title,width,height)
    local W,C,L=JLP.UIWidgets,JLP.UIComponents,JLP.UILayout
    local card=W:Card(parent,title,"primary"); card:SetSize(width,height)
    card.gatheringMap=W:Button(card,"Gathering Map",136)
    card.gatheringMap:SetHeight(26);card.gatheringMap:SetPoint("BOTTOMRIGHT",-18,10)
    card.skinningMaterials=W:Button(card,"Skinning Materials",148)
    card.skinningMaterials:SetHeight(26)
    card.skinningMaterials:SetPoint("RIGHT",card.gatheringMap,"LEFT",-8,0)
    card.skinningMaterials:SetScript("OnClick",function()
        local browser=JLP:GetModule("SkinningMaterialsBrowser")
        if browser then browser:Open("LEATHER") end
    end)
    card.skinningMaterials:Hide()
    card.navigateTo=W:Button(card,"Navigate To · UNKNOWN",152)
    card.navigateTo:SetHeight(26);card.navigateTo:SetPoint("BOTTOMRIGHT",-18,10)
    local navActions=JLP:GetModule("IntegratedNavigationActions")
    if navActions then navActions:Bind(card.navigateTo,function(source)return navActions:CategoryForSource(source)end,function()
        return card.__navigationSource
    end,function()return {explicit=true,owner="GUIDE_DUAL_USER_CLICK",
        planRevision=card.__plan and card.__plan.revision,
        contextToken=card.__navigationContextToken,
        characterKey=card.__navigationCharacterKey,
        sourceIssue=card.__navigationSourceReason}end)end
    card.navigateTo:Hide()
    card.gatheringEvidence=W:Label(card,gatheringEvidenceLabel(),"GameFontHighlightSmall")
    card.gatheringEvidence:SetPoint("BOTTOMLEFT",18,16)
    card.gatheringEvidence:SetPoint("RIGHT",card.gatheringMap,"LEFT",-8,0)
    card.gatheringEvidence:SetHeight(16)
    if card.gatheringEvidence.SetWordWrap then card.gatheringEvidence:SetWordWrap(false) end
    function card:SetFooterEvidenceOwner(skinningShown)
        local anchor=skinningShown and self.skinningMaterials or self.gatheringMap
        self.gatheringEvidence:ClearAllPoints()
        self.gatheringEvidence:SetPoint("BOTTOMLEFT",self,"BOTTOMLEFT",18,16)
        self.gatheringEvidence:SetPoint("RIGHT",anchor,"LEFT",-8,0)
    end
    card.gatheringEvidence:SetTextColor(JLP.UITheme:Color("muted"))
    card.gatheringMap:SetScript("OnClick",function()
        local coordinator=JLP:GetModule("GatheringWindowCoordinator")
        if coordinator then coordinator:Open("GUIDE",Page:GetMode())
        elseif JLP.StandaloneGatheringMap then JLP.StandaloneGatheringMap:Show() end
    end)
    -- Fixed action footer is 36 logical units tall. The scrolling content
    -- may not enter its hitbox, even at the bottom of a gathering guide.
    card.scroll=L:CardScrollArea(card,{cardWidth=width,cardHeight=height,bottom=52})
    local c=card.scroll.content

    card.profIcon=C:Icon(c,44); card.profIcon:SetPoint("TOPLEFT",0,-4)
    card.skill=W:Label(c,"Skill: 0 / 300","GameFontHighlightLarge"); card.skill:SetPoint("TOPLEFT",card.profIcon,"TOPRIGHT",12,-2)
    card.dataset=W:Label(c,"","GameFontHighlightSmall"); card.dataset:SetPoint("TOPLEFT",card.skill,"BOTTOMLEFT",0,-8); card.dataset:SetPoint("TOPRIGHT",-112,-34); card.dataset:SetTextColor(JLP.UITheme:Color("muted"))
    card.badge=W:StatusPill(card,"BLOCKED","bad",94); card.badge:SetPoint("TOPRIGHT",-22,-16)
    card.preDispatch=W:Button(card,"Shadow Preflight",140); card.preDispatch:SetHeight(30); card.preDispatch:SetPoint("RIGHT",card.badge,"LEFT",-8,0); card.preDispatch:Hide()
    card.preDispatch:SetScript("OnClick",function() performResearchPreDispatch(card) end)

    card.gatheringGenerate=W:Button(c,"Generate Gathering Route",205)
    card.gatheringGenerate:SetHeight(30)
    card.gatheringGenerate:SetScript("OnClick",function()
        local coordinator=JLP:GetModule("GatheringWindowCoordinator")
        if coordinator then coordinator:Open("GUIDE",Page:GetMode()) end
        if JLP.StandaloneGatheringMap then JLP.StandaloneGatheringMap:GenerateRoute() end
    end)
    card.gatheringGenerate:Hide()
    card.stepLabel=C:SectionTitle(c,"CURRENT STEP"); card.stepLabel:SetPoint("TOPLEFT",0,-62)
    card.stepBlock=C:ActionBlock(c,card.scroll.__contentWidth,true); card.stepBlock:SetPoint("TOPLEFT",0,-84)
    card.craftOne=W:Button(c,"Craft One",92); card.craftOne:SetHeight(30); card.craftOne:Hide()
    card.craftAll=W:Button(c,"Craft All",92); card.craftAll:SetHeight(30); card.craftAll:Hide()
    addCraftXControl(card,c)
    card.routeAuto=W:Button(c,"Auto Route",110); card.routeAuto:SetHeight(30); card.routeAuto:SetPoint("LEFT",card.craftAll,"RIGHT",10,0); card.routeAuto:Hide()
    card.routeAuto:SetScript("OnClick",function() performResearchRouteAuto(card) end)
    card.enchant=W:Button(c,"Enchant",92); card.enchant:SetHeight(30); card.enchant:Hide()
    card.targetSlot=C:EnchantTargetSlot(c,30); card.targetSlot:Hide()
    card.actionFeedback=W:Label(c,"","GameFontHighlightSmall"); card.actionFeedback:SetPoint("TOPLEFT",0,-182); card.actionFeedback:SetPoint("TOPRIGHT",0,-182); card.actionFeedback:SetHeight(16); card.actionFeedback:Hide(); installCraftFeedbackClock(card)
    card.contextCTA=W:Button(c,"Next Action",176); card.contextCTA:SetHeight(32); card.contextCTA:Hide()
    card.contextCTA:SetScript("OnClick",function() performContextCTA(card) end)
    card.craftOne:SetScript("OnClick",function() if card.__plan then performCraft(card.__professionKey,card.__plan,"one") end end)
    card.craftAll:SetScript("OnClick",function() if card.__researchCraftAll then performResearchCraftAll(card) elseif card.__plan then performCraft(card.__professionKey,card.__plan,"all") end end)
    card.enchant:SetScript("OnClick",function() if card.__plan then performEnchant(card.__professionKey,card.__plan,card) end end)
    card.targetSlot:SetPickerHandler(function(self) if card.__plan then openTargetPicker(self,card.__professionKey,card.__plan) end end)
    card.meta=W:Label(c,"","GameFontHighlight"); card.meta:Hide()
    card.stepTitle=W:Label(c,"","GameFontNormalLarge"); card.stepTitle:Hide()
    card.rule1=W:SectionRule(c); card.rule1:SetPoint("TOPLEFT",0,-144); card.rule1:SetPoint("TOPRIGHT",0,-144)

    card.nextLabel=C:SectionTitle(c,"NEXT ACTION"); card.nextLabel:SetPoint("TOPLEFT",0,-156)
    card.nextBlock=C:ActionBlock(c,card.scroll.__contentWidth,true); card.nextBlock:SetPoint("TOPLEFT",0,-178)
    card.requirementRows={}
    card.nextAction=W:Body(c); card.nextAction:Hide()
    card.rule2=W:SectionRule(c); card.rule2:SetPoint("TOPLEFT",0,-238); card.rule2:SetPoint("TOPRIGHT",0,-238)

    card.readyLabel=C:SectionTitle(c,"READINESS & WORKSPACE"); card.readyLabel:SetPoint("TOPLEFT",0,-250)
    card.readinessRows={}
    for i=1,17 do card.readinessRows[i]=C:KeyValueRow(c,card.scroll.__contentWidth); card.readinessRows[i]:SetPoint("TOPLEFT",0,-274-((i-1)*24)) end
    card.readiness=W:Body(c); card.readiness:Hide()
    card.rule3=W:SectionRule(c); card.rule3:SetPoint("TOPLEFT",0,-350); card.rule3:SetPoint("TOPRIGHT",0,-350)

    card.materialLabel=C:SectionTitle(c,"MATERIAL SNAPSHOT"); card.materialLabel:SetPoint("TOPLEFT",0,-362)
    card.materialRows={C:MaterialRow(c,card.scroll.__contentWidth,false,true),C:MaterialRow(c,card.scroll.__contentWidth,false,true)}
    card.materialRows[1]:SetPoint("TOPLEFT",0,-386); card.materialRows[2]:SetPoint("TOPLEFT",0,-466)
    card.trainerRows={}
    for i=1,3 do card.trainerRows[i]=C:KeyValueRow(c,card.scroll.__contentWidth); card.trainerRows[i]:SetPoint("TOPLEFT",0,-390-((i-1)*30)); card.trainerRows[i]:Hide() end
    card.materials=W:Body(c); card.materials:Hide()
    card.gatheringSources=W:Label(c,"","GameFontHighlightSmall")
    card.gatheringSources:SetPoint("TOPLEFT",0,-543)
    card.gatheringSources:SetWidth(card.scroll.__contentWidth)
    if card.gatheringSources.SetWordWrap then card.gatheringSources:SetWordWrap(true) end
    card.gatheringSources:SetHeight(24)
    card.gatheringSources:Hide()
    card.route=W:Label(c,"","GameFontHighlightSmall"); card.route:Hide()
    card.workspace=W:Label(c,"","GameFontHighlightSmall"); card.workspace:Hide()
    card.scroll:SetContentHeight(546)
    card.__dualTemplate="profession-guide-primary"; card.__assetVariant="primary"; card.__layoutWidth=width; card.__layoutHeight=height
    return card
end

local function stableSetShown(frame, shown)
    if not frame then return end
    shown=shown and true or false
    if frame.IsShown then
        local ok,current=pcall(frame.IsShown,frame)
        if ok and current==shown then return end
    end
    if frame.SetShown then frame:SetShown(shown)
    elseif shown and frame.Show then frame:Show()
    elseif (not shown) and frame.Hide then frame:Hide() end
end

local function setDirectControls(card,directMode)
    stableSetShown(card.craftOne,directMode=="craft")
    stableSetShown(card.craftAll,directMode=="craft" or card.__researchCraftAllVisible==true)
    stableSetShown(card.enchant,directMode=="enchant")
    stableSetShown(card.targetSlot,directMode=="enchant")
end

-- UI spacing contract for dual crafting cards. This is intentionally local
-- to the Guide: it does not change the shared MaterialRow component or
-- alter the underlying planner, material quantities, or read-only research.
-- Each row keeps a minimum below its icon and the longest visible text line.
local function compactDualMaterialHeight(widget,material)
    local measured=tonumber(widget and widget.__layoutHeight) or 76
    local hasDependency=material and material.craftedFrom~=nil
    local minimum=hasDependency and 100 or 68
    return math.max(minimum,measured-8)
end

local function layoutDualCard(card,mode,reqModel,materialRows)
    card.__lastGuideLayoutMode=mode
    card.__lastGuideRequirementModel=reqModel
    card.__lastGuideMaterialRows=materialRows
    card.__gatheringGuideLayout=nil
    -- Current Step starts 84 units below the scroll content top. Its own
    -- measured bottom, not the original 54px template, owns the next section.
    local stepH=card.stepBlock:Relayout()
    local y=84+stepH+6
    if card.nextBlock then card.nextBlock:Relayout() end
    local directMode=card.__directMode
    setDirectControls(card,directMode)
    if directMode=="craft" then
        if card.__appliedDirectMode~="craft" then
            card.craftOne:ClearAllPoints(); card.craftOne:SetPoint("TOPLEFT",card.stepBlock,"BOTTOMLEFT",0,-4)
            card.craftAll:ClearAllPoints(); card.craftAll:SetPoint("LEFT",card.craftOne,"RIGHT",10,0)
            card.routeAuto:ClearAllPoints(); card.routeAuto:SetPoint("LEFT",card.craftAll,"RIGHT",10,0)
            card.__directControlAnchorCount=(card.__directControlAnchorCount or 0)+1
        end
        y=y+38
    elseif directMode=="enchant" then
        if card.__appliedDirectMode~="enchant" then
            card.enchant:ClearAllPoints(); card.enchant:SetPoint("TOPLEFT",card.stepBlock,"BOTTOMLEFT",0,-4)
            card.targetSlot:ClearAllPoints(); card.targetSlot:SetPoint("LEFT",card.enchant,"RIGHT",10,0)
            card.__directControlAnchorCount=(card.__directControlAnchorCount or 0)+1
            if card.targetSlot then card.targetSlot.__jlpAnchorCount=card.__directControlAnchorCount end
        end
        y=y+38
    elseif card.__researchCraftAllVisible==true or (card.routeAuto and card.routeAuto.IsShown and card.routeAuto:IsShown()) then
        if card.__researchCraftAllVisible==true then
            card.craftAll:ClearAllPoints(); card.craftAll:SetPoint("TOPLEFT",card.stepBlock,"BOTTOMLEFT",0,-4)
            card.routeAuto:ClearAllPoints(); card.routeAuto:SetPoint("LEFT",card.craftAll,"RIGHT",10,0)
        else
            card.routeAuto:ClearAllPoints(); card.routeAuto:SetPoint("TOPLEFT",card.stepBlock,"BOTTOMLEFT",0,-4)
        end
        y=y+38
    end
    if card.actionFeedback and card.actionFeedback.IsShown and card.actionFeedback:IsShown() then
        card.actionFeedback:ClearAllPoints(); card.actionFeedback:SetPoint("TOPLEFT",0,-y); card.actionFeedback:SetPoint("TOPRIGHT",0,-y); y=y+20
    end
    if card.craftX and card.craftX.IsShown and card.craftX:IsShown() then
        card.craftXInput:ClearAllPoints()
        card.craftXInput:SetPoint("TOPLEFT",card.craftAll,"BOTTOMLEFT",4,-5)
        card.craftX:ClearAllPoints()
        card.craftX:SetPoint("LEFT",card.craftXInput,"RIGHT",9,0)
        y=y+38
    end
    card.__appliedDirectMode=directMode
    card.rule1:ClearAllPoints(); card.rule1:SetPoint("TOPLEFT",0,-y); card.rule1:SetPoint("TOPRIGHT",0,-y); y=y+12
    card.nextLabel:ClearAllPoints(); card.nextLabel:SetPoint("TOPLEFT",0,-y)
    y=y+24
    if mode=="craft" then
        card.nextBlock:Hide()
        y=layoutRequirementRows(card,reqModel,y)
    else
        hideRequirementRows(card)
        card.nextBlock:Show(); card.nextBlock:ClearAllPoints(); card.nextBlock:SetPoint("TOPLEFT",0,-y)
        y=y+card.nextBlock:GetHeight()+4
    end
    card.rule2:ClearAllPoints(); card.rule2:SetPoint("TOPLEFT",0,-y); card.rule2:SetPoint("TOPRIGHT",0,-y); y=y+14
    card.readyLabel:ClearAllPoints(); card.readyLabel:SetPoint("TOPLEFT",0,-y)
    y=y+GUIDE_SECTION_LINE_HEIGHT+GUIDE_SECTION_GAP
    for _,row in ipairs(card.readinessRows or {}) do
        y=layoutGuideReadinessRow(row,y)
    end
    if card.contextCTA and card.contextCTA.IsShown and card.contextCTA:IsShown() then
        card.contextCTA:ClearAllPoints(); card.contextCTA:SetPoint("TOPLEFT",0,-y)
        y=y+32+GUIDE_SECTION_GAP
    end
    card.rule3:ClearAllPoints(); card.rule3:SetPoint("TOPLEFT",0,-y); card.rule3:SetPoint("TOPRIGHT",0,-y); y=y+14
    card.materialLabel:ClearAllPoints(); card.materialLabel:SetPoint("TOPLEFT",0,-y); y=y+21
    if mode=="craft" then
        for i,rowWidget in ipairs(card.materialRows or {}) do
            local row=materialRows and materialRows[i]
            if row then
                rowWidget:ClearAllPoints(); rowWidget:SetPoint("TOPLEFT",0,-y); rowWidget:SetMaterial(row); rowWidget:Show()
                -- SetMaterial has already measured wrapped content. Only its
                -- unused visual tail is shortened; long lines still grow.
                local rowHeight=compactDualMaterialHeight(rowWidget,row)
                rowWidget:SetHeight(rowHeight); rowWidget.__layoutHeight=rowHeight
                y=y+rowHeight+4
            else rowWidget:Hide() end
        end
        for _,row in ipairs(card.trainerRows or {}) do row:Hide() end
    elseif mode=="train" then
        for _,row in ipairs(card.materialRows or {}) do row:Hide() end
        for _,row in ipairs(card.trainerRows or {}) do
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-y); row:Show(); y=y+30
        end
    else
        for _,row in ipairs(card.materialRows or {}) do row:Hide() end
        for _,row in ipairs(card.trainerRows or {}) do row:Hide() end
    end
    card.scroll:SetContentHeight(y+8,true)
end

-- One geometry owner for existing Dual Gathering content, including resize.
-- Do not regenerate route data or source rights on a viewport change.
local function layoutDualGatheringCard(card)
    local stepBottom=84+card.stepBlock:Relayout()
    local gatherTop=stepBottom+9
    local nextLabelTop=gatherTop+30+19
    local nextBlockTop=nextLabelTop+26
    local nextBlockBottom=nextBlockTop+card.nextBlock:Relayout()
    local ruleTop=nextBlockBottom+14
    local readyTop=ruleTop+15
    card.rule1:ClearAllPoints();card.rule1:SetPoint("TOPLEFT",0,-(gatherTop+37));card.rule1:SetPoint("TOPRIGHT",0,-(gatherTop+37))
    card.gatheringGenerate:ClearAllPoints();card.gatheringGenerate:SetPoint("TOPLEFT",0,-gatherTop)
    -- Gathering has a fixed Map/footer, but its scroll content must
    -- still grow for wrapped Current Step and Next Action text.
    card.nextLabel:ClearAllPoints();card.nextLabel:SetPoint("TOPLEFT",0,-nextLabelTop)
    card.nextBlock:ClearAllPoints();card.nextBlock:SetPoint("TOPLEFT",0,-nextBlockTop);card.nextBlock:Show()
    card.rule2:ClearAllPoints();card.rule2:SetPoint("TOPLEFT",0,-ruleTop);card.rule2:SetPoint("TOPRIGHT",0,-ruleTop)
    card.readyLabel:ClearAllPoints();card.readyLabel:SetPoint("TOPLEFT",0,-readyTop)
    local readinessY=readyTop+GUIDE_SECTION_LINE_HEIGHT+GUIDE_SECTION_GAP
    for i,row in ipairs(card.readinessRows) do
        if i<=6 then
            readinessY=layoutGuideReadinessRow(row,readinessY)
        else
            row:Hide()
        end
    end
    card.rule3:ClearAllPoints();card.rule3:SetPoint("TOPLEFT",0,-readinessY);card.rule3:SetPoint("TOPRIGHT",0,-readinessY)
    local materialLabelY=readinessY+16
    card.materialLabel:ClearAllPoints();card.materialLabel:SetPoint("TOPLEFT",0,-materialLabelY)
    -- The last content element starts below the section label. Measure
    -- its actual multiline extent rather than fixing the scroll child.
    -- The fixed footer is outside this scroll viewport.
    local sourceWidth=math.max(100,card.scroll.__contentWidth or 300)
    card.gatheringSources:SetWidth(sourceWidth)
    card.gatheringSources:SetHeight(16000)
    local measured=card.gatheringSources.GetStringHeight and card.gatheringSources:GetStringHeight() or 24
    measured=math.max(24,math.min(16000,tonumber(measured) or 24))
    card.gatheringSources:SetHeight(measured+4)
    card.__gatherSourcesTop=materialLabelY+27
    card.gatheringSources:ClearAllPoints();card.gatheringSources:SetPoint("TOPLEFT",0,-card.__gatherSourcesTop)
    card.scroll:SetContentHeight(card.__gatherSourcesTop+measured+28,true)
end

local function setDualCard(card,p)
    card.__gatheringGuideLayout=nil
    card.__lastGuideLayoutMode=nil
    -- The 52-unit inset belongs to gathering cards with fixed Map/footer
    -- controls. Crafting cards have no fixed footer; leaving that inset
    -- clips their final Horde research button above an artificial blank tail.
    if card.scroll and card.scroll.SetCardBottomInset then
        card.scroll:SetCardBottomInset(isGatheringProfession(p.key) and 52 or 42)
    end
    card.__navigationSource=nil
    if card.navigateTo then card.navigateTo:Hide() end
    if p.key=="HERBALISM" or p.key=="MINING" then
        local presenter=JLP:GetModule("GatheringGuidePresentation")
        local data=presenter and presenter:Build(p.key,p.skill,p.maxSkill)
        if data then
            card.__professionKey=p.key;card.__plan=nil;card.__directMode=nil
            card.__researchCraftAllVisible=false
            setDirectControls(card,nil)
            card.__consumerSnapshot=nil;card.__consumerAuthorityState=nil
            card.profIcon:SetProfession(p.key,p)
            card.heading:SetText((p.name or p.key).." 1-300")
            card.skill:SetText("Skill: "..data.skill.." / "..data.maxSkill)
            card.badge:SetStatus(data.routeStopCount>0 and "ROUTE READY" or "GATHERING","good")
            setDualDataset(card,p.key,"Historical node references; manual gathering only")
            card.stepLabel:SetText(data.currentStep and "CURRENT STEP" or "CURRENT GATHERING OBJECTIVE")
            card.stepBlock:SetAction(JLP.UIIconResolver:GetProfession(p.key,p),
                data.objectiveTitle or ("Gather in "..data.zoneName),data.currentStep and data.nextAction or data.resourceText)
            card.nextLabel:SetText(data.currentStep and "NEXT ACTION" or "NEXT GATHERING ACTION")
            card.nextBlock:SetAction(JLP.UIIconResolver:GetProfession(p.key,p),
                data.objectiveTitle or (data.routeStopCount>0 and "Follow gathering route" or "Select resources and generate route"),data.nextAction)
            card.readyLabel:SetText("GATHERING READINESS")
            card.materialLabel:SetText("GATHERING SOURCES")
            card.materials:SetText(data.qualification)
            if data.smeltingCandidate then card.materials:SetText(data.smeltingCandidate.explanation) end
            if card.gatheringSources then card.gatheringSources:SetText(data.resourceText.."\n"..(data.sourceSummary or (data.smeltingCandidate and data.smeltingCandidate.explanation or data.qualification)));card.gatheringSources:Show() end
            card.gatheringGenerate:SetShown(not data.currentStep or data.currentStep.kind=="gather")
            card.preDispatch:Hide();card.routeAuto:Hide();card.actionFeedback:Hide()
            card.targetSlot:SetTarget(nil);card.contextCTA:Hide()
            card.skinningMaterials:Hide()
            card:SetFooterEvidenceOwner(false)
            for i,row in ipairs(card.readinessRows) do
                if i==1 then row:SetRow("profession","Profession skill",data.skill.." / "..data.maxSkill,"cyan");row:Show()
                elseif i==2 then row:SetRow("zone","Selected zone",data.zoneName);row:Show()
                elseif i==3 then row:SetRow("resource","Eligible types",tostring(data.resourceCount));row:Show()
                elseif i==4 then row:SetRow("route","Route mode",data.routeMode);row:Show()
                elseif i==5 then row:SetRow("selected","Custom selected",tostring(data.selectedResourceCount));row:Show()
                elseif i==6 then row:SetRow("route","Route stops",tostring(data.routeStopCount));row:Show()
                else row:Hide() end
            end
            for _,row in ipairs(card.materialRows) do row:Hide() end
            for _,row in ipairs(card.trainerRows) do row:Hide() end
            card.__gatheringGuideLayout=true
            card.__lastGuideLayoutMode=nil
            layoutDualGatheringCard(card)
            return
        end
    end
    card.gatheringGenerate:Hide()
    if card.gatheringSources then card.gatheringSources:Hide() end
    card.stepLabel:SetText("CURRENT STEP");card.nextLabel:SetText("NEXT ACTION")
    card.readyLabel:SetText("READINESS & WORKSPACE");card.materialLabel:SetText("MATERIAL SNAPSHOT")
    local planner=JLP:GetModule("Planner")
    local consumer,consumerState=nil,nil
    if allowResearchConsumer(p.key) then consumer,consumerState=researchConsumerSnapshot(p.key) end
    local revoked=consumerAuthorityRevoked(consumerState)
    local plan=consumer and consumer.plan or ((not revoked) and planner and planner:GetProfessionPlan(p.key) or nil)
    local dataset=consumer and consumer.dataset or ((not revoked) and planner and planner:GetDataset(p.key) or nil)
    local readOnly,authorityClass=isReadOnlyPlan(plan)
    local displayReadOnly=readOnly
    card.__professionKey=p.key; card.__plan=plan; card.__directMode=nil; card.__consumerSnapshot=consumer; card.__consumerAuthorityState=consumerState
    setResearchPreDispatchControl(card,consumer,plan)
    setResearchCraftAllControl(card,consumer,plan)
    setResearchRouteAutoControl(card,consumer,plan)
    local sequenceBoundary=card.__jlpSequenceBoundary
    local sequenceRestart=card.__jlpSequenceRestart
    local craftAllRestart=card.__jlpCraftAllRestart
    local craftAllResolution=(craftAllRestart and craftAllRestart.restartRequired and craftAllRestart.restartReady~=true) and currentCraftAllResolution(p.key) or nil
    local craftAllHandoff=currentCraftAllHandoff(p.key)
    card.__jlpCraftAllResolution=craftAllResolution
    card.__jlpCraftAllHandoff=craftAllHandoff
    if craftAllHandoff and craftAllHandoff.handoffKind=="MATERIALS" then setActionButtonEnabled(card.craftAll,false) end

    local readiness,queue,assist,flow,machine,workspace,nextBest,routeSession,travelSession,travelTransition,navigationGuidance,routeMarker,destinationHandoff,recovery,transactionRecovery,telemetryStatus,tracking
    local stepModel
    if consumer then
        readiness=consumer.readiness
        queue=consumer.actionQueue
        stepModel=consumer.guideSteps
    else
        readiness,queue,assist,flow,machine,workspace,nextBest,routeSession,travelSession,travelTransition,navigationGuidance,routeMarker,destinationHandoff,recovery,transactionRecovery,telemetryStatus,tracking=bundle(p.key,plan)
        local guideSteps=JLP:GetModule("GuideSteps")
        stepModel=guideSteps and guideSteps:Build(p.key,plan) or nil
    end

    local navigationAdapter=JLP:GetModule("IntegratedNavigationActions")
    local navigationSource,navigationSourceReason=nil,nil
    if navigationAdapter then
        navigationSource,navigationSourceReason=navigationAdapter:GuideSource(p.key,plan,assist and assist.source)
    end
    card.__navigationSource=navigationSource
    card.__navigationSourceReason=navigationSourceReason
    local inventory=JLP:GetModule("Inventory")
    card.__navigationCharacterKey=inventory and inventory.GetCharacterKey and inventory:GetCharacterKey() or nil
    card.__navigationContextToken="CURRENT_STEP:"..tostring(p.key)..":"..tostring(plan and plan.revision or "UNKNOWN")
    local navActions=JLP:GetModule("IntegratedNavigationActions")
    if card.navigateTo and navActions then
        navActions:Update(card.navigateTo,function(source)return navActions:CategoryForSource(source)end,card.__navigationSource,
          {explicit=true,planRevision=plan and plan.revision,contextToken=card.__navigationContextToken,
           characterKey=card.__navigationCharacterKey,sourceIssue=card.__navigationSourceReason})
        card.navigateTo:Show()
    end
    local action=currentAction(queue); local F=JLP.UIContentFormat
    card.__professionState=machine
    card.heading:SetText((p.name or "Profession").." 1-300"); card.profIcon:SetProfession(p.key,p); card.skill:SetText(string.format("Skill: %d / %d",p.skill or 0,p.maxSkill or 300))
    local gatherSummary=JLP:GetModule("GatheringSourceEvidenceSummary")
    if card.gatheringEvidence and gatherSummary then
        card.gatheringEvidence:SetText(p.key=="SKINNING" and gatherSummary:SkinningLabel() or gatherSummary:Label())
    end
    if card.skinningMaterials then card.skinningMaterials:SetShown(p.key=="SKINNING") end
    card:SetFooterEvidenceOwner(p.key=="SKINNING")
    if card.gatheringMap then card.gatheringMap:SetShown(isGatheringProfession(p.key)) end
    if card.gatheringEvidence then card.gatheringEvidence:SetShown(isGatheringProfession(p.key)) end
    if sequenceBoundary then card.badge:SetStatus("SEQUENCE STOP","gold") elseif sequenceRestart and sequenceRestart.restartReady then card.badge:SetStatus(sequenceRestart.contract=="production-auto-route-fresh-click-restart-planner-v1" and "AUTO ROUTE READY" or "BOUNDARY RESOLVED","good") elseif craftAllRestart and craftAllRestart.restartReady then card.badge:SetStatus("INTERRUPTION RESOLVED","good") elseif craftAllHandoff then local label,tone=craftAllHandoffBadge(craftAllHandoff); card.badge:SetStatus(label,tone) elseif craftAllResolution then local label,tone=craftAllResolutionBadge(craftAllResolution); if label then card.badge:SetStatus(label,tone) elseif consumer or displayReadOnly then card.badge:SetStatus(suppressReadOnlyPresentation(p.key,authorityClass) and "CANDIDATE" or "READ-ONLY","gold") elseif revoked then card.badge:SetStatus("AUTHORITY REVOKED","bad") else card.badge:SetStatus(statusLabel(plan,readiness,machine),statusTone(plan,readiness,machine)) end elseif consumer or displayReadOnly then card.badge:SetStatus(suppressReadOnlyPresentation(p.key,authorityClass) and "CANDIDATE" or "READ-ONLY","gold") elseif revoked then card.badge:SetStatus("AUTHORITY REVOKED","bad") else card.badge:SetStatus(statusLabel(plan,readiness,machine),statusTone(plan,readiness,machine)) end
    if consumer then
        setDualDataset(card,p.key,string.format("Build %s · controlled research authority",tostring(consumer.currentBuild or "?")))
    elseif revoked then
        setDualDataset(card,p.key,string.format("Build %s · research authority revoked",tostring(consumerState and consumerState.currentBuild or "?")))
    else
        setDualDataset(card,p.key,string.format("Build %s · %s%s",dataset and dataset.sourceBuild or "?",dataset and dataset.datasetStatus or "unavailable",plan and plan.readOnlyRouteFallback and " · HISTORICAL REFERENCE · non-native" or (displayReadOnly and " · read-only" or "")))
    end
    setReadinessRows(card.readinessRows,readiness,tracking,flow,machine,workspace,nextBest,routeSession,travelSession,travelTransition,navigationGuidance,routeMarker,destinationHandoff,recovery,transactionRecovery,telemetryStatus,p.key)
    if consumer or displayReadOnly or revoked then hideContextCTA(card) else setContextCTA(card,nextBest,p.key,true) end
    card.readiness:SetText(F and F:Readiness(readiness,tracking,flow) or "Readiness unavailable")
    card.nextAction:SetText(sequenceBoundary and tostring(sequenceBoundary.nextActionText or "Resolve the sequence boundary before continuing.") or (sequenceRestartText(sequenceRestart) or (craftAllRestartText(craftAllRestart) or ((craftAllHandoff and tostring(craftAllHandoff.nextActionText or "Craft All settled. Review the next verified action.")) or (craftAllResolutionText(craftAllResolution) or (revoked and revokedAuthorityText(consumerState) or (F and F:Action(action,plan,true) or tostring(action and action.text or "No pending action."))))))))
    card.route:SetText(F and stepModel and F:StepProgressionCompact(stepModel) or "Route unavailable")
    card.workspace:SetText(sequenceBoundary and ("Workspace: sequence stopped · "..tostring(sequenceBoundary.label or "next action required")) or ((sequenceRestart and sequenceRestart.restartReady) and (sequenceRestart.contract=="production-auto-route-fresh-click-restart-planner-v1" and "Workspace: Auto Route interruption resolved · fresh click and fresh session required" or "Workspace: previous sequence boundary resolved · new explicit sequence required") or ((craftAllRestart and craftAllRestart.restartReady) and "Workspace: Craft All interruption resolved · fresh click and fresh ledger required" or (craftAllHandoff and ("Workspace: Craft All settled · "..tostring(craftAllHandoff.handoffKind=="TARGET_REACHED" and "new Planner step ready" or "same recipe needs materials")) or (craftAllResolution and ("Workspace: Craft All restart · "..tostring(craftAllResolution.reason or "revalidation required")) or ((consumer or displayReadOnly) and (suppressReadOnlyPresentation(p.key,authorityClass) and "Workspace: candidate Planner view" or "Workspace: read-only Planner/candidate view") or (revoked and "Workspace: authority revoked; execution remains disabled" or (flow and ("Workspace: "..tostring(flow.nextStationLabel or "Other")) or "Workspace unavailable"))))))))

    if plan and plan.actionKind=="craft" and plan.step then
        card.stepBlock:SetAction(JLP.UIIconResolver:GetRecipe(plan.step.recipe,p.key),plan.step.craftInstruction or ("Craft "..tostring(plan.step.remainingCrafts or "?").." "..tostring(plan.step.recipe or "item")),(plan.step.p1OneCraft and "Manual casts; results observed separately" or string.format("Target: %d     Estimated: %d casts",plan.step.skillTarget or 0,plan.step.remainingCrafts or 0)),nil,nil,plan.step.recipe)
        local fieldReceipt=plan.catalogueFieldReceipt
        local fieldSuffix=fieldReceipt and
            (" | M2 "..tostring(fieldReceipt.state or "UNKNOWN")) or " | M2 UNKNOWN"
        card.stepTitle:SetText(plan.step.craftInstruction or ("Craft "..tostring(plan.step.remainingCrafts or "?").." "..tostring(plan.step.recipe or "item"))); card.meta:SetText((plan.step.p1OneCraft and "Planned casts; recheck after each observed result" or string.format("Target %d | Approx. %d casts remaining",plan.step.skillTarget or 0,plan.step.remainingCrafts or 0))..fieldSuffix..recipeSkillEvidenceLabel(plan))
        local requirements=consumer and consumer.requirementPlan or requirementModel(p.key,plan)
        card.nextBlock:SetAction(JLP.UIIconResolver:GetRecipe(plan.step.recipe,p.key),(consumer or displayReadOnly) and ("Read-only material plan for "..tostring(plan.step.recipe or "current step")) or ("Prepare all materials for "..tostring(plan.step.recipe or "current step")),string.format("%d material type%s in the current step",requirements.materialTypes or 0,(requirements.materialTypes or 0)==1 and "" or "s"),nil,nil,plan.step.recipe)
        card.materialLabel:SetText("MATERIAL SNAPSHOT")
        ensureMaterialRows(card,#(plan.materials or {}),false)
        if consumer or displayReadOnly then
            card.__directMode=nil
            card.targetSlot:SetTarget(nil)
            card.actionFeedback:Hide()
        elseif p.key=="ENCHANTING" then
            card.__directMode="enchant"
            local crafting=JLP:GetModule("Crafting"); local target=crafting and crafting:GetSelectedEnchantTarget(p.key,plan) or nil
            card.targetSlot:SetTarget(target)
            setEnchantActionButton(card,p.key,plan,readiness,target)
            setActionFeedback(card,p.key,plan)
        else
            card.__directMode="craft"
            setCraftActionButtons(card,p.key,plan,readiness)
            setActionFeedback(card,p.key,plan)
        end
        layoutDualCard(card,"craft",requirements,plan.materials or {})
        card.materials:SetText(F and F:Materials(plan.materials,6,true) or "Material data unavailable")
    elseif plan and plan.actionKind=="train" then
        card.__directMode=nil; card.targetSlot:SetTarget(nil); if consumer or displayReadOnly or revoked then card.actionFeedback:Hide() else setActionFeedback(card,p.key,plan) end
        local gate=plan.step and plan.step.trainer; local src=plan.step and plan.step.sourceInfo
        card.stepBlock:SetAction(JLP.UIIconResolver:GetProfession(p.key,p),"Profession rank training",string.format("Current cap: %d     Next cap: %d",p.maxSkill or 0,gate and gate.nextCap or 300),"text")
        card.stepTitle:SetText("Profession rank training"); card.meta:SetText(string.format("Current cap %d | Next cap %d",p.maxSkill or 0,gate and gate.nextCap or 300))
        local nextTitle,nextMeta=actionDisplay(action,plan)
        local trainerMeta=src and ("Trainer: "..tostring(src.name or "Profession trainer")) or ""
        card.nextBlock:SetAction(JLP.UIIconResolver:GetProfession(p.key,p),nextTitle,(nextMeta~="" and (nextMeta.."   ") or "")..trainerMeta)
        for _,w in ipairs(card.materialRows) do w:Hide() end
        card.materialLabel:SetText("TRAINER")
        local name,_,zone,coord=sourceParts(src,p.key,gate)
        card.trainerRows[1]:SetRow("trainer","Trainer",name,"cyan")
        card.trainerRows[2]:SetRow("zone","Zone",zone)
        card.trainerRows[3]:SetRow("coordinates","Coordinates",coord,"cyan")
        layoutDualCard(card,"train",nil,nil)
        card.materials:SetText(F and F:Source(src,true) or tostring(name))
    else
        card.__directMode=nil; card.targetSlot:SetTarget(nil); if consumer or displayReadOnly or revoked then card.actionFeedback:Hide() else setActionFeedback(card,p.key,plan) end
        card.__requirementModel=nil
        local inactiveTitle=revoked and "Research authority revoked" or (plan and plan.action or "No active profession step")
        card.stepBlock:SetAction(JLP.UIIconResolver:GetProfession(p.key,p),inactiveTitle,revoked and "Current-build authority must be revalidated before this route can be consumed again." or "")
        card.stepTitle:SetText(inactiveTitle); card.meta:SetText(recipeSkillEvidenceLabel(plan)); card.nextBlock:SetAction(JLP.UIIconResolver:GetProfession(p.key,p),
            revoked and "Re-establish current-build research authority" or
            (plan and plan.p1Prerequisite and plan.p1Prerequisite.text) or
            (plan and plan.actionKind=="reference" and "Read-only profession reference" or "No pending action"),
            plan and planner:EnsureReferenceSnapshot(plan) and plan.referenceSnapshot.currentSourceBuild and
            ("Client DB2 build "..tostring(plan.referenceSnapshot.currentSourceBuild)..
                " · "..tostring(plan.referenceSnapshot.current and plan.referenceSnapshot.current.recipeCandidates or "?")..
                " recipe candidates; not native approval") or
            (revoked and tostring(consumerState and consumerState.sourceAuthorityState or "") or ""))
        layoutDualCard(card,"other",nil,nil)
    end
end

local function buildDual(parent)
    local L=JLP.UITheme.layout; local f=CreateFrame("Frame",nil,parent); f:SetAllPoints(); local gap=L.cardGap or 14
    local dims=JLP.UILayout:PageGeometry(parent,1078,636); local contentWidth,contentHeight=dims.width,dims.height; local columnWidth=JLP.UILayout:EqualColumns(contentWidth,2,gap)
    local left=buildDualProfessionCard(f,"Profession 1 - 1-300",columnWidth,contentHeight); left:SetPoint("TOPLEFT",0,0)
    local right=buildDualProfessionCard(f,"Profession 2 - 1-300",columnWidth,contentHeight); right:SetPoint("TOPRIGHT",0,0)
    left.__equalSplit="dual"; right.__equalSplit="dual"; f.left=left; f.right=right; f.equalSplit=true; f.sharedPanelTemplate=true
    return f
end

local function layoutSinglePlan(plan,mode,reqModel)
    plan.__lastGuideLayoutMode=mode
    plan.__lastGuideRequirementModel=reqModel
    if plan.LayoutActionToolbar then plan:LayoutActionToolbar() end
    local stepH=plan.stepBlock:Relayout()
    if plan.nextBlock then plan.nextBlock:Relayout() end
    local y=22+stepH+18
    if plan.actionFeedback and plan.actionFeedback.IsShown and plan.actionFeedback:IsShown() then
        plan.actionFeedback:ClearAllPoints(); plan.actionFeedback:SetPoint("TOPLEFT",0,-y); plan.actionFeedback:SetPoint("TOPRIGHT",0,-y); y=y+20
    end
    plan.nextLabel:ClearAllPoints(); plan.nextLabel:SetPoint("TOPLEFT",0,-y); y=y+24
    if mode=="craft" then
        plan.nextBlock:Hide()
        y=layoutRequirementRows(plan,reqModel,y)
    else
        hideRequirementRows(plan)
        plan.nextBlock:Show(); plan.nextBlock:ClearAllPoints(); plan.nextBlock:SetPoint("TOPLEFT",0,-y)
        y=y+plan.nextBlock:GetHeight()+4
    end
    plan.readyLabel:ClearAllPoints(); plan.readyLabel:SetPoint("TOPLEFT",0,-y)
    y=y+GUIDE_SECTION_LINE_HEIGHT+GUIDE_SECTION_GAP
    for _,row in ipairs(plan.readinessRows or {}) do
        if row and row.IsShown and row:IsShown() then
            y=layoutGuideReadinessRow(row,y)
        end
    end
    if plan.contextCTA and plan.contextCTA.IsShown and plan.contextCTA:IsShown() then
        plan.contextCTA:ClearAllPoints(); plan.contextCTA:SetPoint("TOPLEFT",0,-y)
        y=y+32+GUIDE_SECTION_GAP
    end
    plan.upcomingLabel:ClearAllPoints(); plan.upcomingLabel:SetPoint("TOPLEFT",0,-y)
    y=y+GUIDE_SECTION_LINE_HEIGHT+GUIDE_SECTION_GAP
    plan.progression:ClearAllPoints(); plan.progression:SetPoint("TOPLEFT",0,-y); plan.progression:SetPoint("TOPRIGHT",0,-y)
    -- Each displayed Step Progression line gets the same 8-unit free space
    -- as the Readiness rows, without inserting fake empty route steps.
    if plan.progression.SetSpacing then plan.progression:SetSpacing(GUIDE_SECTION_GAP) end
    local progressionHeight=math.max(24,stringHeight(plan.progression,24))
    plan.progression:SetHeight(progressionHeight)
    y=y+progressionHeight+GUIDE_SECTION_GAP
    plan.materialButton:ClearAllPoints(); plan.materialButton:SetPoint("TOPLEFT",0,-y)
    plan.mapButton:ClearAllPoints(); plan.mapButton:SetPoint("LEFT",plan.materialButton,"RIGHT",10,0)
    plan.ahButton:ClearAllPoints(); plan.ahButton:SetPoint("LEFT",plan.mapButton,"RIGHT",10,0)
    local hasActions=shown(plan.materialButton) or shown(plan.mapButton) or shown(plan.ahButton)
    local bottom=y+(hasActions and 32 or 0)
    if plan.navButton then
        -- Avoid putting the navigation hitbox below the scroll child, even
        -- when no other action button is visible.
        local navTop=y+(hasActions and 40 or 8)
        plan.navButton:ClearAllPoints();plan.navButton:SetPoint("TOPLEFT",0,-navTop)
        if shown(plan.navButton) then
            bottom=math.max(bottom,navTop+plan.navButton:GetHeight())
        end
    end
    plan.scroll:SetContentHeight(bottom+GUIDE_SECTION_GAP,true)
end

-- In the single-profession Materials & Sources card a detailed row
-- without a crafted-from dependency contains only title, counts, and the
-- advisory source text. The shared 132-unit row also reserves space for
-- optional dependency fields; do not reserve it if those fields are empty.
local function compactSingleMaterialHeight(widget,material)
    local measured=tonumber(widget and widget.__layoutHeight) or 132
    if material and material.craftedFrom then return measured end
    local hasAdvisory=material and material.availability~=nil
    return math.max(hasAdvisory and 112 or 100,measured-32)
end

local function layoutCraftMaterials(materials,rows)
    local after=0
    for i,row in ipairs(materials.materialRows) do
        if rows[i] then
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-after)
            row:SetMaterial(rows[i]); row:Show()
            local rowHeight=compactSingleMaterialHeight(row,rows[i])
            row:SetHeight(rowHeight); row.__layoutHeight=rowHeight
            after=after+rowHeight+7
        else row:Hide() end
    end
    materials.sourceLabel:ClearAllPoints(); materials.sourceLabel:SetPoint("TOPLEFT",0,-after)
    -- A source receipt can include build, exact ID, access and provenance.
    -- The former fixed 22px row and hard-coded +58 offset clipped its text.
    local sourceTop=after+28
    local sourceHeight=24
    if materials.sourceRow.IsShown and materials.sourceRow:IsShown() then
        local sourceValue=materials.sourceRow.value
        if sourceValue and sourceValue.GetStringHeight then
            local h=tonumber(sourceValue:GetStringHeight())
            if h and h>0 and h<math.huge then sourceHeight=math.max(24,math.min(220,h+8)) end
        end
    end
    materials.sourceRow:ClearAllPoints(); materials.sourceRow:SetPoint("TOPLEFT",0,-sourceTop)
    materials.sourceRow:SetHeight(sourceHeight)
    local bottom=sourceTop+sourceHeight+8
    if materials.qualityNote and materials.qualityNote.IsShown and materials.qualityNote:IsShown() then
        materials.qualityNote:ClearAllPoints()
        materials.qualityNote:SetPoint("TOPLEFT",0,-bottom)
        materials.qualityNote:SetPoint("TOPRIGHT",0,-bottom)
        local measured=materials.qualityNote.GetStringHeight and tonumber(materials.qualityNote:GetStringHeight()) or nil
        local needed=math.max(42,math.min(200,(measured and measured>0 and measured or 68)+10))
        materials.qualityNote:SetHeight(needed)
        bottom=bottom+needed+8
    end
    materials.scroll:SetContentHeight(math.max(1,bottom+8),true)
end

local function buildSingle(parent)
    local W,C,L=JLP.UIWidgets,JLP.UIComponents,JLP.UILayout; local S=JLP.UITheme.layout; local f=CreateFrame("Frame",nil,parent); f:SetAllPoints(); local gap=S.cardGap or 14
    local dims=L:PageGeometry(parent,1078,636);local contentWidth,contentHeight=dims.width,dims.height;local columnWidth=L:EqualColumns(contentWidth,2,gap)
    local progressHeight=190; local lowerHeight=contentHeight-progressHeight-gap
    local progress=W:Card(f,"Profession Progress","primary"); progress:SetPoint("TOPLEFT",0,0); progress:SetPoint("TOPRIGHT",0,0); progress:SetHeight(progressHeight)
    progress.icon=C:Icon(progress,52); progress.icon:SetPoint("TOPLEFT",24,-68)
    progress.name=W:Label(progress,"Profession","GameFontNormalLarge"); progress.name:SetPoint("TOPLEFT",progress.icon,"TOPRIGHT",16,-2)
    progress.skill=W:Label(progress,"0 / 300","GameFontHighlight"); progress.skill:SetPoint("TOPLEFT",progress.name,"BOTTOMLEFT",0,-8); progress.skill:SetTextColor(JLP.UITheme:Color("muted"))
    progress.gatheringMap=W:Button(progress,"Open Gathering Map",177)
    progress.gatheringMap:SetHeight(28);progress.gatheringMap:SetPoint("TOPRIGHT",-24,-73)
    progress.skinningMaterials=W:Button(progress,"Skinning Materials",170)
    progress.skinningMaterials:SetHeight(28)
    progress.skinningMaterials:SetPoint("RIGHT",progress.gatheringMap,"LEFT",-8,0)
    progress.skinningMaterials:SetScript("OnClick",function()
        local browser=JLP:GetModule("SkinningMaterialsBrowser")
        if browser then browser:Open("LEATHER") end
    end)
    progress.skinningMaterials:Hide()
    progress.gatheringEvidence=W:Label(progress,gatheringEvidenceLabel(),"GameFontHighlightSmall")
    progress.gatheringEvidence:SetPoint("TOPRIGHT",progress.gatheringMap,"BOTTOMRIGHT",0,-7)
    progress.gatheringEvidence:SetTextColor(JLP.UITheme:Color("muted"))
    progress.gatheringMap:SetScript("OnClick",function()
        local coordinator=JLP:GetModule("GatheringWindowCoordinator")
        if coordinator then coordinator:Open("GUIDE",Page:GetMode())
        elseif JLP.StandaloneGatheringMap then JLP.StandaloneGatheringMap:Show() end
    end)
    progress.bar=W:Progress(progress); progress.bar:SetPoint("TOPLEFT",progress.icon,"BOTTOMRIGHT",16,-14); progress.bar:SetPoint("TOPRIGHT",-28,-134); progress.bar:SetHeight(18)
    progress.maturity=W:Label(progress,"","GameFontHighlightSmall")
    progress.maturity:SetPoint("BOTTOMLEFT",24,13); progress.maturity:SetPoint("BOTTOMRIGHT",-24,13)
    progress.maturity:SetJustifyH("LEFT")

    local plan=W:Card(f,"Current Plan","primary"); plan:SetPoint("BOTTOMLEFT",0,0); plan:SetSize(columnWidth,lowerHeight)
    plan.badge=W:StatusPill(plan,"BLOCKED","bad",98); plan.badge:SetPoint("TOPRIGHT",-22,-16)
    plan.preDispatch=W:Button(plan,"Shadow Preflight",140); plan.preDispatch:SetHeight(30); plan.preDispatch:SetPoint("RIGHT",plan.badge,"LEFT",-8,0); plan.preDispatch:Hide()
    plan.preDispatch:SetScript("OnClick",function() performResearchPreDispatch(plan) end)
    plan.gatheringGenerate=W:Button(plan,"Generate Gathering Route",205)
    plan.gatheringGenerate:SetHeight(30);plan.gatheringGenerate:SetPoint("RIGHT",plan.badge,"LEFT",-8,0)
    plan.gatheringGenerate:SetScript("OnClick",function()
        local coordinator=JLP:GetModule("GatheringWindowCoordinator")
        if coordinator then coordinator:Open("GUIDE",Page:GetMode()) end
        local map=JLP.StandaloneGatheringMap
        if map then map:GenerateRoute() end
    end)
    plan.gatheringGenerate:Hide()
    plan.routeAuto=W:Button(plan,"Auto Route",106); plan.routeAuto:SetHeight(30); plan.routeAuto:SetPoint("RIGHT",plan.badge,"LEFT",-8,0); plan.routeAuto:Hide()
    plan.routeAuto:SetScript("OnClick",function() performResearchRouteAuto(plan) end)
    plan.craftAll=W:Button(plan,"Craft All",88); plan.craftAll:SetHeight(30); plan.craftAll:SetPoint("RIGHT",plan.routeAuto,"LEFT",-8,0); plan.craftAll:Hide()
    plan.craftOne=W:Button(plan,"Craft One",88); plan.craftOne:SetHeight(30); plan.craftOne:SetPoint("RIGHT",plan.craftAll,"LEFT",-8,0); plan.craftOne:Hide()
    addCraftXControl(plan,plan)
    plan.craftXInput:SetPoint("TOPLEFT",22,-104)
    plan.craftX:SetPoint("LEFT",plan.craftXInput,"RIGHT",8,0)
    plan.targetSlot=C:EnchantTargetSlot(plan,30); plan.targetSlot:SetPoint("RIGHT",plan.badge,"LEFT",-8,0); plan.targetSlot:Hide()
    plan.enchant=W:Button(plan,"Enchant",88); plan.enchant:SetHeight(30); plan.enchant:SetPoint("RIGHT",plan.targetSlot,"LEFT",-8,0); plan.enchant:Hide()
    plan.craftOne:SetScript("OnClick",function() if plan.__plan then performCraft(plan.__professionKey,plan.__plan,"one") end end)
    plan.craftAll:SetScript("OnClick",function() if plan.__researchCraftAll then performResearchCraftAll(plan) elseif plan.__plan then performCraft(plan.__professionKey,plan.__plan,"all") end end)
    plan.enchant:SetScript("OnClick",function() if plan.__plan then performEnchant(plan.__professionKey,plan.__plan,plan) end end)
    plan.targetSlot:SetPickerHandler(function(self) if plan.__plan then openTargetPicker(self,plan.__professionKey,plan.__plan) end end)
    -- Action controls share the card header row with the status badge.
    -- Priority from right to left: Craft All / Craft One or Enchant target /
    -- Enchant. A secondary row is reserved only if the actual card is narrow.
    plan.scroll=L:CardScrollArea(plan,{cardWidth=columnWidth,cardHeight=lowerHeight,top=66})
    function plan:LayoutActionToolbar()
        local controls
        if self.enchant.IsShown and self.enchant:IsShown() then
            controls={self.targetSlot,self.enchant,self.routeAuto,self.preDispatch,
                self.gatheringGenerate,self.craftX,self.craftXInput}
        else
            controls={self.craftAll,self.craftOne,self.routeAuto,self.preDispatch,
                self.gatheringGenerate,self.craftX,self.craftXInput}
        end
        local shown={}
        local total=0
        for _,control in ipairs(controls) do
            if control and control.IsShown and control:IsShown() then
                shown[#shown+1]=control
                total=total+math.max(30,tonumber(control:GetWidth()) or 88)+8
            end
        end
        local cardWidth=tonumber(self:GetWidth()) or columnWidth
        local badgeWidth=tonumber(self.badge:GetWidth()) or 98
        local available=cardWidth-44-badgeWidth-8-166
        local secondRow=total>available
        if self.SetHeadingRightInset then
            -- The title and actions are siblings with non-overlapping bounds.
            self:SetHeadingRightInset(secondRow and (badgeWidth+46) or
                (badgeWidth+total+32))
        end
        local previous=self.badge
        local rowCount=1
        local rowWidth=0
        if secondRow then previous=nil end
        for _,control in ipairs(shown) do
            local width=math.max(30,tonumber(control:GetWidth()) or 88)
            if secondRow and rowWidth>0 and rowWidth+width+8>cardWidth-44 then
                rowCount=rowCount+1
                rowWidth=0
                previous=nil
            end
            control:ClearAllPoints()
            if previous then
                control:SetPoint("RIGHT",previous,"LEFT",-8,0)
            else
                control:SetPoint("TOPRIGHT",self,"TOPRIGHT",-22,-59-(rowCount-1)*36)
            end
            previous=control
            rowWidth=rowWidth+width+8
        end
        -- The content viewport starts immediately below the heading divider
        -- in the normal layout and below each compact fallback row otherwise.
        local inset=secondRow and (106+(rowCount-1)*36) or 66
        if self.__toolbarTop~=inset then
            self.__toolbarTop=inset
            self.scroll.__cardContentTop=inset
            self.scroll:ClearAllPoints()
            self.scroll:SetPoint("TOPLEFT",self,"TOPLEFT",22,-inset)
            self.scroll:ApplyCardBounds(cardWidth,self:GetHeight())
        end
        self.__toolbarBottom=secondRow and (91+(rowCount-1)*36) or 46
    end
    local pc=plan.scroll.content
    plan.actionFeedback=W:Label(pc,"","GameFontHighlightSmall"); plan.actionFeedback:SetHeight(16); plan.actionFeedback:Hide(); installCraftFeedbackClock(plan)
    plan.stepLabel=C:SectionTitle(pc,"CURRENT STEP"); plan.stepLabel:SetPoint("TOPLEFT",0,0)
    plan.stepBlock=C:ActionBlock(pc,plan.scroll.__contentWidth,true); plan.stepBlock:SetPoint("TOPLEFT",0,-22)
    plan.stepTitle=W:Label(pc,"","GameFontNormalLarge"); plan.stepTitle:Hide(); plan.meta=W:Label(pc,"","GameFontHighlight"); plan.meta:Hide()
    plan.rule2=W:SectionRule(pc); plan.rule2:SetPoint("TOPLEFT",0,-82); plan.rule2:SetPoint("TOPRIGHT",0,-82)
    plan.nextLabel=C:SectionTitle(pc,"NEXT ACTION"); plan.nextLabel:SetPoint("TOPLEFT",0,-94)
    plan.nextBlock=C:ActionBlock(pc,plan.scroll.__contentWidth,true); plan.nextBlock:SetPoint("TOPLEFT",0,-116)
    plan.requirementRows={}
    plan.nextAction=W:Body(pc); plan.nextAction:Hide()
    plan.readyLabel=C:SectionTitle(pc,"READINESS & WORKSPACE"); plan.readyLabel:SetPoint("TOPLEFT",0,-180)
    plan.readinessRows={}; for i=1,17 do plan.readinessRows[i]=C:KeyValueRow(pc,plan.scroll.__contentWidth); plan.readinessRows[i]:SetPoint("TOPLEFT",0,-204-((i-1)*22)) end
    plan.readiness=W:Body(pc); plan.readiness:Hide()
    plan.contextCTA=W:Button(pc,"Next Action",176); plan.contextCTA:SetHeight(32); plan.contextCTA:Hide()
    plan.contextCTA:SetScript("OnClick",function() performContextCTA(plan) end)
    plan.upcomingLabel=C:SectionTitle(pc,"STEP PROGRESSION"); plan.upcomingLabel:SetPoint("TOPLEFT",0,-294)
    plan.progression=W:Body(pc); plan.progression:SetPoint("TOPLEFT",0,-316); plan.progression:SetPoint("TOPRIGHT",0,-316); plan.progression:SetHeight(24); plan.progression:SetTextColor(JLP.UITheme:Color("muted"))
    plan.upcoming=W:Body(pc); plan.upcoming:Hide()
    plan.materialButton=W:Button(pc,"Material Plan",145); plan.materialButton:SetHeight(32); plan.materialButton:Hide()
    plan.materialButton:SetScript("OnClick",function() local a=JLP:GetModule("AcquisitionPlanner"); if a then a:SetSelectedScope("current") end; if JLP.MainWindow then JLP.MainWindow:Create():Show(); JLP.MainWindow:ShowPage("Auction House") end end)
    plan.mapButton=W:Button(pc,"Show Source",145); plan.mapButton:SetHeight(32); plan.mapButton:Hide()
    plan.mapButton:SetScript("OnClick",function() local a=JLP:GetModule("ActionAssist"); if a and Page.currentAssist then local _,m=a:ShowSource(Page.currentAssist); JLP:Print(m) end end)
    plan.navButton=W:Button(pc,"Navigate To · UNKNOWN",145);plan.navButton:SetHeight(28)
    local actions=JLP:GetModule("IntegratedNavigationActions")
    if actions then actions:Bind(plan.navButton,function(source)return actions:CategoryForSource(source)end,function()
        return Page.currentNavigationSource
    end,function()return {explicit=true,owner="GUIDE_USER_CLICK",
         planRevision=Page.currentNavigationPlanRevision,
         contextToken=Page.currentNavigationContextToken,
         characterKey=Page.currentNavigationCharacterKey,
         sourceIssue=Page.currentNavigationSourceReason}end) end
    plan.ahButton=W:Button(pc,"AH Guidance",145); plan.ahButton:SetHeight(32); plan.ahButton:Hide()
    plan.ahButton:SetScript("OnClick",function() local a=JLP:GetModule("ActionAssist"); if a and Page.currentAssist then local _,m=a:OpenAHGuidance(Page.currentAssist); JLP:Print(m) end end)

    local materials=W:Card(f,"Materials & Sources","primary"); materials:SetPoint("BOTTOMRIGHT",0,0); materials:SetSize(columnWidth,lowerHeight)
    materials.scroll=L:CardScrollArea(materials,{cardWidth=columnWidth,cardHeight=lowerHeight})
    local mc=materials.scroll.content
    materials.qualityNote=W:Label(mc,"","GameFontHighlightSmall")
    materials.qualityNote:SetTextColor(JLP.UITheme:Color("muted"))
    materials.qualityNote:Hide()
    materials.materialRows={}
    materials.sourceLabel=C:SectionTitle(mc,"RECIPE SOURCE")
    materials.sourceRow=C:KeyValueRow(mc,materials.scroll.__contentWidth)
    -- Keep the shared KeyValueRow component intact; only the potentially
    -- multiline Materials & Sources receipt needs top alignment and wrapping.
    if materials.sourceRow.value then
        if materials.sourceRow.value.ClearAllPoints then
            materials.sourceRow.value:ClearAllPoints()
            materials.sourceRow.value:SetPoint("TOPLEFT",materials.sourceRow.label,"TOPRIGHT",5,0)
            materials.sourceRow.value:SetPoint("TOPRIGHT",materials.sourceRow,"TOPRIGHT",-2,0)
        end
        if materials.sourceRow.value.SetWordWrap then
            materials.sourceRow.value:SetWordWrap(true)
        end
    end
    materials.trainerLabel=C:SectionTitle(mc,"TRAINER DETAILS"); materials.trainerLabel:SetPoint("TOPLEFT",0,0); materials.trainerLabel:Hide()
    materials.trainerRows={}; for i=1,4 do materials.trainerRows[i]=C:KeyValueRow(mc,materials.scroll.__contentWidth); materials.trainerRows[i]:SetPoint("TOPLEFT",0,-30-((i-1)*30)); materials.trainerRows[i]:Hide() end
    materials.processLabel=C:SectionTitle(mc,"PROCESS"); materials.processLabel:SetPoint("TOPLEFT",0,-172); materials.processLabel:Hide()
    materials.process1=C:TextBlock(mc,materials.scroll.__contentWidth,68); materials.process1:SetPoint("TOPLEFT",0,-202); materials.process1:Hide()
    materials.process2=C:TextBlock(mc,materials.scroll.__contentWidth,68); materials.process2:SetPoint("TOPLEFT",0,-276); materials.process2:Hide()

    plan.scroll:SetContentHeight(380)
    materials.scroll:SetContentHeight(360)
    plan.__equalSplit="single-lower"; materials.__equalSplit="single-lower"; plan.__layoutWidth=columnWidth; materials.__layoutWidth=columnWidth; plan.__layoutHeight=lowerHeight; materials.__layoutHeight=lowerHeight
    f.progress=progress; f.plan=plan; f.materials=materials; f.equalLowerSplit=true
    return f
end

-- Guide uses a single outer scroll viewport in narrow modes.  The individual
-- card scrollers remain independent; the outer scrollbar is the input
-- alternative when inner cards consume wheel movement.
function Page:Create(parent)
    if self.frame then return self.frame end
    local f=CreateFrame("Frame",nil,parent); f:SetAllPoints()
    local viewport=CreateFrame("ScrollFrame",nil,f); viewport:SetAllPoints()
    local content=CreateFrame("Frame",nil,viewport); content:SetSize(1078,636)
    if viewport.SetScrollChild then viewport:SetScrollChild(content) end
    f.guideViewport=viewport; f.guideContent=content
    f.dual=buildDual(content); f.single=buildSingle(content)
    local warning=JLP.UIWidgets:Label(f,"Guide requires at least 740 x 430 logical UI units. Reduce UI scale or enlarge the window.","GameFontHighlight")
    warning:SetPoint("CENTER",f,"CENTER",0,0)
    warning:SetWidth(540); warning:Hide(); f.layoutWarning=warning
    f.outerScrollbar=JLP.UILayout:AttachNativeScrollbar(viewport,
        {owner=f,right=-2,top=-2,bottom=2})
    function f:ScrollPage(delta)
        self.scrollOffset=math.max(0,math.min(self.scrollMaximum or 0,(self.scrollOffset or 0)+(tonumber(delta) or 0)))
        if self.guideViewport.SetVerticalScroll then self.guideViewport:SetVerticalScroll(self.scrollOffset) end
        return self.scrollOffset
    end
    -- Inner cards have priority for wheel events. When an inner scroller has
    -- reached its limit, the unused movement continues on the outer Guide.
    local function outerWheelHandoff(pixels)
        local old=f.scrollOffset or 0
        f:ScrollPage(pixels)
        return (f.scrollOffset or 0)-old
    end
    for _,area in ipairs({f.dual.left.scroll,f.dual.right.scroll,f.single.plan.scroll,f.single.materials.scroll}) do
        area:SetWheelHandoff(outerWheelHandoff)
    end
    f.__guideWheelHandoff=outerWheelHandoff
    if viewport.EnableMouseWheel then viewport:EnableMouseWheel(true) end
    viewport:SetScript("OnMouseWheel",function(_,delta) f:ScrollPage(-(tonumber(delta) or 0)*70) end)
    self.frame=f
    self:SetMode((JLP.DB and JLP.DB.profile and JLP.DB.profile.guideMode) or "dual")
    return f
end

function Page:ApplyGuideLayout()
    local f=self.frame
    if not f then return nil end
    local dims=JLP.UILayout:PageGeometry(f,1078,636)
    local plan=JLP.UILayout:GuideResponsivePlan(dims.width,dims.height,self.mode=="dual" and "dual" or "single")
    local scale=f.GetEffectiveScale and tonumber(f:GetEffectiveScale()) or 1
    if not scale or scale~=scale or scale<=0 or scale==math.huge then scale=1 end
    local signature=table.concat({plan.state,self.mode,math.floor(dims.width),
        math.floor(dims.height),math.floor(scale*1000+0.5)},":")
    if f.guideLayoutSignature==signature then return plan end
    local modeChanged=f.guideLayoutMode~=self.mode
    f.guideLayoutSignature=signature
    f.guideLayoutMode=self.mode
    f.responsivePlan=plan
    local usable=plan.interactiveControlsFit
    f.guideViewport:SetShown(usable)
    f.layoutWarning:SetShown(not usable)
    if f.outerScrollbar then f.outerScrollbar:Refresh() end
    if not usable then f.scrollMaximum=0; f:ScrollPage(0); return plan end
    local gap=plan.gap
    f.guideContent:SetSize(plan.contentWidth,plan.contentHeight)
    local dual=f.dual
    local left,right=dual.left,dual.right
    left:ClearAllPoints();right:ClearAllPoints()
    left:SetSize(plan.cardWidth,plan.dualCardHeight)
    right:SetSize(plan.cardWidth,plan.dualCardHeight)
    left.scroll:ApplyCardBounds(plan.cardWidth,plan.dualCardHeight)
    right.scroll:ApplyCardBounds(plan.cardWidth,plan.dualCardHeight)
    -- Reflow text-based children when the parent card changes width.
    -- Layout signatures ensure this is not called on every refresh tick.
    for _,card in ipairs({left,right}) do
        local cw=card.scroll.__contentWidth or (plan.cardWidth-50)
        if card.gatheringSources then
            card.gatheringSources:SetWidth(cw)
            if card.gatheringSources.IsShown and card.gatheringSources:IsShown() then
                card.gatheringSources:SetHeight(16000)
                local sh=card.gatheringSources.GetStringHeight and card.gatheringSources:GetStringHeight() or 24
                sh=math.max(24,math.min(16000,tonumber(sh) or 24))
                card.gatheringSources:SetHeight(sh+4)
                local top=card.__gatherSourcesTop or 543
                card.scroll:SetContentHeight(top+sh+28,true)
            end
        end
        for _,row in ipairs(card.readinessRows or {}) do
            if row.SetWidth then row:SetWidth(cw) end
        end
        -- Resize the *existing* action components before rebuilding their
        -- vertical anchors/content height. This also works if ApplyGuideLayout
        -- is invoked without immediately recreating the profession view.
        for _,block in ipairs({card.stepBlock,card.nextBlock}) do
            if block and block.SetWidth then block:SetWidth(cw) end
            if block and block.Relayout then block:Relayout() end
        end
        if card.__gatheringGuideLayout then
            layoutDualGatheringCard(card)
        elseif card.__lastGuideLayoutMode then
            layoutDualCard(card,card.__lastGuideLayoutMode,
                card.__lastGuideRequirementModel,card.__lastGuideMaterialRows)
        end
    end
    left:SetPoint("TOPLEFT",dual,"TOPLEFT",0,0)
    if plan.stacked then
        right:SetPoint("TOPLEFT",dual,"TOPLEFT",0,-plan.dualCardHeight-gap)
    else
        right:SetPoint("TOPRIGHT",dual,"TOPRIGHT",0,0)
    end
    local single=f.single
    single.progress:SetHeight(plan.progressHeight)
    single.plan:ClearAllPoints();single.materials:ClearAllPoints()
    single.plan:SetSize(plan.cardWidth,plan.planHeight)
    single.materials:SetSize(plan.cardWidth,plan.materialsHeight)
    single.plan.scroll:ApplyCardBounds(plan.cardWidth,plan.planHeight)
    local pcw=single.plan.scroll.__contentWidth or (plan.cardWidth-50)
    for _,block in ipairs({single.plan.stepBlock,single.plan.nextBlock}) do
        if block and block.SetWidth then block:SetWidth(pcw) end
        if block and block.Relayout then block:Relayout() end
    end
    for _,row in ipairs(single.plan.readinessRows or {}) do
        if row.SetWidth then row:SetWidth(pcw) end
    end
    if single.plan.__lastGuideLayoutMode then
        layoutSinglePlan(single.plan,single.plan.__lastGuideLayoutMode,
            single.plan.__lastGuideRequirementModel)
    end
    if single.plan.LayoutActionToolbar then single.plan:LayoutActionToolbar() end
    single.materials.scroll:ApplyCardBounds(plan.cardWidth,plan.materialsHeight)
    if plan.stacked then
        single.plan:SetPoint("TOPLEFT",single,"TOPLEFT",0,-plan.progressHeight-gap)
        single.materials:SetPoint("TOPLEFT",single,"TOPLEFT",0,-plan.progressHeight-gap-plan.planHeight-gap)
    else
        single.plan:SetPoint("BOTTOMLEFT",single,"BOTTOMLEFT",0,0)
        single.materials:SetPoint("BOTTOMRIGHT",single,"BOTTOMRIGHT",0,0)
    end
    f.scrollMaximum=math.max(0,plan.contentHeight-dims.height)
    if modeChanged then f.scrollOffset=0 end
    f:ScrollPage(0)
    return plan
end

function Page:SetMode(mode)
    local ws=workspace()
    local resolved=ws and select(1,ws:ResolveGuideMode(mode)) or "onboarding"
    self.mode=resolved
    -- An explicit primary Guide choice takes Current Step focus back from
    -- First Aid. Browsing the secondary preview does not change this intent.
    if JLP.DB and JLP.DB.profile and (resolved=="dual" or ws and ws.HasLearned and ws:HasLearned(resolved)) then
        JLP.DB.profile.activeSecondaryCurrentStep=nil
    end
    if JLP.DB and JLP.DB.profile then JLP.DB.profile.guideMode=resolved end
    local gathering=JLP:GetModule("GatheringSharedMapState")
    if gathering and gathering.ObserveSupplyProfessionFocus then gathering:ObserveSupplyProfessionFocus(resolved) end
    if self.frame then
        self.frame.dual:SetShown(resolved=="dual")
        self.frame.single:SetShown(resolved~="dual")
        -- Reset outer scrolling even if a new profession resolves to the
        -- same Guide mode; inner card scroll remains managed by its content.
        self.frame.scrollOffset=0
        self.frame:ScrollPage(0)
        self.frame.guideLayoutSignature=nil
        self:Refresh()
    end
end
function Page:GetEnchantTargetUIDiagnostics()
    local single=self.frame and self.frame.single and self.frame.single.plan and self.frame.single.plan.targetSlot
    local dual=self.frame and self.frame.dual and self.frame.dual.right and self.frame.dual.right.targetSlot
    local function part(label,slot)
        if not slot then return label.."=missing" end
        local surface=slot.hit or slot
        local mouse="?"
        if surface.IsMouseEnabled then
            local ok,value=pcall(surface.IsMouseEnabled,surface)
            if ok then mouse=value and "on" or "off" end
        elseif surface.mouseEnabled~=nil then mouse=surface.mouseEnabled and "on" or "off" end
        local shown="?"
        if surface.IsShown then
            local ok,value=pcall(surface.IsShown,surface)
            if ok then shown=value and "yes" or "no" end
        elseif surface.shown~=nil then shown=surface.shown and "yes" or "no" end
        local strata="?"
        if surface.GetFrameStrata then
            local ok,value=pcall(surface.GetFrameStrata,surface)
            if ok and value then strata=tostring(value) end
        end
        local level="?"
        if surface.GetFrameLevel then
            local ok,value=pcall(surface.GetFrameLevel,surface)
            if ok and value~=nil then level=tostring(value) end
        end
        local inputMouse="n/a"
        local input=slot.nativeSlot and slot.nativeSlot.Button and slot.nativeSlot.Button.InputOverlay or nil
        if input and input.IsMouseEnabled then
            local ok,value=pcall(input.IsMouseEnabled,input)
            if ok then inputMouse=value and "on" or "off" end
        elseif input and input.mouseEnabled~=nil then inputMouse=input.mouseEnabled and "on" or "off" end
        local clickEnabled="?"
        if surface.IsMouseClickEnabled then
            local ok,value=pcall(surface.IsMouseClickEnabled,surface)
            if ok then clickEnabled=value and "on" or "off" end
        end
        local motionEnabled="?"
        if surface.IsMouseMotionEnabled then
            local ok,value=pcall(surface.IsMouseMotionEnabled,surface)
            if ok then motionEnabled=value and "on" or "off" end
        end
        local visible="?"
        if surface.IsVisible then
            local ok,value=pcall(surface.IsVisible,surface)
            if ok then visible=value and "yes" or "no" end
        end
        local flyoutState="none"
        local flyout=slot.__jlpLastNativeFlyout
        if flyout then
            local flyShown="?"
            if flyout.IsShown then
                local ok,value=pcall(flyout.IsShown,flyout)
                if ok then flyShown=value and "yes" or "no" end
            elseif flyout.shown~=nil then flyShown=flyout.shown and "yes" or "no" end
            local flyVisible="?"
            if flyout.IsVisible then
                local ok,value=pcall(flyout.IsVisible,flyout)
                if ok then flyVisible=value and "yes" or "no" end
            end
            local flyStrata="?"
            if flyout.GetFrameStrata then
                local ok,value=pcall(flyout.GetFrameStrata,flyout)
                if ok and value then flyStrata=tostring(value) end
            end
            local flyLevel="?"
            if flyout.GetFrameLevel then
                local ok,value=pcall(flyout.GetFrameLevel,flyout)
                if ok and value~=nil then flyLevel=tostring(value) end
            end
            flyoutState=string.format("%s/%s/%s/%s",flyShown,flyVisible,flyStrata,flyLevel)
        end
        local addIconState="n/a"
        local addIcon=input and input.AddIcon or nil
        if addIcon and addIcon.IsShown then
            local ok,value=pcall(addIcon.IsShown,addIcon)
            if ok then addIconState=value and "yes" or "no" end
        elseif addIcon and addIcon.shown~=nil then addIconState=addIcon.shown and "yes" or "no" end
        return string.format("%s(native=%s selector=custom visual=single input=self txsync=none mouse=%s click=%s motion=%s shown=%s visible=%s strata=%s level=%s enter=%d leave=%d show=%d hide=%d anchor=%d set=%d down=%d open=%d customOpen=%d itemClick=%d selectedCount=%d paint=%d selected=%s)",label,slot.__nativeEnchantSlot and "yes" or "no",mouse,clickEnabled,motionEnabled,shown,visible,strata,level,tonumber(slot.__jlpEnterCount) or 0,tonumber(slot.__jlpLeaveCount) or 0,tonumber(slot.__jlpShowCount) or 0,tonumber(slot.__jlpHideCount) or 0,tonumber(slot.__jlpAnchorCount) or 0,tonumber(slot.__jlpSetTargetCount) or 0,tonumber(slot.__jlpMouseDownCount) or 0,tonumber(slot.__jlpOpenCount) or 0,tonumber(slot.__jlpCustomPickerCount) or 0,tonumber(slot.__jlpCustomItemClickCount) or 0,tonumber(slot.__jlpCustomSelectionCount) or 0,tonumber(slot.__jlpManualVisualCount) or 0,slot.__target and "yes" or "no")
    end
    return string.format("pickerCalls=%d pageRefresh=%d %s %s",tonumber(self.__targetPickerOpenCalls) or 0,tonumber(self.__refreshCount) or 0,part("single",single),part("dual",dual))
end

function Page:GetMode() return self.mode or "onboarding" end

local hideReferencePreview
local function renderOnboarding(single,mode,pair)
    local learned=#(pair or {})
    local title=mode=="learn-second" and "Learn a second primary profession" or "Learn a primary profession"
    local body=mode=="learn-second" and "Your first primary profession is detected. Learn a second primary profession to unlock Dual Mode." or "No primary profession is currently detected. Learn a primary profession to begin profession planning."
    single.progress.icon:SetResolved(JLP.UIIconResolver:GetFallback())
    if single.progress.icon.ClearInteraction then single.progress.icon:ClearInteraction() end
    single.progress.heading:SetText("Profession onboarding")
    if single.progress.maturity then single.progress.maturity:SetText("") end
    single.progress.name:SetText(title)
    single.progress.skill:SetText(learned==0 and "Primary slots: 0 / 2" or "Primary slots: 1 / 2")
    single.progress.bar:SetSkill(learned,2)
    local card=single.plan
    card.__professionKey=nil; card.__plan=nil; card.__consumerSnapshot=nil; card.__consumerAuthorityState=nil
    if card.gatheringGenerate then card.gatheringGenerate:Hide() end
    card.stepLabel:SetText("CURRENT STEP");card.readyLabel:SetText("READINESS & WORKSPACE")
    card.upcomingLabel:SetText("STEP PROGRESSION")
    setDirectControls(card,nil); stableSetShown(card.preDispatch,false); stableSetShown(card.routeAuto,false)
    card.targetSlot:SetTarget(nil); card.actionFeedback:Hide(); hideContextCTA(card)
    card.mapButton:Hide(); card.ahButton:Hide(); card.materialButton:Hide()
    card.badge:SetStatus("ONBOARDING","gold")
    card.stepBlock:SetAction(JLP.UIIconResolver:GetFallback(),title,body)
    card.stepTitle:SetText(title); card.nextBlock:SetAction(JLP.UIIconResolver:GetFallback(),"Visit a profession trainer",body)
    hideRequirementRows(card)
    for i,row in ipairs(card.readinessRows or {}) do
        if i==1 then row:SetRow("profession","Learned primary professions",tostring(learned).." / 2",learned>0 and "good" or "warn"); row:Show()
        elseif i==2 then row:SetRow("identity","Profession identity","Stable IDs only","good"); row:Show()
        elseif i==3 then row:SetRow("execution","Native execution","Unavailable until a learned production profession is selected","muted"); row:Show()
        else row:Hide() end
    end
    card.readiness:SetText(body); card.progression:SetText("The guide will populate automatically from the professions actually learned by this character."); card.upcoming:SetText(card.progression:GetText() or "")
    card.__requirementModel=nil
    local m=single.materials
    hideReferencePreview(m)
    for _,w in ipairs(m.materialRows or {}) do w:Hide() end
    for _,r in ipairs(m.trainerRows or {}) do r:Hide() end
    m.trainerLabel:Hide(); m.processLabel:Hide(); m.process1:Hide(); m.process2:Hide()
    m.sourceLabel:Show(); m.sourceRow:Show(); m.sourceLabel:SetText("WORKSPACE")
    m.sourceRow:SetRow("profession","Detected primary slots",learned==0 and "Both slots are open" or "One slot is open","cyan")
    m.scroll:SetContentHeight(64,true)
    layoutSinglePlan(card,"other",nil)
end

-- Alpha139: the only Guide consumer of reference-route acquisition.
-- Separate from production plan/material rows; does not create craft controls.
hideReferencePreview = function(holder)
    local ui=holder and holder.__foreverReferenceUI
    if not ui then return end
    ui.title:Hide(); ui.notice:Hide(); ui.strategy:Hide(); ui.coverage:Hide()
    if ui.access then ui.access:Hide() end
    if ui.hordeResearch then ui.hordeResearch:Hide() end
    if ui.bandNext then ui.bandNext:Hide();ui.bandReset:Hide() end
    if ui.bandPrevious then ui.bandPrevious:Hide() end
    if ui.bandFirst then ui.bandFirst:Hide() end
    if ui.bandLast then ui.bandLast:Hide() end
    if ui.bandSelection then ui.bandSelection:Hide() end
    if ui.back then ui.back:Hide() end
    if ui.prev then ui.prev:Hide();ui.next:Hide();ui.page:Hide() end
    for _,row in ipairs(ui.materialRows) do row:Hide() end
    for _,row in ipairs(ui.sourceRows) do row:Hide() end
    for _,button in ipairs(ui.evidenceButtons or {}) do button:Hide() end
    if ui.evidenceSheet and ui.evidenceSheet.Reset then ui.evidenceSheet:Reset() end
    -- A changed profession/skill can hide this card before the next render.
    -- A formerly valid click receipt must not remain a navigable source.
    holder.__referenceMaterialReceipt=nil
    holder.__referenceMaterialKey=nil
    holder.__referenceOwnerSignature=nil
    holder.__referenceMaterialPage=1
end
-- A manual source-band transition is a NEW source/material context. Drop
-- currently selectable receipt/SourceSheet before any redraw or callback, so
-- a delayed Bank/AH click cannot target the previous recipe's item ID.
-- The planner remains authoritative; this is transient read-only UI state.
local function completeQualifiedBandSelection(holder,key,ok,reason,priorSkill)
    if ok then
        Page.referenceBandFeedback=nil
        holder.__referenceMaterialPage=1
        holder.__referenceMaterialReceipt=nil
        holder.__referenceMaterialKey=nil
        local ui=holder.__foreverReferenceUI
        if ui and ui.evidenceSheet and ui.evidenceSheet.Reset then
            ui.evidenceSheet:Reset()
        end
    else
        Page.referenceBandFeedback={key=key,skill=priorSkill,reason=reason}
    end
    Page:Refresh()
    return ok,reason
end
local function ensureReferencePreview(holder)
    if holder.__foreverReferenceUI then return holder.__foreverReferenceUI end
    local W,C=JLP.UIWidgets,JLP.UIComponents
    local c=holder.scroll.content
    local width=holder.scroll.__contentWidth
    local ui={materialRows={},sourceRows={},evidenceButtons={}}
    ui.title=C:SectionTitle(c,"FOREVER ROUTE · ADVISORY")
    ui.strategy=W:Button(c,"Normal route",128); ui.strategy:SetHeight(27)
    ui.bandNext=W:Button(c,"Next sourced band",142);ui.bandNext:SetHeight(25)
    ui.bandFirst=W:Button(c,"First sourced band",142);ui.bandFirst:SetHeight(25)
    ui.bandLast=W:Button(c,"Last sourced band",142);ui.bandLast:SetHeight(25)
    ui.bandPrevious=W:Button(c,"Previous sourced band",165);ui.bandPrevious:SetHeight(25)
    ui.bandReset=W:Button(c,"Current skill",125);ui.bandReset:SetHeight(25)
    ui.hordeResearch=W:Button(c,"Horde strategy / materials",205)
    ui.hordeResearch:SetHeight(26)
    ui.hordeResearch:SetScript("OnClick",function()
        Page:OpenHordeResearchPanel(holder.__referenceProfessionKey,Page.referenceStrategy,
            holder.__referenceDisplayedSkill)
    end)
    ui.bandSelection=W:Label(c,"","GameFontHighlightSmall")
    ui.bandSelection:SetWidth(math.max(180,width-10));ui.bandSelection:SetHeight(34)
    if ui.bandSelection.SetWordWrap then ui.bandSelection:SetWordWrap(true) end
    ui.bandNext:SetScript("OnClick",function()
        local key=holder.__referenceProfessionKey
        local selected=holder.__referenceDisplayedSkill
        local ok,reason=Page:SelectNextQualifiedBand(key,selected,Page.referenceStrategy)
        completeQualifiedBandSelection(holder,key,ok,reason,selected)
    end)
    ui.bandFirst:SetScript("OnClick",function()
        local key=holder.__referenceProfessionKey
        local ok,reason=Page:SelectFirstQualifiedBand(key,Page.referenceStrategy)
        completeQualifiedBandSelection(holder,key,ok,reason,holder.__referenceDisplayedSkill)
    end)
    ui.bandLast:SetScript("OnClick",function()
        local key=holder.__referenceProfessionKey
        local ok,reason=Page:SelectLastQualifiedBand(key,Page.referenceStrategy)
        completeQualifiedBandSelection(holder,key,ok,reason,holder.__referenceDisplayedSkill)
    end)
    ui.bandPrevious:SetScript("OnClick",function()
        local key=holder.__referenceProfessionKey
        local selected=holder.__referenceDisplayedSkill
        local ok,reason=Page:SelectPreviousQualifiedBand(key,selected,Page.referenceStrategy)
        completeQualifiedBandSelection(holder,key,ok,reason,selected)
    end)
    ui.bandReset:SetScript("OnClick",function()
        local key=holder.__referenceProfessionKey
        local ok,reason=Page:ResetQualifiedBand(key)
        completeQualifiedBandSelection(holder,key,ok,reason,holder.__referenceDisplayedSkill)
    end)
    ui.back=W:Button(c,"Back to reference overview",184);ui.back:SetHeight(26)
    ui.back:SetScript("OnClick",function()
        -- Preserve profession/strategy, drop only the current material page.
        holder.__referenceMaterialPage=1
        holder.__referenceMaterialReceipt=nil
        if ui.evidenceSheet and ui.evidenceSheet.Reset then ui.evidenceSheet:Reset() end
        Page:Refresh()
        -- Refresh preserves the existing scroll by design. The explicit Back
        -- command targets the reference overview, including dual Guide cards.
        local layout=JLP.UILayout
        if layout and type(layout.ReturnToScrollOrigin)=="function" then
            layout:ReturnToScrollOrigin(holder.scroll)
        elseif holder.scroll and holder.scroll.ScrollTo then holder.scroll:ScrollTo(0) end
        if Page.frame and Page.frame.ScrollPage then Page.frame:ScrollPage(0) end
    end)
    ui.strategy:SetScript("OnClick",function()
        Page.referenceStrategy=(Page.referenceStrategy=="aggressive") and "normal" or "aggressive"
        holder.__referenceMaterialPage=1
        Page:Refresh()
    end)
    -- Bounded material browser lives in the existing Guide scroll child.
    -- This is reference advice, NEVER a craft queue or an inventory action.
    ui.prev=W:Button(c,"Previous",78);ui.prev:SetHeight(24)
    ui.next=W:Button(c,"Next",78);ui.next:SetHeight(24)
    ui.page=W:Label(c,"", "GameFontHighlightSmall")
    ui.prev:SetScript("OnClick",function()
        if not holder.__referenceMaterialReceipt or not holder.__referenceMaterialReceipt.canPrevious then return end
        holder.__referenceMaterialPage=holder.__referenceMaterialReceipt.page-1
        Page:Refresh()
    end)
    ui.next:SetScript("OnClick",function()
        if not holder.__referenceMaterialReceipt or not holder.__referenceMaterialReceipt.canNext then return end
        holder.__referenceMaterialPage=holder.__referenceMaterialReceipt.page+1
        Page:Refresh()
    end)
    ui.notice=C:NoticeRow(c,width,62)
    ui.coverage=C:KeyValueRow(c,width)
    ui.access=C:KeyValueRow(c,width)
    for i=1,3 do
        ui.materialRows[i]=C:MaterialRow(c,width,false)
        ui.sourceRows[i]=C:InlineRow(c,width)
        ui.evidenceButtons[i]=W:Button(c,"Source / recipe details",166)
        ui.evidenceButtons[i]:SetHeight(24)
        ui.evidenceButtons[i]:SetScript("OnClick",function()
            local receipt=holder.__referenceMaterialReceipt
            local item=receipt and receipt.rows and receipt.rows[i] or nil
            if not (item and ui.evidenceSheet and holder.__referenceMaterialKey and
                holder.__referenceMaterialReceipt==receipt and ui.evidenceButtons[i] and
                (not ui.evidenceButtons[i].IsShown or ui.evidenceButtons[i]:IsShown())) then return end
            ui.evidenceSheet:SetRow(item,receipt.rows,i)
            ui.evidenceSheet.frame:Show()
        end)
    end
    if type(W.AdvisorySourceSheet)=="function" then
        ui.evidenceSheet=W:AdvisorySourceSheet(holder,math.min(width-8,370),340)
        if ui.evidenceSheet then
            local sheet=ui.evidenceSheet.frame
            sheet:SetPoint("TOPLEFT",holder,"TOPLEFT",4,-36)
            if sheet.SetFrameLevel and holder.GetFrameLevel then
                sheet:SetFrameLevel(holder:GetFrameLevel()+12)
            end
            ui.evidenceSheet.close:SetScript("OnClick",function() ui.evidenceSheet:Reset() end)
            if ui.evidenceSheet.SetNavigation then
                ui.evidenceSheet:SetNavigation(function(target,reference)
                    if not holder.__referenceMaterialKey or not holder.__referenceMaterialReceipt then return false end
                    local main=JLP.MainWindow
                    return main and main.BeginMaterialReference and
                        main:BeginMaterialReference(target,"Guide",reference,holder)==true or false
                end)
            end
        end
    end
    holder.__foreverReferenceUI=ui
    return ui
end
-- The six Horde research strategies use the existing ProfessionResearch source
-- plan. The source panel is TRANSIENT and does not create a second planner,
-- stock authority or persistent SavedVariables purchase list.
local HORDE_KEYS={ALCHEMY=true,BLACKSMITHING=true,ENCHANTING=true,
    ENGINEERING=true,LEATHERWORKING=true,TAILORING=true}
function Page:GetHordeResearchStep()
    local state=self.hordeResearch
    if not state or not HORDE_KEYS[state.key] then return nil,"RESEARCH_UNAVAILABLE" end
    local research=JLP:GetModule("ProfessionResearch")
    local plan,reason=research and research:BuildSourcePlan(state.key,state.strategy,0,300)
    if not plan then return nil,reason or "SOURCE_UNAVAILABLE" end
    local row=plan.steps[state.stepIndex]
    if not row then return nil,"STEP_CHANGED" end
    return row,nil,plan
end
function Page:RefreshHordeResearchPanel()
    local state=self.hordeResearch
    local frame=self.hordeResearchPanel
    if not state or not frame then return false,"PANEL_UNAVAILABLE" end
    local step,reason,plan=self:GetHordeResearchStep()
    if not step then
        frame.title:SetText("Horde source plan · "..tostring(reason));return false,reason end
    state.stepIdentity=tostring(step.skillMin)..":"..tostring(step.recipeID or step.name)..":"..
        tostring(step.recipeSourceURL or "SOURCE_UNAVAILABLE")..":"..tostring(step.estimatedCrafts)
    local source=JLP:GetModule("SourceResolver")
    local rank=step.skillMin>=200 and "Artisan" or step.skillMin>=125 and "Expert" or
        step.skillMin>=50 and "Journeyman" or "Apprentice"
    local rankInfo=source and source:GetRankRequirement(state.key,rank)
    local trainer=source and source:GetHordeTrainerResearch(state.key,rank)
    local t=trainer and trainer.trainers and trainer.trainers[1]
    local nav=t and source:GetQualifiedHordeTrainerNav(state.key,rank,t.name)
    local trainerInfo=t and (t.name.." · "..tostring(t.zone).." · "..
        (nav and "qualified source map "..tostring(nav.mapID) or
            "MANUAL LOCATION (unqualified map)")) or "Trainer SOURCE_UNAVAILABLE"
    local rows=step.verifiedReagents or {}
    local material=rows[state.materialIndex] or rows[1]
    state.materialIndex=material and (state.materialIndex<=#rows and state.materialIndex or 1) or 1
    material=rows[state.materialIndex]
    frame.title:SetText(state.key.." · "..tostring(plan.strategy)..
        " ("..tostring(plan.sourceMode).." source)")
    frame.summary:SetText("Skill "..tostring(step.skillMin).."–"..tostring(step.skillTarget)..
        " · "..tostring(step.name).." · recipe "..tostring(step.recipeID or "UNKNOWN")..
        "\nGuide estimated crafts "..tostring(step.estimatedCrafts)..
        " (not guaranteed). "..tostring(step.recipeQualification)..
        "\n"..trainerInfo.." · rank "..rank.." (verify learned/client status)"..
        "\n"..(step.sourceConflict and
            "SOURCE CONFLICT · direct verified reagents override historical Word amounts" or
            "No historical source conflict on this step established"))
    local lines={}
    for i,row in ipairs(rows) do
        lines[#lines+1]=(i==state.materialIndex and "> " or "  ")..
            tostring(row.name).." (#"..tostring(row.itemID)..") · "..
            tostring(row.perCraft).." / craft · gross ~"..
            tostring(row.guideGrossEstimate or "UNKNOWN")
    end
    if #lines==0 then lines[1]="SOURCE_UNAVAILABLE · no directly verified item-level reagents. Manual research only." end
    frame.materials:SetText(table.concat(lines,"\n"))
    frame.status:SetText("Research/advisory only · stock UNKNOWN unless requalified by Bank. No price quote or native craft.")
    for _,btn in ipairs({frame.bank,frame.ah}) do
        local enabled=material~=nil and step.recipeQualification=="FOREVER_REFERENCE_VERIFIED" and
            self:MaterialOwnerSignature()~="OWNER_UNKNOWN"
        if btn.SetEnabled then btn:SetEnabled(enabled) end
        if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
    end
    return true
end
-- Page-bound overlays remain physically on UIParent to avoid scrollframe
-- clipping but follow the logical Guide owner on navigation and close.
function Page:Deactivate()
    if JLP.UIWindowRegistry then JLP.UIWindowRegistry:CloseOwner("Guide") end
    if self.frame and JLP.UIInteraction then JLP.UIInteraction:HideTooltipTree(self.frame) end
    if self.targetPicker then
        self.targetPicker:Hide()
        self.targetPicker.__jlpVisualEpoch=(self.targetPicker.__jlpVisualEpoch or 0)+1
    end
    if self.hordeResearchPanel then self.hordeResearchPanel:Hide() end
end
function Page:OpenHordeResearchPanel(key,strategy,skill)
    if not HORDE_KEYS[key] then return false,"PROFESSION_UNAVAILABLE" end
    local research=JLP:GetModule("ProfessionResearch")
    local mode=(strategy=="fastest" or strategy=="aggressive") and "aggressive" or "normal"
    local plan=research and research:BuildSourcePlan(key,mode,0,300)
    if not plan or #plan.steps==0 then return false,"SOURCE_UNAVAILABLE" end
    local selected=1
    if type(skill)=="number" then
        for i,step in ipairs(plan.steps) do
            if skill>=step.skillMin then selected=i end
        end
    end
    self.hordeResearch={key=key,strategy=mode,stepIndex=selected,materialIndex=1,
        ownerSignature=self:MaterialOwnerSignature()}
    if not self.hordeResearchPanel then
        local W=JLP.UIWidgets
        local f=CreateFrame("Frame","JuztLevelProfessionsHordeResearchPanel",UIParent)
        f:SetSize(494,330);f:SetPoint("CENTER",UIParent,"CENTER",0,55)
        local parentWidth=UIParent and UIParent.GetWidth and UIParent:GetWidth() or 600
        local parentHeight=UIParent and UIParent.GetHeight and UIParent:GetHeight() or 450
        local fit=math.min(1,math.max(0.5,math.min((parentWidth-20)/494,(parentHeight-20)/330)))
        if f.SetScale then f:SetScale(fit) end
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        if f.SetClampedToScreen then f:SetClampedToScreen(true) end
        if JLP.UILayout and JLP.UILayout.OverlayFrameLevel then
            f:SetFrameLevel(JLP.UILayout:OverlayFrameLevel(self.frame,"modal"))
        end
        f.__jlpPageOwner=self.name
        if JLP.UIWindowRegistry then
            JLP.UIWindowRegistry:Register("GuideHordeResearch",f,"Guide")
            JLP.UIWindowRegistry:RegisterSpecial("JuztLevelProfessionsHordeResearchPanel")
        end
        if f.EnableMouse then f:EnableMouse(true) end
        W:SkinPanel(f,"secondary")
        f.title=W:Label(f,"Horde research","GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT",15,-14)
        f.summary=W:Label(f,"","GameFontHighlightSmall")
        f.summary:SetPoint("TOPLEFT",15,-49);f.summary:SetWidth(460);f.summary:SetHeight(105)
        if f.summary.SetWordWrap then f.summary:SetWordWrap(true) end
        f.materials=W:Label(f,"","GameFontHighlightSmall")
        f.materials:SetPoint("TOPLEFT",15,-154);f.materials:SetWidth(460);f.materials:SetHeight(82)
        if f.materials.SetWordWrap then f.materials:SetWordWrap(true) end
        f.status=W:Label(f,"","GameFontHighlightSmall")
        f.status:SetPoint("TOPLEFT",15,-239);f.status:SetWidth(458);f.status:SetHeight(34)
        if f.status.SetWordWrap then f.status:SetWordWrap(true) end
        local function navButton(text,x,y,fn)
            local b=W:Button(f,text,88);b:SetHeight(22);b:SetPoint("BOTTOMLEFT",x,y)
            b:SetScript("OnClick",fn);return b
        end
        navButton("Prev step",12,41,function()
            local st=Page.hordeResearch;if not st then return end
            st.stepIndex=math.max(1,st.stepIndex-1);st.materialIndex=1
            Page:RefreshHordeResearchPanel()
        end)
        navButton("Next step",105,41,function()
            local st=Page.hordeResearch;if not st then return end
            local plan=JLP:GetModule("ProfessionResearch"):BuildSourcePlan(st.key,st.strategy,0,300)
            st.stepIndex=math.min(#(plan and plan.steps or {}),st.stepIndex+1)
            st.materialIndex=1;Page:RefreshHordeResearchPanel()
        end)
        navButton("Next item",198,41,function()
            local st=Page.hordeResearch;local step=Page:GetHordeResearchStep()
            if not st or not step then return end
            st.materialIndex=(st.materialIndex % math.max(1,#(step.verifiedReagents or {})))+1
            Page:RefreshHordeResearchPanel()
        end)
        navButton("Econom./Fast",291,41,function()
            local st=Page.hordeResearch;if not st then return end
            st.strategy=st.strategy=="normal" and "aggressive" or "normal"
            st.materialIndex=1;Page:RefreshHordeResearchPanel()
        end)
        navButton("Close",384,41,function() f:Hide() end)
        f.bank=navButton("Inspect Bank",75,12,function() Page:InspectHordeResearchMaterial("Bank") end)
        f.ah=navButton("Manual AH",175,12,function() Page:InspectHordeResearchMaterial("Auction House") end)
        function f:ApplyViewportFit()
            local width=UIParent and UIParent.GetWidth and UIParent:GetWidth() or 600
            local height=UIParent and UIParent.GetHeight and UIParent:GetHeight() or 450
            local fit=math.min(1,math.max(0.5,math.min((width-20)/494,(height-20)/330)))
            if self.SetScale then self:SetScale(fit) end
            self:ClearAllPoints();self:SetPoint("CENTER",UIParent,"CENTER",0,0)
        end
        f:SetScript("OnShow",function(self) self:ApplyViewportFit() end)
        f:Hide();self.hordeResearchPanel=f
    end
    self:RefreshHordeResearchPanel()
    if self.hordeResearchPanel.ApplyViewportFit then self.hordeResearchPanel:ApplyViewportFit() end
    if not (JLP.UIWindowRegistry and JLP.UIWindowRegistry:OpenModal("Guide","GuideHordeResearch")) then
        self.hordeResearchPanel:Show()
    end
    return true
end
function Page:InspectHordeResearchMaterial(target)
    local row,reason=self:GetHordeResearchStep()
    local state=self.hordeResearch
    local reagent=row and row.verifiedReagents and row.verifiedReagents[state.materialIndex]
    if not reagent or row.recipeQualification~="FOREVER_REFERENCE_VERIFIED" then
        return false,reason or "SOURCE_UNAVAILABLE" end
    local owner=self:MaterialOwnerSignature()
    if owner=="OWNER_UNKNOWN" or owner~=state.ownerSignature then return false,"OWNER_CHANGED" end
    local main=JLP.MainWindow
    if not main then return false,"NAVIGATION_UNAVAILABLE" end
    local qualified={itemID=reagent.itemID,name=reagent.name,
        source=reagent.sourceURL,required=reagent.guideGrossEstimate,
        readOnly=true,nativeDispatchAllowed=false}
    local ok,why=main:BeginMaterialReference(target,"Guide",qualified,self.hordeResearchPanel)
    if ok and self.hordeResearchPanel then self.hordeResearchPanel:Hide() end
    return ok,why
end
-- Origin adapters only capture a currently visible and source-qualified row.
-- No recipe/inventory quantities are persisted across navigation.
function Page:CaptureMaterialReference(reference,holder)
    if holder and holder==self.hordeResearchPanel then
        local state=self.hordeResearch
        local step=self:GetHordeResearchStep()
        local row=step and step.verifiedReagents and state and step.verifiedReagents[state.materialIndex]
        if not state or not step or not row or not holder.IsShown or not holder:IsShown() or
            row.itemID~=reference.itemID or row.sourceURL~=reference.source or
            row.guideGrossEstimate~=reference.required or
            state.ownerSignature~=self:MaterialOwnerSignature() or
            state.ownerSignature=="OWNER_UNKNOWN" then return nil,"RESEARCH_SOURCE_CHANGED" end
        return {page="Guide",mode=self:GetMode(),holder=holder,horde=true,
            ownerSignature=state.ownerSignature,materialID=row.itemID,
            source=row.sourceURL,required=row.guideGrossEstimate,
            identity=state.stepIdentity,key=state.key,strategy=state.strategy,
            stepIndex=state.stepIndex,materialIndex=state.materialIndex,
            readOnly=true,nativeDispatchAllowed=false}
    end
    local frame=self.frame
    if not frame or not holder or not
        ((frame.single and frame.single.materials==holder) or
         (frame.dual and (frame.dual.left==holder or frame.dual.right==holder))) then
        return nil,"ORIGIN_NOT_CURRENT"
    end
    if holder.__smeltingReference and reference==holder.__smeltingReference then
        local owner=self:MaterialOwnerSignature()
        if owner=="OWNER_UNKNOWN" or holder.__smeltingOwner~=owner then
            return nil,"OWNER_UNKNOWN"
        end
        local smelt=JLP:GetModule("MiningSmeltingProgression")
        local advice=smelt and smelt:BuildMaterialAdvice(holder.__smeltingSkill)
        local material=advice and advice.materials and advice.materials[holder.__smeltingMaterialIndex]
        if not material or material.itemID~=reference.itemID or
            reference.required~=material.perSmelt or
            reference.source~=holder.__smeltingReference.source or
            advice.recipe~=holder.__smeltingRecipe then return nil,"SOURCE_CHANGED" end
        return {page="Guide",mode=self:GetMode(),holder=holder,smelting=true,
            ownerSignature=owner,materialID=reference.itemID,readOnly=true,
            nativeDispatchAllowed=false,source=reference.source,required=reference.required,
            skill=holder.__smeltingSkill,recipe=advice.recipe,
            materialIndex=holder.__smeltingMaterialIndex}
    end
    local receipt=holder and holder.__referenceMaterialReceipt
    -- New Guide renders always stamp the owner. Older read-only Guide
    -- adapters may not have the field; bind them at capture instead of
    -- treating absence as a confirmed foreign owner. Once stamped, a changed
    -- owner always fails closed on subsequent capture and Return.
    if holder.__referenceOwnerSignature and
        holder.__referenceOwnerSignature~=self:MaterialOwnerSignature() then
        return nil,"CHARACTER_CHANGED"
    end
    local ui=holder and holder.__foreverReferenceUI
    if not (receipt and ui and ui.evidenceSheet and
        ui.evidenceSheet.currentReference and ui.evidenceSheet.frame and
        ui.evidenceSheet.frame.IsShown and ui.evidenceSheet.frame:IsShown()) then
        return nil,"REFERENCE_NOT_VISIBLE"
    end
    local rowIndex,row
    for i,item in ipairs(receipt.rows or {}) do
        local same=item==ui.evidenceSheet.currentRow
        if not same and JLP.UIWidgets and JLP.UIWidgets.MaterialReferenceIdentity then
            same=ui.evidenceSheet.currentIdentity~=nil and
                JLP.UIWidgets:MaterialReferenceIdentity(item)==ui.evidenceSheet.currentIdentity
        end
        if same then rowIndex,row=i,item;break end
    end
    if not rowIndex then return nil,"REFERENCE_STALE" end
    local qualified=JLP.UIWidgets:QualifiedMaterialReference(row)
    if not qualified or qualified.itemID~=reference.itemID or
        qualified.required~=reference.required or qualified.source~=reference.source or
        qualified.bankKnown~=reference.bankKnown then return nil,"SOURCE_CHANGED" end
    local layout=JLP.UILayout
    local outer=self.frame
    return {page="Guide",mode=self:GetMode(),materialID=qualified.itemID,
        identity=holder.__referenceMaterialKey,materialPage=receipt.page,rowIndex=rowIndex,
        holder=holder,readOnly=true,nativeDispatchAllowed=false,
        ownerSignature=holder.__referenceOwnerSignature or self:MaterialOwnerSignature(),
        source=qualified.source,required=qualified.required,bankKnown=qualified.bankKnown,
        scroll=layout and layout.CaptureScrollPosition and layout:CaptureScrollPosition(holder.scroll) or 0,
        outerScroll=outer and (tonumber(outer.scrollOffset) or 0) or 0,
        sheetScroll=layout and layout.CaptureScrollPosition and
            layout:CaptureScrollPosition(ui.evidenceSheet.viewport) or 0}
end
function Page:ClearMaterialReference()
    if self.hordeResearchPanel then self.hordeResearchPanel:Hide() end
    self.hordeResearch=nil
    local f=self.frame
    if not f then return end
    for _,holder in pairs({single=f.single and f.single.materials,
        left=f.dual and f.dual.left,right=f.dual and f.dual.right}) do
        if holder then
            holder.__smeltingReference=nil;holder.__smeltingOwner=nil
            holder.__smeltingReturnMessage=nil
        end
        if holder and holder.__foreverReferenceUI then
            local sheet=holder.__foreverReferenceUI.evidenceSheet
            if sheet and sheet.Reset then sheet:Reset() end
            holder.__referenceMaterialReceipt=nil
            holder.__referenceMaterialPage=1
        end
    end
end
function Page:RestoreMaterialReference(capture)
    if type(capture)=="table" and capture.horde==true then
        local state=self.hordeResearch
        if not state or state.key~=capture.key or state.strategy~=capture.strategy or
            state.stepIndex~=capture.stepIndex or state.materialIndex~=capture.materialIndex or
            capture.ownerSignature~=self:MaterialOwnerSignature() or
            capture.ownerSignature=="OWNER_UNKNOWN" then return false,"RESEARCH_OR_OWNER_CHANGED" end
        local step=self:GetHordeResearchStep()
        local mat=step and step.verifiedReagents and step.verifiedReagents[state.materialIndex]
        if not step or not mat or state.stepIdentity~=capture.identity or
            mat.itemID~=capture.materialID or mat.sourceURL~=capture.source or
            mat.guideGrossEstimate~=capture.required then return false,"RESEARCH_SOURCE_CHANGED" end
        self:RefreshHordeResearchPanel()
        if self.hordeResearchPanel then
            if not (JLP.UIWindowRegistry and JLP.UIWindowRegistry:OpenModal("Guide","GuideHordeResearch")) then
                self.hordeResearchPanel:Show()
            end
        end
        return true
    end
    if type(capture)~="table" or capture.mode~=self:GetMode() or
        capture.readOnly~=true or capture.nativeDispatchAllowed~=false then return false end
    local holder=capture.holder
    if capture.smelting==true then
        if not holder or capture.ownerSignature=="OWNER_UNKNOWN" or
            capture.ownerSignature~=self:MaterialOwnerSignature() then return false end
        self:Refresh() -- Rebuild live skill, material identity and exact source.
        local ref=holder.__smeltingReference
        if not ref or holder.__smeltingOwner~=capture.ownerSignature or
            holder.__smeltingSkill~=capture.skill or
            holder.__smeltingRecipe~=capture.recipe or
            holder.__smeltingMaterialIndex~=capture.materialIndex or
            ref.itemID~=capture.materialID or ref.source~=capture.source or
            ref.required~=capture.required then return false end
        holder.__smeltingReturnMessage="Returned to source-qualified Smelting material · manual action only"
        if holder.smeltingStatus and holder.smeltingStatus.SetText then
            holder.smeltingStatus:SetText(holder.__smeltingReturnMessage)
        end
        return true
    end
    if not holder or not holder.__referenceMaterialKey or
        holder.__referenceMaterialKey~=capture.identity then return false end
    if capture.ownerSignature and capture.ownerSignature~=self:MaterialOwnerSignature() then
        return false
    end
    holder.__referenceMaterialPage=capture.materialPage
    self:Refresh() -- re-resolve profession, skill, strategy and recipe evidence
    if holder.__referenceMaterialKey~=capture.identity then return false end
    local receipt=holder.__referenceMaterialReceipt
    local row=receipt and receipt.page==capture.materialPage and
        receipt.rows and receipt.rows[capture.rowIndex]
    local qualified=row and JLP.UIWidgets:QualifiedMaterialReference(row)
    if not qualified or qualified.itemID~=capture.materialID or
        qualified.source~=capture.source or qualified.required~=capture.required or
        qualified.bankKnown~=capture.bankKnown then return false end
    local sheet=holder.__foreverReferenceUI and holder.__foreverReferenceUI.evidenceSheet
    if not sheet then return false end
    sheet:SetRow(row,receipt.rows,capture.rowIndex);sheet.frame:Show()
    local layout=JLP.UILayout
    if layout and layout.RestoreScrollPosition then
        layout:RestoreScrollPosition(holder.scroll,capture.scroll)
        layout:RestoreScrollPosition(sheet.viewport,capture.sheetScroll)
    end
    if self.frame and self.frame.ScrollPage then self.frame:ScrollPage(capture.outerScroll or 0) end
    return true
end
local function renderReferencePreview(holder,key,skill,startY)
    local viewModule=JLP:GetModule("ForeverRouteGuideView")
    if not viewModule or not viewModule:IsSupported(key) then
        -- The Forever source research UI also serves Horde Tailoring and
        -- Enchanting, which have no ForeverRouteGuideView band adapter. Keep
        -- their read-only strategy/material entrance visible independently.
        hideReferencePreview(holder)
        if HORDE_KEYS[key] then
            local ui=ensureReferencePreview(holder)
            hideReferencePreview(holder)
            -- Content end is authoritative. Keep one small gap above the
            -- section heading, one between heading and 26-unit button, and
            -- 12 units after the button (not the old 32-unit blank tail).
            local y=math.max(0,tonumber(startY) or 0)+7
            -- Single-profession Materials & Sources sometimes contains less
            -- than one viewport of content. In that case its research CTA
            -- should finish a small, natural distance above the card bottom,
            -- not leave a large dead zone underneath. Dual cards keep normal
            -- flowing content and use the smaller crafting bottom inset.
            if not holder.__dualTemplate then
                local viewportHeight=tonumber(holder.scroll.__layoutHeight) or 0
                y=math.max(y,viewportHeight-(26+26+12))
            end
            ui.title:ClearAllPoints();ui.title:SetPoint("TOPLEFT",0,-y)
            ui.title:SetText(tostring(key).." HORDE RESEARCH · READ-ONLY")
            ui.title:Show()
            ui.hordeResearch:ClearAllPoints()
            ui.hordeResearch:SetPoint("TOPLEFT",0,-y-26)
            ui.hordeResearch:Show()
            holder.__referenceProfessionKey=key
            holder.__referenceDisplayedSkill=skill
            holder.scroll:SetContentHeight(y+26+26+12,true)
        end
        return
    end
    local isBandBrowser=key=="BLACKSMITHING" or key=="LEATHERWORKING"
    local override=isBandBrowser and Page.referenceSkillOverride[key] or nil
    local displayedSkill=override or skill
    local view=viewModule:Build(key,displayedSkill,Page.referenceStrategy)
    if not view then
        -- Candidate route unavailability is a visible, non-native recovery
        -- instruction instead of silently hiding the only candidate flow.
        -- Research and candidate professions share a read-only unavailable
        -- receipt. Absence of source-qualified reference data must not leave
        -- an old material list or a silent, apparently successful view.
        local unavailable=ensureReferencePreview(holder)
        hideReferencePreview(holder)
        local y=math.max(0,tonumber(startY) or 0)+14
        unavailable.title:ClearAllPoints();unavailable.title:SetPoint("TOPLEFT",0,-y)
        unavailable.title:SetText(key=="ALCHEMY" and "ALCHEMY CANDIDATE · READ-ONLY" or
            (tostring(key).." RESEARCH · READ-ONLY"))
        unavailable.title:Show()
        unavailable.notice:ClearAllPoints();unavailable.notice:SetPoint("TOPLEFT",0,-y-34)
        unavailable.notice:SetNotice("warning",
            key=="ALCHEMY" and
            "Current-build candidate materials unavailable. Verify skill and source; retry manually. Native crafting disabled." or
            "Source-qualified research materials unavailable. Review profession skill, strategy and evidence; retry manually. Native crafting disabled.","muted")
        unavailable.notice:Show()
        -- A manually selected source band can become unavailable after a
        -- source/character update. Keep its non-native escape control visible
        -- even when the former research view cannot be rebuilt.
        holder.__referenceProfessionKey=key
        holder.__referenceDisplayedSkill=displayedSkill
        if HORDE_KEYS[key] and unavailable.hordeResearch then
            unavailable.hordeResearch:ClearAllPoints()
            unavailable.hordeResearch:SetPoint("TOPLEFT",0,-y-(override and 145 or 107))
            unavailable.hordeResearch:Show()
        end
        if isBandBrowser and override~=nil then
            unavailable.bandReset:ClearAllPoints()
            unavailable.bandReset:SetPoint("TOPLEFT",0,-y-111)
            unavailable.bandReset:SetText("Current skill")
            unavailable.bandReset:Show()
            holder.scroll:SetContentHeight(y+205,true)
        else
            holder.scroll:SetContentHeight(y+160,true)
        end
        return
    end
    local ui=ensureReferencePreview(holder)
    ui.title:SetText(key=="ALCHEMY" and "ALCHEMY CANDIDATE · READ-ONLY" or
        (key.." RESEARCH · READ-ONLY"))
    local y=math.max(0,tonumber(startY) or 0)+14
    ui.title:ClearAllPoints();ui.title:SetPoint("TOPLEFT",0,-y);ui.title:Show()
    ui.strategy:ClearAllPoints();ui.strategy:SetPoint("TOPRIGHT",0,-y+6)
    ui.strategy:SetText(view.mode=="aggressive" and "Fastest (Aggressive source)" or
        "Economical (Normal source)");ui.strategy:Show()
    y=y+34
    holder.__referenceProfessionKey=key
    holder.__referenceDisplayedSkill=displayedSkill
    if isBandBrowser then
        ui.bandNext:ClearAllPoints();ui.bandNext:SetPoint("TOPLEFT",0,-y)
        ui.bandFirst:ClearAllPoints();ui.bandFirst:SetPoint("TOPRIGHT",0,-y)
        ui.bandPrevious:ClearAllPoints();ui.bandPrevious:SetPoint("TOPLEFT",0,-y-29)
        ui.bandLast:ClearAllPoints();ui.bandLast:SetPoint("TOPRIGHT",0,-y-29)
        ui.bandReset:ClearAllPoints();ui.bandReset:SetPoint("TOPRIGHT",0,-y-58)
        local canRewind,rewindReason=Page:SelectPreviousQualifiedBand(key,displayedSkill,Page.referenceStrategy,true)
        ui.bandPrevious:SetEnabled(canRewind==true)
        ui.bandPrevious:SetAlpha(canRewind and 1 or 0.45)
        ui.bandPrevious:SetText(canRewind and "Previous sourced band" or "No previous sourced band")
        holder.__referenceRewindReason=canRewind and nil or rewindReason
        ui.bandPrevious:Show()
        local canAdvance,advanceReason=Page:SelectNextQualifiedBand(key,displayedSkill,Page.referenceStrategy,true)
        ui.bandNext:SetEnabled(canAdvance==true)
        ui.bandNext:SetText(canAdvance and "Next sourced band" or "No next sourced band")
        ui.bandNext:Show()
        local firstOK,firstSkill=Page:SelectFirstQualifiedBand(key,Page.referenceStrategy,true)
        local firstAvailable=firstOK and firstSkill~=displayedSkill
        ui.bandFirst:SetEnabled(firstAvailable==true)
        ui.bandFirst:SetAlpha(firstAvailable and 1 or 0.45)
        ui.bandFirst:SetText(firstAvailable and "First sourced band" or "At first sourced band")
        ui.bandFirst:Show()
        local lastOK,lastSkill=Page:SelectLastQualifiedBand(key,Page.referenceStrategy,true)
        local lastAvailable=lastOK and lastSkill~=displayedSkill
        ui.bandLast:SetEnabled(lastAvailable==true)
        ui.bandLast:SetAlpha(lastAvailable and 1 or 0.45)
        ui.bandLast:SetText(lastAvailable and "Last sourced band" or "At last sourced band")
        ui.bandLast:Show()
        -- Current skill remains available after any manual override, even at
        -- the terminal step. No native craft or learned-skill change occurs.
        ui.bandReset:SetShown(override~=nil)
        holder.__referenceAdvanceReason=canAdvance and nil or advanceReason
        -- Three navigation rows are only needed while Current skill/reset is
        -- visible. Without a manual override do not reserve a phantom row.
        y=y+(override~=nil and 89 or 59)
    else
        ui.bandNext:Hide();ui.bandFirst:Hide();ui.bandLast:Hide();ui.bandPrevious:Hide();ui.bandReset:Hide()
    end
    ui.notice:ClearAllPoints();ui.notice:SetPoint("TOPLEFT",0,-y)
    local text="Source-qualified reagents are verified PER CRAFT only. Expected crafts, gross materials and missing amounts are research estimates; bank and acquisition advice remain read-only."
    if view.skillGateConflict then
        text="SKILL ELIGIBILITY GAP: "..tostring(view.skillBandRecipe or "Recipe")..
          " requires "..tostring(view.skillBandRequiredSkill or
                (view.skillEligibility and view.skillEligibility.minimumSkill) or "unverified minimum")..
          ". This interval is not qualified for progression. Verify a skill-eligible recipe."
    end
    if view.candidateReadOnly and not view.skillGateConflict then
        text="Alchemy has the same Forever materials and acquisition preview. Historical craft estimates only; native crafting remains disabled."
    end
    local terminal=holder.__referenceAdvanceReason
    local feedback=Page.referenceBandFeedback
    if feedback and (feedback.key~=key or feedback.skill~=displayedSkill) then
        Page.referenceBandFeedback=nil;feedback=nil
    end
    if override~=nil or terminal or feedback then
        local status=override~=nil and ("MANUAL SOURCE BAND "..tostring(displayedSkill)..
            " · character skill "..tostring(skill or "UNKNOWN")..". Research only.") or ""
        if terminal then
            local explanation=terminal=="NO_NEXT_QUALIFIED_BAND" and
                "END OF QUALIFIED SOURCE BANDS · Current skill resets the manual selection." or
                ("NEXT BAND UNAVAILABLE ("..tostring(terminal).."). Verify current skill/source.")
            status=status~="" and (status.." ")..explanation or explanation
        end
        if feedback then status=status.." · Selection: "..tostring(feedback.reason) end
        ui.bandSelection:ClearAllPoints();ui.bandSelection:SetPoint("TOPLEFT",0,-y)
        ui.bandSelection:SetHeight(54)
        ui.bandSelection:SetText(status)
        ui.bandSelection:Show();y=y+58
    else ui.bandSelection:Hide() end
    if Page.materialReferenceWarning then text=Page.materialReferenceWarning.." "..text end
    ui.notice:SetNotice((view.skillGateConflict or Page.materialReferenceWarning) and "warning" or "info",text,"muted")
    ui.notice:Show();y=y+70
    ui.coverage:ClearAllPoints();ui.coverage:SetPoint("TOPLEFT",0,-y)
    ui.coverage:SetRow("recipe","Reference coverage",string.format("%d material IDs · %d research-only steps · %d hidden",view.materialCount,view.unknownReferenceSteps,view.hiddenMaterialCount),"gold")
    ui.coverage:Show();y=y+29
    if JLP.UIWidgets and JLP.UIWidgets.SetAdvisoryStatusText and ui.page then
        -- Set a consistent wrapped/height-bounded label when material navigation
        -- is shown; page count itself is subsequently set by the shared pager.
        JLP.UIWidgets:SetAdvisoryStatusText(ui.page,ui.page.GetText and ui.page:GetText() or "",190,30)
    end
    -- Public recipe-item access, not an assertion that a vendor has stock or
    -- that the character has learned the recipe. No NPC visit is mandatory.
    local proof=view.verifiedRecipeAccess and view.verifiedRecipeAccess[1]
    if key=="ALCHEMY" and tonumber(skill) and skill>=250 and proof then
        ui.access:ClearAllPoints();ui.access:SetPoint("TOPLEFT",0,-y)
        ui.access:SetRow("recipe","Recipe access",
            string.format("%s · item %d · skill %d · vendor/learned UNKNOWN",
                tostring(proof.recipe),proof.recipeItemID,proof.requiredSkillToLearn),"gold")
        ui.access:Show();y=y+29
    elseif key~="ALCHEMY" and view.skillBandRecipe then
        -- A bounded read-only next-step cue for the current research band.
        -- Does NOT assert the recipe is known or native craftable.
        ui.access:ClearAllPoints();ui.access:SetPoint("TOPLEFT",0,-y)
        ui.access:SetRow("recipe","Research step",
            tostring(view.skillBandRecipe).." · required skill "..
            tostring(view.skillBandRequiredSkill or "UNKNOWN").." · historical only","gold")
        ui.access:Show();y=y+29
    else
        ui.access:Hide()
    end
    -- All four source-qualified reference professions can browse the same
    -- read-only materials. Only Alchemy is candidate; the others remain
    -- research-only and never receive native crafting authority.
    local pageSource=viewModule
    -- Skill and strategy can change the qualified materials while the same
    -- profession card remains open. Never retain an unrelated old page.
    local materialIdentity=tostring(Page:MaterialOwnerSignature())..":"..tostring(key)..":"..tostring(displayedSkill)..":"..
        (override~=nil and "MANUAL" or "CURRENT")..":"..tostring(view.mode)..":"..
        tostring(view.materialCount or 0)..":"..tostring(view.unknownReferenceSteps or 0)..":"..
        tostring(view.skillBandRecipe or "")..":"..tostring(view.skillBandRequiredSkill or "")..":"..
        tostring(view.skillGateConflict == true)
    -- Different qualified recipes can contain the same material-row count.
    -- Bind page state to the actual per-recipe evidence, never a stale card.
    for _,material in ipairs(view.skillBandMaterials or {}) do
        materialIdentity=materialIdentity..":band:"..tostring(material.itemID)..":"..
            tostring(material.grossRequired)..":"..tostring(material.perCraft)..":"..
            tostring(material.estimatedCraftCount)..":"..tostring(material.sourceURL)..":"..
            tostring(material.bankKnown)..":"..tostring(material.externalRequired)
        for _,band in ipairs(material.recipeBands or {}) do
            materialIdentity=materialIdentity..":"..tostring(band.recipe)..":"..
                tostring(band.recipeID)..":"..tostring(band.skillMin)..":"..
                tostring(band.sourceURL)
        end
    end
    for _,material in ipairs(view.materials or {}) do
        materialIdentity=materialIdentity..":"..tostring(material.itemID)..":"..
            tostring(material.grossRequired)..":"..tostring(material.perCraft)..":"..
            tostring(material.estimatedCraftCount)..":"..tostring(material.sourceURL)..":"..
            tostring(material.sourceText)..":"..tostring(material.bankKnown)..":"..
            tostring(material.currentBankAvailable)..":"..tostring(material.externalRequired)
    end
    holder.__referenceOwnerSignature=self:MaterialOwnerSignature()
    if holder.__referenceMaterialKey~=materialIdentity then
        holder.__referenceMaterialPage=1; holder.__referenceMaterialKey=materialIdentity
        if ui.evidenceSheet and ui.evidenceSheet.Reset then ui.evidenceSheet:Reset() end
    end
    local previousReceipt=holder.__referenceMaterialReceipt
    local receipt=pageSource and pageSource.MaterialPage and
        pageSource:MaterialPage(view,holder.__referenceMaterialPage,3) or nil
    if previousReceipt and receipt and previousReceipt.page~=receipt.page and
        ui.evidenceSheet and ui.evidenceSheet.Reset then ui.evidenceSheet:Reset() end
    local allRows=receipt and receipt.rows or view.materials
    local page=receipt and receipt.page or 1
    local pageCount=receipt and receipt.pageCount or 1
    holder.__referenceMaterialPage=page
    holder.__referenceMaterialReceipt=receipt
    -- Qualified research/reference rows share this presentation-only browser.
    -- Missing rows cannot fabricate receipt or native authority.
    if not receipt and ui.evidenceSheet and ui.evidenceSheet.Reset then ui.evidenceSheet:Reset() end
    local hasPager=receipt and receipt.total>0
    ui.prev:SetShown(hasPager==true);ui.next:SetShown(hasPager==true);ui.page:SetShown(hasPager==true)
    if hasPager then
        ui.prev:ClearAllPoints();ui.prev:SetPoint("TOPLEFT",0,-y)
        ui.next:ClearAllPoints();ui.next:SetPoint("TOPRIGHT",0,-y)
        ui.page:ClearAllPoints();ui.page:SetPoint("TOPLEFT",0,-y-28)
        ui.page:SetWidth(math.max(180,(holder.scroll.__contentWidth or 360)-8))
        ui.page:SetText(string.format("Selected band materials %d-%d / %d · page %d/%d",
            (page-1)*3+1,math.min(page*3,receipt.total),receipt.total,page,pageCount))
        if JLP.UIWidgets and JLP.UIWidgets.ApplyAdvisoryPager then
            JLP.UIWidgets:ApplyAdvisoryPager(ui.prev,ui.next,ui.page,receipt,
                string.format("Materials %d-%d / %d · page %d/%d",
                    (page-1)*3+1,math.min(page*3,receipt.total),receipt.total,page,pageCount))
        else
            if ui.prev.SetEnabled then ui.prev:SetEnabled(receipt.canPrevious) end
            if ui.next.SetEnabled then ui.next:SetEnabled(receipt.canNext) end
        end
        y=y+51
    end
    for i=1,3 do
        local row=allRows[i]
        local material=ui.materialRows[i]
        local source=ui.sourceRows[i]
        if row then
            if JLP.UIWidgets and JLP.UIWidgets.AdvisoryMaterialTooltip then
                JLP.UIWidgets:AdvisoryMaterialTooltip(source,{
                    name=row.name,source=row.sourceText,sourceURL=row.sourceURL,
                    guideEstimate=row.grossRequired,perCraft=row.perCraft,
                    estimatedCraftCount=row.estimatedCraftCount,bags=row.bagsAvailable,
                    bankKnown=row.bankKnown,bank=row.currentBankAvailable,
                    externalNeededIfGuideEstimateHolds=row.externalRequired})
            end
            material:ClearAllPoints();material:SetPoint("TOPLEFT",0,-y)
            material:SetMaterial({itemID=row.itemID,name=row.name,source="reference",
                required=row.grossRequired,owned=(row.bagsAvailable and row.bankKnown and row.currentBankAvailable) and
                    (row.bagsAvailable+row.currentBankAvailable) or nil,
                missing=row.externalRequired,storage={bags=row.bagsAvailable,bank=row.bankKnown and row.currentBankAvailable or nil}})
            material:Show();y=y+(material.__layoutHeight or 76)+3
            source:ClearAllPoints();source:SetPoint("TOPLEFT",0,-y)
            local note=row.sourceShort
            if row.sourceVerifiedPerCraft==true then
                -- Reagent amount is sourced; expected crafts and any resulting
                -- gross/missing stock are NOT source-verified future actions.
                note="Source x"..tostring(row.perCraft).." / craft × est. "..
                    tostring(row.estimatedCraftCount).." crafts = ~"..
                    tostring(row.grossRequired).." gross; ~"..
                    tostring(row.externalRequired or "UNKNOWN").." external (POINT unavailable)"
            end
            if not row.bankKnown then note=note.." · bank UNKNOWN" end
            source:SetRow("materials",row.sourceVerifiedPerCraft and "Material estimate" or
                "Conditional sources",note,"muted")
            -- Reserve two actual text lines for sourced formulae instead of
            -- positioning the next clickable Source button on top of wrapping.
            local noteHeight=row.sourceVerifiedPerCraft and 42 or 22
            if source.SetHeight then source:SetHeight(noteHeight) end
            if source.text and source.text.SetWordWrap then
                source.text:SetWordWrap(row.sourceVerifiedPerCraft==true)
            end
            if source.text and source.text.ClearAllPoints then
                source.text:ClearAllPoints()
                source.text:SetPoint("TOPLEFT",source.icon,"TOPRIGHT",9,0)
                source.text:SetPoint("TOPRIGHT",source,"TOPRIGHT",-2,0)
            end
            source:Show();y=y+noteHeight+5
            local evidence=ui.evidenceButtons[i]
            if evidence then
                evidence:ClearAllPoints();evidence:SetPoint("TOPLEFT",0,-y)
                evidence:SetShown(ui.evidenceSheet~=nil)
                y=y+27
            end
        else
            material:Hide();source:Hide()
            if ui.evidenceButtons[i] then ui.evidenceButtons[i]:Hide() end
        end
    end
    local layout=JLP.UILayout
    local viewport=holder.scroll.__layoutHeight or 1
    local contentHeight=layout and layout.BoundedContentHeight and
        layout:BoundedContentHeight(y+10,viewport,16000) or y+10
    if ui.back then
        ui.back:ClearAllPoints()
        ui.back:SetPoint("TOPLEFT",0,-(contentHeight-6))
        ui.back:SetShown(key~="ALCHEMY" and receipt~=nil and receipt.total>0)
        if ui.back.IsShown and ui.back:IsShown() then
            contentHeight=layout and layout.BoundedContentHeight and
                layout:BoundedContentHeight(contentHeight+36,viewport,16000) or contentHeight+36
        end
    end
    holder.scroll:SetContentHeight(contentHeight,true)
end

-- Alpha171: non-crafting profession guide. Reuses the existing blue Guide cards.
-- All data is read-only historical/learned evidence; no native gathering authority.
local function renderGatheringSingle(single,selected)
    local presenter=JLP:GetModule("GatheringGuidePresentation")
    local data=presenter and presenter:Build(selected.key,selected.skill,selected.maxSkill)
    if not data then return false end
    local card=single.plan
    card.__professionKey=selected.key;card.__plan=nil
    setDirectControls(card,nil)
    stableSetShown(card.preDispatch,false);stableSetShown(card.routeAuto,false)
    stableSetShown(card.gatheringGenerate,not data.currentStep or data.currentStep.kind=="gather")
    hideContextCTA(card)
    card.targetSlot:SetTarget(nil);card.actionFeedback:Hide()
    card.mapButton:Hide();card.ahButton:Hide();card.materialButton:Hide()
    card.badge:SetStatus(data.routeStopCount>0 and "ROUTE READY" or "GATHERING","good")
    card.stepLabel:SetText(data.currentStep and "CURRENT STEP" or "CURRENT GATHERING OBJECTIVE")
    card.nextLabel:SetText("NEXT ACTION")
    card.readyLabel:SetText("GATHERING READINESS")
    card.upcomingLabel:SetText("GATHERING PROGRESSION")
    local icon=JLP.UIIconResolver:GetProfession(selected.key,selected)
    card.stepBlock:SetAction(icon,data.objectiveTitle or ("Gather resources in "..data.zoneName),
        data.currentStep and data.nextAction or (data.resourceCount>0 and ("Skill-eligible historical resources: "..data.resourceText) or
        "No verified eligible references in this zone. Open the map to choose another zone."))
    card.nextBlock:SetAction(icon,data.objectiveTitle or (data.routeStopCount>0 and "Follow gathering route" or "Choose and generate a route"),
        data.nextAction)
    hideRequirementRows(card)
    for i,row in ipairs(card.readinessRows or {}) do
        if i==1 then row:SetRow("profession","Profession skill",tostring(data.skill).." / "..tostring(data.maxSkill),"cyan");row:Show()
        elseif i==2 then row:SetRow("zone","Selected zone",data.zoneName);row:Show()
        elseif i==3 then row:SetRow("resources","Eligible historical types",tostring(data.resourceCount));row:Show()
        elseif i==4 then row:SetRow("route","Route mode",data.routeMode);row:Show()
        elseif i==5 then row:SetRow("selection","Custom resources selected",tostring(data.selectedResourceCount));row:Show()
        elseif i==6 then row:SetRow("route","Route stops",tostring(data.routeStopCount));row:Show()
        else row:Hide() end
    end
    card.readiness:SetText(data.qualification)
    card.progression:SetText(data.smeltingCandidate and data.smeltingCandidate.explanation or
        data.sourceSummary or "Gather eligible nodes; check trainer access near your skill cap. Skill gains are not guaranteed.")
    card.upcoming:SetText(card.progression:GetText() or "")
    card.nextAction:SetText(data.nextAction)
    local holder=single.materials
    -- Gathering has no active craft-step material qualification. Clear the
    -- previous profession's source quality before the early return.
    if holder.qualityNote then holder.qualityNote:Hide() end
    card.__requirementModel=nil
    hideReferencePreview(holder)
    for _,row in ipairs(holder.materialRows or {}) do row:Hide() end
    for _,row in ipairs(holder.trainerRows or {}) do row:Hide() end
    holder.trainerLabel:Hide();holder.processLabel:Hide()
    holder.sourceLabel:Show();holder.sourceLabel:SetText("GATHERING SOURCES")
    holder.sourceLabel:ClearAllPoints();holder.sourceLabel:SetPoint("TOPLEFT",0,0)
    holder.sourceRow:Show();holder.sourceRow:SetRow("zone","Historical zone",data.zoneName,"cyan")
    holder.sourceRow:ClearAllPoints();holder.sourceRow:SetPoint("TOPLEFT",0,-28)
    restoreGatheringSourceBlock(holder.process1)
    restoreGatheringSourceBlock(holder.process2)
    holder.process1:Show();holder.process1:SetBlock("resources","Recommended eligible nodes",data.resourceText,"cyan")
    holder.process1:ClearAllPoints();holder.process1:SetPoint("TOPLEFT",0,-68)
    holder.process2:Show();holder.process2:SetBlock("info",
        data.smeltingCandidate and "Mining: conditional Smelting option" or "Historical data only",
        data.sourceSummary or (data.smeltingCandidate and data.smeltingCandidate.explanation or data.qualification),"gold")
    holder.process2:ClearAllPoints();holder.process2:SetPoint("TOPLEFT",0,-151)
    -- Source-backed Smelting is a conditional alternative, not a craft queue.
    -- Only identities independently verified in Forever recipe reagent rows
    -- unlock exact Bank/AH navigation. A single smelt is NOT a craft estimate.
    holder.__smeltingReference=nil;holder.__smeltingOwner=nil
    if selected.key=="MINING" then
        local smelt=JLP:GetModule("MiningSmeltingProgression")
        local advice=smelt and smelt:BuildMaterialAdvice(selected.skill)
        local parts={}
        local qualified,qualifiedIndex
        local unavailable={}
        for i,m in ipairs(advice and advice.materials or {}) do
            if not m.itemID then unavailable[#unavailable+1]=tostring(m.name).." x"..tostring(m.perSmelt or "?") end
            parts[#parts+1]=tostring(m.name).." x"..tostring(m.perSmelt or "?")..
                " per smelt · itemID "..(m.itemID and tostring(m.itemID) or "UNAVAILABLE")
            if m.itemID and not qualified then qualified,qualifiedIndex=m,i end
        end
        if not holder.smeltingStatus and type(JLP.UIWidgets.Label)=="function" then
            holder.smeltingStatus=JLP.UIWidgets:Label(holder,"", "GameFontHighlightSmall")
            if holder.smeltingStatus.SetWidth then holder.smeltingStatus:SetWidth(340) end
            if holder.smeltingStatus.SetHeight then holder.smeltingStatus:SetHeight(104) end
            if holder.smeltingStatus.SetJustifyH then holder.smeltingStatus:SetJustifyH("LEFT") end
        end
        if not holder.smeltingBank and type(JLP.UIWidgets.Button)=="function" then
            holder.smeltingBank=JLP.UIWidgets:Button(holder,"Inspect in Bank",140)
            holder.smeltingAH=JLP.UIWidgets:Button(holder,"Manual AH review",150)
            if holder.smeltingBank.SetHeight then holder.smeltingBank:SetHeight(24) end
            if holder.smeltingAH.SetHeight then holder.smeltingAH:SetHeight(24) end
            holder.smeltingBank:SetScript("OnClick",function()
                Page:InspectSmeltingMaterial("Bank",holder)
            end)
            holder.smeltingAH:SetScript("OnClick",function()
                Page:InspectSmeltingMaterial("Auction House",holder)
            end)
        end
        if not holder.smeltingManual and type(JLP.UIWidgets.Button)=="function" then
            holder.smeltingManual=JLP.UIWidgets:Button(holder,"Manual reagent search",200)
            holder.smeltingManual:SetHeight(24)
            holder.smeltingManual:SetScript("OnClick",function()
                if holder.smeltingStatus then
                    holder.smeltingStatus:SetText(holder.__smeltingManualText or
                        "Manual source information unavailable")
                end
            end)
        end
        holder.__smeltingManualText= "MANUAL ONLY · Search exact names yourself: "..
            (#unavailable>0 and table.concat(unavailable,"; ") or "No unqualified reagents")..
            ". Item IDs and item-level AH prices UNAVAILABLE. Recipe learned / forge / stock UNKNOWN."
        if holder.smeltingManual then
            holder.smeltingManual:SetShown(#unavailable>0)
            holder.smeltingManual:ClearAllPoints()
            holder.smeltingManual:SetPoint("TOPLEFT",0,-391)
        end
        if holder.smeltingStatus then
            holder.smeltingStatus:ClearAllPoints();holder.smeltingStatus:SetPoint("TOPLEFT",0,-242)
            holder.smeltingStatus:SetText(#parts>0 and
                ("SMELTING · per-craft source only: "..table.concat(parts,"; ")..
                ". Recipe learned / forge / reagent stock UNKNOWN. Manual decision.") or
                "SMELTING: "..tostring(advice and advice.state or "UNAVAILABLE")..
                " · no qualified reagent quantity; gather nodes manually.")
            holder.smeltingStatus:Show()
        end
        if qualified and qualifiedIndex and advice and advice.sourceURL then
            local owner=Page:MaterialOwnerSignature()
            holder.__smeltingSkill=selected.skill
            holder.__smeltingRecipe=advice.recipe
            holder.__smeltingMaterialIndex=qualifiedIndex
            holder.__smeltingOwner=owner
            holder.__smeltingReference={itemID=qualified.itemID,name=qualified.name,
                required=qualified.perSmelt,source="SMELTING:"..tostring(advice.sourceURL)..
                    ":"..tostring(qualified.identitySourceURL),bankKnown=false,
                readOnly=true,nativeDispatchAllowed=false,manualOnly=true}
        end
        for _,control in ipairs({holder.smeltingBank,holder.smeltingAH}) do
            if control then control:SetShown(qualified~=nil and Page:MaterialOwnerSignature()~="OWNER_UNKNOWN") end
        end
        if holder.smeltingBank then
            holder.smeltingBank:ClearAllPoints();holder.smeltingBank:SetPoint("TOPLEFT",0,-359)
            holder.smeltingAH:ClearAllPoints();holder.smeltingAH:SetPoint("TOPLEFT",154,-359)
        end
    else
        if holder.smeltingStatus then holder.smeltingStatus:Hide() end
        if holder.smeltingBank then holder.smeltingBank:Hide();holder.smeltingAH:Hide() end
        if holder.smeltingManual then holder.smeltingManual:Hide() end
    end
    holder.scroll:SetContentHeight(selected.key=="MINING" and 460 or 265,true)
    layoutSinglePlan(card,"gather",nil)
    return true
end

function Page:Refresh()
    -- A former Mining reference must not leave visible Bank/AH buttons after
    -- switching Guide mode, character or profession. UI state only.
    local selectedMode=self.mode
    if selectedMode~="MINING" and selectedMode~="mining" and self.frame then
        local function hide(holder)
            if holder then
                holder.__smeltingReference=nil
                if holder.smeltingBank then holder.smeltingBank:Hide() end
                if holder.smeltingAH then holder.smeltingAH:Hide() end
                if holder.smeltingStatus then holder.smeltingStatus:Hide() end
                if holder.smeltingManual then holder.smeltingManual:Hide() end
            end
        end
        hide(self.frame.single and self.frame.single.materials)
        hide(self.frame.dual and self.frame.dual.left)
        hide(self.frame.dual and self.frame.dual.right)
    end
    self.currentNavigationSource=nil
    self.__refreshCount=(self.__refreshCount or 0)+1
    if not self.frame then return end
    local ws=workspace()
    local pair=getPair()
    local resolved=ws and select(1,ws:ResolveGuideMode(self.mode)) or "onboarding"
    if resolved~=self.mode then self.mode=resolved; if JLP.DB and JLP.DB.profile then JLP.DB.profile.guideMode=resolved end end
    self.frame.dual:SetShown(resolved=="dual"); self.frame.single:SetShown(resolved~="dual")
    self:ApplyGuideLayout()
    if resolved=="dual" and #pair>=2 then
        setDualCard(self.frame.dual.left,pair[1]); setDualCard(self.frame.dual.right,pair[2])
        -- Append after the normal Guide sections; do not replace native readiness.
        renderReferencePreview(self.frame.dual.left,pair[1].key,pair[1].skill,self.frame.dual.left.scroll.__contentHeight)
        renderReferencePreview(self.frame.dual.right,pair[2].key,pair[2].skill,self.frame.dual.right.scroll.__contentHeight)
        return
    end
    if resolved=="onboarding" or resolved=="learn-second" then renderOnboarding(self.frame.single,resolved,pair); return end
    local selected=nil; for _,p in ipairs(pair) do if p.key==resolved then selected=p break end end
    if not selected then renderOnboarding(self.frame.single,#pair==1 and "learn-second" or "onboarding",pair); return end
    local s=self.frame.single; s.progress.icon:SetProfession(selected.key,selected); s.progress.heading:SetText((selected.name or "Profession").." 1-300"); s.progress.name:SetText(selected.name or "Profession"); s.progress.skill:SetText(string.format("Current skill: %d / %d",selected.skill or 0,selected.maxSkill or 300)); s.progress.bar:SetSkill(selected.skill or 0,selected.maxSkill or 300)
    setMaturityText(s.progress.maturity,selected.key)
    local gatherSummary=JLP:GetModule("GatheringSourceEvidenceSummary")
    if s.progress.gatheringEvidence and gatherSummary then
        s.progress.gatheringEvidence:SetText(selected.key=="SKINNING" and gatherSummary:SkinningLabel() or gatherSummary:Label())
    end
    if s.progress.skinningMaterials then s.progress.skinningMaterials:SetShown(selected.key=="SKINNING") end
    if s.progress.gatheringMap then s.progress.gatheringMap:SetShown(isGatheringProfession(selected.key)) end
    if s.progress.gatheringEvidence then s.progress.gatheringEvidence:SetShown(isGatheringProfession(selected.key)) end
    if selected.key=="HERBALISM" or selected.key=="MINING" then
        if renderGatheringSingle(s,selected) then return end
    end
    -- Restore crafting headings if the player switched professions.
    s.plan.stepLabel:SetText("CURRENT STEP")
    s.plan.readyLabel:SetText("READINESS & WORKSPACE")
    s.plan.upcomingLabel:SetText("STEP PROGRESSION")
    s.plan.gatheringGenerate:Hide()
    local planner=JLP:GetModule("Planner")
    local consumer,consumerState=nil,nil
    if allowResearchConsumer(selected.key) then consumer,consumerState=researchConsumerSnapshot(selected.key) end
    local revoked=consumerAuthorityRevoked(consumerState)
    local plan=consumer and consumer.plan or ((not revoked) and planner and planner:GetProfessionPlan(selected.key) or nil)
    local readOnly,authorityClass=isReadOnlyPlan(plan)
    local displayReadOnly=readOnly
    local readiness,queue,assist,flow,machine,workspace,nextBest,routeSession,travelSession,travelTransition,navigationGuidance,routeMarker,destinationHandoff,recovery,transactionRecovery,telemetryStatus,tracking
    local stepModel
    if consumer then
        readiness=consumer.readiness
        queue=consumer.actionQueue
        stepModel=consumer.guideSteps
    else
        readiness,queue,assist,flow,machine,workspace,nextBest,routeSession,travelSession,travelTransition,navigationGuidance,routeMarker,destinationHandoff,recovery,transactionRecovery,telemetryStatus,tracking=bundle(selected.key,plan)
        local guideSteps=JLP:GetModule("GuideSteps")
        stepModel=guideSteps and guideSteps:Build(selected.key,plan) or nil
    end
    local action=currentAction(queue)
    Page.currentAssist=assist
    local navigationAdapter=JLP:GetModule("IntegratedNavigationActions")
    local navigationSource,navigationSourceReason=nil,nil
    if navigationAdapter then
        navigationSource,navigationSourceReason=navigationAdapter:GuideSource(selected.key,plan,assist and assist.source)
    end
    Page.currentNavigationSource=navigationSource
    Page.currentNavigationSourceReason=navigationSourceReason
    Page.currentNavigationPlanRevision=plan and plan.revision or nil
    local inventory=JLP:GetModule("Inventory")
    Page.currentNavigationCharacterKey=inventory and inventory.GetCharacterKey and inventory:GetCharacterKey() or nil
    -- The same identity is used by auto-sync, button presentation and OnClick.
    -- It changes with step/plan revision, not with ordinary UI refreshes.
    local stepIdentity=plan and plan.step and (plan.step.recipeID or plan.step.spellID or plan.step.id) or "UNKNOWN"
    Page.currentNavigationContextToken="CURRENT_STEP:"..tostring(selected.key)..":"..
      tostring(plan and plan.revision or "UNKNOWN")..":"..tostring(stepIdentity)
    if selected.key=="LEATHERWORKING" or selected.key=="SKINNING" then
        Page.currentNavigationContextToken=Page.currentNavigationContextToken..":"..
            tostring(plan and plan.actionKind)..":"..tostring(navigationSource and navigationSource.serviceID or "NO_DESTINATION")
    end
    local context={planRevision=Page.currentNavigationPlanRevision,
      contextToken=Page.currentNavigationContextToken,characterKey=Page.currentNavigationCharacterKey}
    local unified=JLP:GetModule("UnifiedDestinationNavigation")
    if unified and unified.ObservePlanContext then unified:ObservePlanContext(context) end
    if unified and unified.SyncCurrentStep and Page.currentNavigationSource then
        local permitted=unified:CanNavigate("CURRENT_STEP",Page.currentNavigationSource,context)
        if permitted==true then unified:SyncCurrentStep(Page.currentNavigationSource,context) end
    end
    if self.frame and self.frame.single and self.frame.single.plan then
        local b=self.frame.single.plan.navButton
        local actions=JLP:GetModule("IntegratedNavigationActions")
        if b and actions then
          local clickContext={explicit=true,planRevision=context.planRevision,
             contextToken=context.contextToken,characterKey=context.characterKey,
             sourceIssue=Page.currentNavigationSourceReason}
          actions:Update(b,function(source)return actions:CategoryForSource(source)end,
              Page.currentNavigationSource,clickContext)
        end
    end
    local card=s.plan; card.__professionKey=selected.key; card.__plan=plan; card.__consumerSnapshot=consumer; card.__consumerAuthorityState=consumerState
    setResearchPreDispatchControl(card,consumer,plan)
    setResearchCraftAllControl(card,consumer,plan)
    setResearchRouteAutoControl(card,consumer,plan)
    local sequenceBoundary=card.__jlpSequenceBoundary
    local sequenceRestart=card.__jlpSequenceRestart
    local craftAllRestart=card.__jlpCraftAllRestart
    local craftAllResolution=(craftAllRestart and craftAllRestart.restartRequired and craftAllRestart.restartReady~=true) and currentCraftAllResolution(selected.key) or nil
    local craftAllHandoff=currentCraftAllHandoff(selected.key)
    card.__jlpCraftAllResolution=craftAllResolution
    card.__jlpCraftAllHandoff=craftAllHandoff
    if craftAllHandoff and craftAllHandoff.handoffKind=="MATERIALS" then setActionButtonEnabled(card.craftAll,false) end
    card.__professionState=machine
    card.mapButton:SetShown((not consumer) and (not displayReadOnly) and (not revoked) and assist and assist.canMap or false); card.ahButton:SetShown((not consumer) and (not displayReadOnly) and (not revoked) and assist and assist.canAH or false)
    if sequenceBoundary then card.badge:SetStatus("SEQUENCE STOP","gold") elseif sequenceRestart and sequenceRestart.restartReady then card.badge:SetStatus(sequenceRestart.contract=="production-auto-route-fresh-click-restart-planner-v1" and "AUTO ROUTE READY" or "BOUNDARY RESOLVED","good") elseif craftAllRestart and craftAllRestart.restartReady then card.badge:SetStatus("INTERRUPTION RESOLVED","good") elseif craftAllHandoff then local label,tone=craftAllHandoffBadge(craftAllHandoff); card.badge:SetStatus(label,tone) elseif craftAllResolution then local label,tone=craftAllResolutionBadge(craftAllResolution); if label then card.badge:SetStatus(label,tone) elseif consumer or displayReadOnly then card.badge:SetStatus(suppressReadOnlyPresentation(selected.key,authorityClass) and "CANDIDATE" or "READ-ONLY","gold") elseif revoked then card.badge:SetStatus("AUTHORITY REVOKED","bad") else card.badge:SetStatus(statusLabel(plan,readiness,machine),statusTone(plan,readiness,machine)) end elseif consumer or displayReadOnly then card.badge:SetStatus(suppressReadOnlyPresentation(selected.key,authorityClass) and "CANDIDATE" or "READ-ONLY","gold") elseif revoked then card.badge:SetStatus("AUTHORITY REVOKED","bad") else card.badge:SetStatus(statusLabel(plan,readiness,machine),statusTone(plan,readiness,machine)) end
    local F=JLP.UIContentFormat; local guideSteps=JLP:GetModule("GuideSteps")
    setReadinessRows(card.readinessRows,readiness,tracking,flow,machine,workspace,nextBest,routeSession,travelSession,travelTransition,navigationGuidance,routeMarker,destinationHandoff,recovery,transactionRecovery,telemetryStatus,selected.key)
    if consumer or displayReadOnly or revoked then hideContextCTA(card) else setContextCTA(card,nextBest,selected.key,false) end
    card.readiness:SetText(F and F:Readiness(readiness,tracking,flow) or "Readiness and workspace unavailable")
    local progression=F and F:StepProgression(stepModel) or (guideSteps and guideSteps:FormatCompact(stepModel) or "Route unavailable")
    -- Q115-F02-01: the current VERIFY step has no implied historical label.
    -- Only the provider's read-only route fallback warrants that wording.
    if selected.key=="TAILORING" and plan and plan.actionKind=="verify" and
        stepModel and stepModel.current and stepModel.current.currentActionKind=="verify" then
        local historical = stepModel.current.referenceOnly == true and
            stepModel.current.readOnlyRouteFallback == true
        progression=(historical and
            "NOW: VERIFY current Tailoring recipe/access (historical route is reference only)\n" or
            "NOW: VERIFY current Tailoring recipe/access\n")..progression
    end
    card.progression:SetText(progression); card.upcoming:SetText(progression)
    card.materialButton:SetShown((not consumer) and (not revoked) and plan and plan.actionKind=="craft" and plan.materials and #plan.materials>0 or false)
    card.nextAction:SetText(sequenceBoundary and tostring(sequenceBoundary.nextActionText or "Resolve the sequence boundary before continuing.") or (sequenceRestartText(sequenceRestart) or (craftAllRestartText(craftAllRestart) or ((craftAllHandoff and tostring(craftAllHandoff.nextActionText or "Craft All settled. Review the next verified action.")) or (craftAllResolutionText(craftAllResolution) or (revoked and revokedAuthorityText(consumerState) or (F and F:Action(action,plan,false) or tostring(action and action.text or "No pending action."))))))))

    local m=s.materials
    if m.qualityNote then m.qualityNote:Hide() end
    if plan and plan.actionKind=="craft" and plan.step then
        if consumer or displayReadOnly then
            setDirectControls(card,nil)
            card.targetSlot:SetTarget(nil)
            card.actionFeedback:Hide()
        elseif selected.key=="ENCHANTING" then
            setDirectControls(card,"enchant")
            local crafting=JLP:GetModule("Crafting"); local target=crafting and crafting:GetSelectedEnchantTarget(selected.key,plan) or nil
            card.targetSlot:SetTarget(target)
            setEnchantActionButton(card,selected.key,plan,readiness,target)
            setActionFeedback(card,selected.key,plan)
        else
            setDirectControls(card,"craft")
            setCraftActionButtons(card,selected.key,plan,readiness)
            setActionFeedback(card,selected.key,plan)
        end
        card.stepBlock:SetAction(JLP.UIIconResolver:GetRecipe(plan.step.recipe,selected.key),plan.step.craftInstruction or ("Craft "..tostring(plan.step.remainingCrafts or "?").." "..tostring(plan.step.recipe or "item")),(plan.step.p1OneCraft and "Manual casts; results observed separately" or string.format("Skill: %d / %d     Target: %d     Estimated: %d casts",selected.skill or 0,selected.maxSkill or 300,plan.step.skillTarget or 0,plan.step.remainingCrafts or 0)),nil,nil,plan.step.recipe)
        card.stepTitle:SetText(plan.step.craftInstruction or ("Craft "..tostring(plan.step.remainingCrafts or "?").." "..tostring(plan.step.recipe or "item"))); card.meta:SetText((plan.step.p1OneCraft and "Planned casts; recheck after each observed result" or string.format("Skill %d / %d | Target %d | Approx. %d casts remaining",selected.skill or 0,selected.maxSkill or 300,plan.step.skillTarget or 0,plan.step.remainingCrafts or 0))..recipeSkillEvidenceLabel(plan))
        local requirements=consumer and consumer.requirementPlan or requirementModel(selected.key,plan)
        if type(requirements)~="table" then requirements={materialTypes=0,rows={}} end
        card.nextBlock:SetAction(JLP.UIIconResolver:GetRecipe(plan.step.recipe,selected.key),(consumer or displayReadOnly) and ("Read-only material plan for "..tostring(plan.step.recipe or "current step")) or ("Prepare all materials for "..tostring(plan.step.recipe or "current step")),string.format("%d material type%s in the current step",requirements.materialTypes or 0,(requirements.materialTypes or 0)==1 and "" or "s"),nil,nil,plan.step.recipe)
        local explanation=JLP:GetModule("RequirementPlan")
        local function advisoryCall(service,method,...)
            if type(service)~="table" or type(service[method])~="function" then return nil end
            local ok,result=pcall(service[method],service,...)
            return ok and result or nil
        end
        if m.qualityNote then
            local qualification=advisoryCall(explanation,"FormatAvailability",requirements)
            local nextAction=advisoryCall(explanation,"NextSafeAction",requirements)
            local sourceSession=JLP:GetModule("AcquisitionSession")
            -- Qualify the visible selected step. A malformed advisory service
            -- can hide a quote, but cannot change native craft permissions.
            local currentRows=type(requirements.rows)=="table" and requirements.rows or {}
            local sourceModel=advisoryCall(sourceSession,"QualifySources",{requirements=currentRows})
            local quality=advisoryCall(sourceSession,"FormatSources",sourceModel)
            if type(qualification)~="string" then qualification="Material availability unverified" end
            if type(quality)~="string" then quality="Sources unavailable; verify manually" end
            local nextText=type(nextAction)=="table" and nextAction.text or nil
            if type(nextText)~="string" then nextText="Review sources manually" end
            local materialsCatalogue=JLP:GetModule("MaterialCatalog")
            local catalogueNotice=advisoryCall(materialsCatalogue,"GetCatalogueHealthNotice",selected.key)
            if type(catalogueNotice)=="string" and catalogueNotice~="" then
                quality=quality.." | "..catalogueNotice
            end
            m.qualityNote:SetText(qualification.." | "..nextText.." | "..quality)
            m.qualityNote:Show()
        end
        local rows=type(requirements.rows)=="table" and requirements.rows or {}
        ensureMaterialRows(m,#rows,true); layoutCraftMaterials(m,rows)
        card.__requirementModel=requirements
        m.sourceLabel:Show(); m.sourceRow:Show(); m.trainerLabel:Hide(); m.processLabel:Hide(); m.process1:Hide(); m.process2:Hide(); for _,r in ipairs(m.trainerRows) do r:Hide() end
        local src=plan.catalogueAcquisition or plan.step.sourceInfo
        local sourceText=src and (src.name or src.kind or "Profession trainer") or "Profession trainer"
        if plan.catalogueAcquisition then
            sourceText=sourceText.." (typed build-qualified reference; availability UNKNOWN)"
        end
        -- Same internal catalogue consumed by Planner; the display never
        -- grants learned-state or native readiness from a research name match.
        local evidence=plan.catalogueEvidence
        if not evidence then
            local catalogue=JLP:GetModule("ProfessionsDataCatalogue")
            if catalogue then
                local observedBuild=catalogue:GetObservedClientBuild()
                evidence=catalogue:ForPlanStep(selected.key,plan.step,observedBuild)
            end
        end
        if evidence then
            local label=evidence.state=="SOURCE_QUALIFIED" and "static source verified for build" or
                (evidence.observationState=="CLIENT_OBSERVED" and "observed in open client (read-only, not source-qualified)" or
                (evidence.identityState=="NAME_ONLY_RESEARCH" and "research name only" or "reference unqualified"))
            sourceText=sourceText.." | "..label
            local fields=plan.catalogueFieldReceipt and plan.catalogueFieldReceipt.fields
            if type(fields)=="table" then
                sourceText=sourceText.." | M2 ID:"..tostring(fields.identity or "UNKNOWN")..
                    " MAT:"..tostring(fields.reagents or "UNKNOWN")..
                    " OUT:"..tostring(fields.output or "UNKNOWN")..
                    " SKILL:"..tostring(fields.requiredSkill or "UNKNOWN")..
                    " SRC:"..tostring(fields.acquisition or "UNKNOWN")
            end
            local observedReagents=plan.catalogueClientObservedReagents
            if plan.catalogueEvidenceKind=="CLIENT_OBSERVED_SPELL_ID" and
                type(plan.catalogueClientObservedReagentReason)=="string" then
                -- A partial schematic is not zero reagents. Expose why live
                -- material quantities were withheld; do not change plan totals.
                sourceText=sourceText.." | client materials UNKNOWN ("..plan.catalogueClientObservedReagentReason..")"
            end
            if plan.catalogueEvidenceKind=="CLIENT_OBSERVED_SPELL_ID" and
                type(observedReagents)=="table" and #observedReagents>0 then
                -- Compact, strictly advisory live reagent info; no inferred
                -- bag ownership, missing counts, SOURCE_QUALIFIED or craft CTA.
                local parts={}
                for i=1,math.min(#observedReagents,3) do
                    local reagent=observedReagents[i]
                    if type(reagent)=="table" and type(reagent.itemID)=="number" and
                        type(reagent.perCraft)=="number" then
                        parts[#parts+1]=tostring(reagent.perCraft).."x item #"..tostring(reagent.itemID)
                    end
                end
                if #observedReagents>3 then parts[#parts+1]="more" end
                if #parts>0 then
                    sourceText=sourceText.." | client reagents per craft: "..table.concat(parts,", ")
                end
            end
            local comparison=evidence.clientReagentComparison
            if comparison and comparison.state=="CONFLICT" then
                sourceText=sourceText.." | live schematic differs from static reagents (review required)"
            elseif comparison and comparison.state=="MATCH" then
                sourceText=sourceText.." | reagent amounts corroborated by open client"
            end
        else
            sourceText=sourceText.." | catalogue: unqualified/unknown build or identity"
        end
        -- Private owner research sidecar: read-only; not native authority,
        -- not planner stock, crafting readiness or material totals.
        local privatePilot=plan.privateResearchAdvisory or plan.privateResearchPilot
        if privatePilot and privatePilot.state=="CONFLICT" then
            sourceText=sourceText.." | DQ01 CONFLICT: not actionable"
        elseif privatePilot and privatePilot.state=="CANDIDATE" then
            local count=plan.privateResearchAdvisory and privatePilot.rawReagentCount or
                (type(privatePilot.rawReagentSlots)=="table" and #privatePilot.rawReagentSlots or 0)
            sourceText=sourceText.." | DQ01 PARTIAL: "..(count>0 and
                (tostring(count).." raw reagent identities") or "reagents UNKNOWN")..
                "; quantities/yield/difficulty/actor/Horde/totals UNKNOWN"
            if privatePilot.buildState=="CONFLICT" then
                sourceText=sourceText.." | owner data build differs from observed client"
            elseif privatePilot.buildState=="UNKNOWN" then
                sourceText=sourceText.." | client build UNKNOWN"
            end
        end
        -- An observed current-build recipe may have richer *read-only*
        -- material and source data. Its source links are not stock/route
        -- entitlements and cannot change the Planner's material totals.
        local refSpell=tonumber(plan.step and (plan.step.spellID or plan.step.recipeID))
        if refSpell and refSpell>0 then
            local reference=JLP:GetModule("MaterialsSources70450")
            local snapshot=reference and reference.GetSummary and
                reference:GetSummary(selected.key,refSpell,1,70450)
            if snapshot then
                sourceText=sourceText.." | 70450: "..tostring(snapshot.materialState)..
                    ", "..tostring(snapshot.materialTypes).." item types; "..
                    tostring(snapshot.sourceStatus)..
                    (function()
                        local fragments={}
                        for _,v in ipairs(snapshot.publicVendorReferences or
                            (snapshot.publicVendorReference and {snapshot.publicVendorReference} or {})) do
                            fragments[#fragments+1]="; "..tostring(v.factionReference or "UNKNOWN")..
                                " public vendor "..tostring(v.npcName).." #"..tostring(v.npcID)..
                                ", teaching item #"..tostring(v.teachingItemID)..
                                " (NOT live stock)"
                        end
                        for _,q in ipairs(snapshot.publicQuestReferences or {}) do
                            fragments[#fragments+1]="; "..tostring(q.factionReference)..
                                " public quest #"..tostring(q.questID)..
                                ", reward item #"..tostring(q.teachingItemID)..
                                ", NPC "..tostring(q.npcName).." #"..tostring(q.npcID)..
                                " (completion/availability UNKNOWN)"
                        end
                        return table.concat(fragments)
                    end)()..
                    (snapshot.requiredSpellFocusName and
                        ("; station "..tostring(snapshot.requiredSpellFocusName).." (client reference)")
                        or "").."; native authority unchanged"
            end
        end
        m.sourceRow:SetRow("recipe","Recipe source",sourceText,"cyan")
        -- The value has just changed; measure and layout *after* assignment.
        layoutCraftMaterials(m,rows)
    elseif plan and plan.actionKind=="train" then
        setDirectControls(card,nil); if consumer or displayReadOnly or revoked then card.actionFeedback:Hide() else setActionFeedback(card,selected.key,plan) end
        card.targetSlot:SetTarget(nil)
        card.__requirementModel=nil
        local gate=plan.step and plan.step.trainer; local src=plan.step and plan.step.sourceInfo; local name,area,zone,coord=sourceParts(src,selected.key,gate)
        card.stepBlock:SetAction(JLP.UIIconResolver:GetProfession(selected.key,selected),"Profession rank training",string.format("Skill: %d / %d     Unlock cap: %d",selected.skill or 0,selected.maxSkill or 0,gate and gate.nextCap or 300),"text")
        card.stepTitle:SetText("Profession rank training"); card.meta:SetText(string.format("Skill %d / %d | Unlock cap %d",selected.skill or 0,selected.maxSkill or 0,gate and gate.nextCap or 300))
        local nextTitle,nextMeta=actionDisplay(action,plan)
        card.nextBlock:SetAction(JLP.UIIconResolver:GetProfession(selected.key,selected),nextTitle,(nextMeta~="" and (nextMeta.."   ") or "").."Trainer: "..name.." | "..zone.." | "..coord)
        for _,w in ipairs(m.materialRows) do w:Hide() end; m.sourceLabel:Hide(); m.sourceRow:Hide(); m.trainerLabel:Show(); m.processLabel:Show(); m.process1:Show(); m.process2:Show()
        m.trainerRows[1]:Show(); m.trainerRows[1]:SetRow("trainer","Trainer",name,"cyan")
        m.trainerRows[2]:Show(); m.trainerRows[2]:SetRow("area","Area",area)
        m.trainerRows[3]:Show(); m.trainerRows[3]:SetRow("zone","Zone",zone)
        m.trainerRows[4]:Show(); m.trainerRows[4]:SetRow("coordinates","Coordinates",coord,"cyan")
        m.process1:SetBlock("process","","Complete this rank training before the next crafting segment can begin.","gold")
        m.process2:SetBlock("workspace","","The guide advances automatically when the new skill cap is registered.","gold")
        layoutGuideTrainerMaterials(m)
    elseif plan then
        setDirectControls(card,nil); if consumer or displayReadOnly or revoked then card.actionFeedback:Hide() else setActionFeedback(card,selected.key,plan) end
        card.targetSlot:SetTarget(nil)
        card.__requirementModel=nil
        card.stepBlock:SetAction(JLP.UIIconResolver:GetProfession(selected.key,selected),plan.action or "No profession action available.","")
        card.stepTitle:SetText(plan.action or "No profession action available."); card.meta:SetText(recipeSkillEvidenceLabel(plan)); card.nextBlock:SetAction(JLP.UIIconResolver:GetProfession(selected.key,selected),
            (plan.p1Prerequisite and plan.p1Prerequisite.text) or
            (plan.actionKind=="reference" and "Read-only profession reference" or (action and action.text or "No pending action")),
            planner:EnsureReferenceSnapshot(plan) and plan.referenceSnapshot.currentSourceBuild and
            ("Client DB2 build "..tostring(plan.referenceSnapshot.currentSourceBuild)..
                " · "..tostring(plan.referenceSnapshot.current and plan.referenceSnapshot.current.recipeCandidates or "?")..
                " recipe candidates; not native approval") or "")
        for _,w in ipairs(m.materialRows) do w:Hide() end; m.sourceLabel:Hide(); m.sourceRow:Hide(); m.trainerLabel:Hide(); m.processLabel:Hide(); m.process1:Hide(); m.process2:Hide(); for _,r in ipairs(m.trainerRows) do r:Hide() end
        m.scroll:SetContentHeight(1,true)
    else
        setDirectControls(card,nil); if consumer or displayReadOnly or revoked then card.actionFeedback:Hide() else setActionFeedback(card,selected.key,plan) end
        card.targetSlot:SetTarget(nil)
        local inactiveTitle=revoked and "Research authority revoked" or "Planner unavailable"
        card.stepBlock:SetAction(JLP.UIIconResolver:GetProfession(selected.key,selected),inactiveTitle,revoked and "Current-build authority must be revalidated before this route can be consumed again." or ""); card.stepTitle:SetText(inactiveTitle); card.nextBlock:SetAction(JLP.UIIconResolver:GetProfession(selected.key,selected),revoked and "Re-establish current-build research authority" or "No profession plan is available.",revoked and tostring(consumerState and consumerState.sourceAuthorityState or "") or ""); m.scroll:SetContentHeight(1,true)
    end
    layoutSinglePlan(card,(plan and plan.actionKind=="craft") and "craft" or "other",card.__requirementModel)
    -- A rank-training gate has no active crafting/material step.  The former
    -- unconditional preview put its navigation/button fragments BELOW the
    -- trainer PROCESS rows, where they were clipped at the card's bottom.
    -- Return the complete trainer view without leftover reference controls.
    if plan and plan.actionKind=="train" then
        hideReferencePreview(m)
    else
        renderReferencePreview(m,selected.key,selected.skill,m.scroll.__contentHeight)
    end
end

JLP.UIPages=JLP.UIPages or {}
JLP.UIPages[Page.name]=Page
