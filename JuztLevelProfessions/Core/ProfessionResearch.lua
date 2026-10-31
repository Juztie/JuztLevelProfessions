local _, JLP = ...
local ProfessionResearch = {
    contract = "source-provenance-profession-route-research-v1",
    policy = {productStrategyMapping={normal="Economical",aggressive="Fastest"},
        elapsedTimeRankingVerified=false,sourcePriority="FOREVER_DIRECT_REAGENTS_FIRST"},
}

local ORDER = {"ALCHEMY","BLACKSMITHING","ENCHANTING","ENGINEERING","LEATHERWORKING","TAILORING"}

function ProfessionResearch:GetRaw(professionKey, mode)
    local root = JLP.data and JLP.data.professionResearchRoutes
    local profession = root and root.professions and root.professions[professionKey]
    if not profession then return nil end
    mode = (mode == "aggressive" or mode == "fastest") and "aggressive" or "normal"
    return profession[mode]
end

function ProfessionResearch:Get(professionKey, mode)
    local priority=JLP:GetModule("ForeverRecipeAuthority")
    if priority then
        local route=priority:GetEffectiveRoute(professionKey,mode)
        if route then return route end
    end
    return self:GetRaw(professionKey,mode)
end

-- Source-qualified 8799 conflict gate. The original Word record has NO
-- recipe ID; resolve identity via the existing 70009 Tailoring dataset, then
-- require an exact reagent-ID and per-craft-quantity agreement with the
-- independent 70245 Forever evidence. Never touch protected datasets or
-- imply verified 70009 native crafting access.
local function tailoring8799Evidence(key,step)
    if key~="TAILORING" or step.recipe~="Crimson Silk Pantaloons" then return nil end
    local tailoring=JLP.data and JLP.data.tailoring
    local ev=JLP.data and JLP.data.currentBuildEvidence
    local entry=ev and ev.professions and ev.professions.TAILORING
    local identity=tailoring and tailoring.recipeIdentities and tailoring.recipeIdentities[step.recipe]
    if not identity or identity.recipeID~=8799 or not entry or
        entry.validationBasis~="WOWHEAD_FOREVER" or entry.build~=ev.targetBuild then return nil end
    local byID={}
    for _,material in pairs(tailoring.materials or {}) do
        if type(material.itemID)=="number" then byID[material.itemID]=material.name end
    end
    local direct
    for _,row in ipairs(tailoring.route or {}) do
        if row.recipeID==8799 and row.recipe==step.recipe then direct=row;break end
    end
    if not direct then return nil end
    local actual={}
    for _,material in ipairs(direct.materials or {}) do actual[material.itemID]=material.quantity end
    for _,row in ipairs(entry.rows or {}) do
        if row.recipeID==8799 and row.note==step.recipe and row.sourceKey=="wowheadTailoring" then
            local count=0
            for _,material in ipairs(row.materials or {}) do
                if type(material[1])~="number" or type(material[2])~="number" or
                    actual[material[1]]~=material[2] or not byID[material[1]] then return nil end
                count=count+1
            end
            if count~=#(direct.materials or {}) then return nil end
            local verified={recipeID=8799,sourceURL="https://www.wowhead.com/forever/spell=8799/crimson-silk-pantaloons",
                sourceBuild=entry.build,reagents={}}
            for _,mat in ipairs(row.materials) do
                verified.reagents[#verified.reagents+1]={itemID=mat[1],name=byID[mat[1]],quantity=mat[2]}
            end
            return verified
        end
    end
    return nil
end
-- Bounded, transient presentation of the TWO source guide strategies. All
-- materials are guide-level estimates; a (keep) output is never double counted
-- as guaranteed inventory. Recipe IDs absent from the direct Forever catalogue
-- remain UNKNOWN and cannot produce an exact item focus.
function ProfessionResearch:BuildSourcePlan(key,strategy,fromSkill,toSkill)
    local mode=(strategy=="aggressive" or strategy=="fastest") and "aggressive" or "normal"
    local route=self:GetRaw(key,mode)
    if not route then return nil,"SOURCE_UNAVAILABLE" end
    if fromSkill~=nil and (type(fromSkill)~="number" or fromSkill~=fromSkill or fromSkill<0 or
        fromSkill==math.huge or fromSkill==-math.huge) then return nil,"SKILL_INVALID" end
    if toSkill~=nil and (type(toSkill)~="number" or toSkill~=toSkill or toSkill<0 or
        toSkill==math.huge or toSkill==-math.huge) then return nil,"SKILL_INVALID" end
    fromSkill=fromSkill or 0;toSkill=toSkill or 300
    if toSkill<fromSkill then return nil,"SKILL_RANGE_INVALID" end
    local report={profession=key,sourceMode=mode,
        strategy=mode=="aggressive" and "Fastest" or "Economical",
        strategyTimeVerified=false,sourceDocument="Horde Profession Infomation v2.docx",
        sourceAuthority="USER_RESEARCH_ADVISORY_ONLY",nativeDispatchAllowed=false,
        expectedCraftsAuthority="HISTORICAL_GUIDE_ESTIMATE",steps={},
        materialTotals={},historicalMaterialTotals={},qualifiedMaterialTotals={},sourceConflicts={},keepOutputs={},sourceGaps={},invalidSteps=0,
        sourceSteps=0,qualification="RESEARCH_ONLY"}
    for _,step in ipairs(route.steps or {}) do
        if step.kind=="craft" and type(step.skillMin)=="number" and
            type(step.skillTarget)=="number" and step.skillMin<toSkill and step.skillTarget>fromSkill then
            local crafts=step.expectedCrafts
            if type(crafts)~="number" or crafts~=crafts or crafts<=0 or
                crafts==math.huge or crafts~=math.floor(crafts) then
                report.invalidSteps=report.invalidSteps+1
            else
                local row={skillMin=step.skillMin,skillTarget=step.skillTarget,
                    name=step.recipe,recipeID=step.recipeID,sourceEvidence=step.evidence,
                    sourceMode=mode,estimatedCrafts=crafts,craftsGuaranteed=false,
                    estimatedFromGuide=step.estimated==true,keep=step.keep==true,
                    ingredients={},recipeQualification="RESEARCH_ONLY",
                    sourceRequirement=step.sourceRequirement,nativeDispatchAllowed=false}
                local good=true
                for _,material in ipairs(step.requirements or {}) do
                    local q=material.quantity
                    if type(material.name)~="string" or type(q)~="number" or
                        q<0 or q~=q or q==math.huge or q~=math.floor(q) then good=false;break end
                    row.ingredients[#row.ingredients+1]={name=material.name,
                        guideGross=q,perCraft=(q%crafts==0) and q/crafts or nil,
                        quantityAuthority="HISTORICAL_GUIDE_ESTIMATE",itemID=nil}
                end
                if good then
                    local authority=JLP:GetModule("ForeverRecipeAuthority")
                    local verified=authority and type(authority.GetReference)=="function" and
                        authority:GetReference(key,step.recipeID,step.recipe)
                    if type(verified)~="table" then
                        verified=tailoring8799Evidence(key,step)
                    end
                    if type(verified)=="table" then
                        row.recipeID=verified.recipeID
                        row.recipeQualification="FOREVER_REFERENCE_VERIFIED"
                        row.recipeSourceURL=verified.sourceURL
                        -- Never rewrite the historical Word data. The effective
                        -- acquisition basis is ALWAYS the direct Forever reagent set
                        -- when its recipe identity/source are qualified. An invalid
                        -- historical ingredient may be recorded as a conflict only.
                        row.historicalIngredients=row.ingredients
                        row.verifiedReagents={}
                        for _,reagent in ipairs(verified.reagents or {}) do
                            row.verifiedReagents[#row.verifiedReagents+1]={itemID=reagent.itemID,
                                name=reagent.name,perCraft=reagent.quantity,
                                guideGrossEstimate=reagent.quantity*crafts,
                                sourceURL=verified.sourceURL,nativeDispatchAllowed=false}
                        end
                        local historical, direct={},{}
                        for _,material in ipairs(row.historicalIngredients) do
                            historical[material.name]=(historical[material.name] or 0)+material.guideGross
                        end
                        for _,material in ipairs(row.verifiedReagents) do
                            direct[material.name]=(direct[material.name] or 0)+material.guideGrossEstimate
                        end
                        local conflict=false
                        for name,total in pairs(historical) do if direct[name]~=total then conflict=true end end
                        for name,total in pairs(direct) do if historical[name]~=total then conflict=true end end
                        row.sourceConflict=conflict and "DIRECT_FOREVER_REAGENTS_OVERRIDE_HISTORICAL" or nil
                        row.effectiveMaterialAuthority="FOREVER_VERIFIED_PER_CRAFT_GUIDE_ESTIMATED_CRAFTS"
                        row.ingredients={}
                        for _,material in ipairs(row.verifiedReagents) do
                            row.ingredients[#row.ingredients+1]={itemID=material.itemID,name=material.name,
                                perCraft=material.perCraft,guideGross=material.guideGrossEstimate,
                                quantityAuthority=row.effectiveMaterialAuthority,
                                sourceURL=material.sourceURL}
                        end
                        if conflict then
                            report.sourceConflicts[#report.sourceConflicts+1]={recipeID=row.recipeID,
                                recipe=row.name,skillMin=row.skillMin,sourceMode=mode,
                                status=row.sourceConflict,rawSource="Horde Profession Infomation v2.docx",
                                effectiveSource=verified.sourceURL}
                        end
                    end
                    report.steps[#report.steps+1]=row
                    report.sourceSteps=report.sourceSteps+1
                    for _,material in ipairs(row.historicalIngredients or row.ingredients) do
                        report.historicalMaterialTotals[material.name]=(report.historicalMaterialTotals[material.name] or 0)+material.guideGross
                    end
                    for _,material in ipairs(row.ingredients) do
                        report.materialTotals[material.name]=(report.materialTotals[material.name] or 0)+material.guideGross
                        if row.recipeQualification=="FOREVER_REFERENCE_VERIFIED" then
                            report.qualifiedMaterialTotals[material.name]=(report.qualifiedMaterialTotals[material.name] or 0)+material.guideGross
                        end
                    end
                    if row.keep then
                        report.keepOutputs[#report.keepOutputs+1]={name=row.name,
                            expectedCrafts=crafts,inventoryCreditQualified=false,
                            status="KEEP_INTERMEDIATE_NOT_CONFIRMED_STOCK"}
                    end
                else report.invalidSteps=report.invalidSteps+1 end
            end
        end
    end
    -- A guide's (keep) output has NOT been verified as produced. Suppressing
    -- these from the raw consumption total would create a false buying plan.
    report.netPurchaseAmountsQualified=false
    report.materialTotalsStatus="MIXED_REFERENCE_VERIFIED_AND_RESEARCH_ONLY_NOT_EXACT_SHOPPING_LIST"
    for _,gap in ipairs(route.stats and route.stats.gaps or {}) do
        report.sourceGaps[#report.sourceGaps+1]={fromSkill=gap.fromSkill,toSkill=gap.toSkill,
            status="SOURCE_GAP_NO_SYNTHETIC_BRIDGE"}
    end
    return report
end

-- Small, bounded in-game research readout for all six Horde crafting routes.
-- Never describes research-only recipe names as verified item IDs or live stock.
function ProfessionResearch:DescribeSourceStep(key,strategy,skill)
    local plan,reason=self:BuildSourcePlan(key,strategy,0,300)
    if not plan then return "Source plan unavailable: "..tostring(reason) end
    if type(skill)~="number" or skill~=skill or skill<0 or
        skill==math.huge or skill==-math.huge then
        return "Source skill invalid; enter 1–300." end
    local selected
    for _,step in ipairs(plan.steps) do
        if skill>=step.skillMin and skill<step.skillTarget then selected=step;break end
    end
    if not selected then
        return plan.strategy.." · "..key.." · SOURCE_UNAVAILABLE at skill "..
            tostring(skill)..". Source gaps must not be filled synthetically."
    end
    local lines={plan.strategy.." ["..(plan.sourceMode=="normal" and "Normal" or "Aggressive")..
        " source] · "..key.." "..selected.skillMin.."–"..selected.skillTarget,
        tostring(selected.name).." · estimated crafts "..selected.estimatedCrafts..
        " · "..selected.recipeQualification,
        "Research only. Fastest elapsed time UNKNOWN. Gross/missing are conditional."}
    if selected.sourceConflict then lines[#lines+1]="SOURCE CONFLICT: direct Forever recipe reagents override historical guide materials; raw document retained." end
    local rows=selected.verifiedReagents or selected.ingredients or {}
    for i=1,math.min(#rows,4) do
        local row=rows[i]
        lines[#lines+1]=tostring(row.name).." · "..
            tostring(row.perCraft and (row.perCraft.." per craft") or "per-craft UNKNOWN")..
            " · gross ~"..tostring(row.guideGrossEstimate or row.guideGross or "UNKNOWN")
    end
    if selected.keep then lines[#lines+1]="KEEP output for future steps; not confirmed inventory" end
    if #rows>4 then lines[#lines+1]="...additional materials in source guide" end
    lines[#lines+1]="No automated crafting, Bank withdrawal or AH purchase."
    return table.concat(lines,"\n")
end

function ProfessionResearch:Validate()
    local root = JLP.data and JLP.data.professionResearchRoutes
    local errors, warnings = {}, {}
    if not root or root.contract ~= "profession-research-route-catalogue-v1" then
        errors[#errors + 1] = "research route catalogue unavailable"
        return errors, warnings
    end
    for _, key in ipairs(ORDER) do
        local modes = root.professions and root.professions[key]
        if not modes then
            errors[#errors + 1] = key .. ": missing profession catalogue"
        else
            for _, mode in ipairs({"normal","aggressive"}) do
                local route = modes[mode]
                if not route or type(route.steps) ~= "table" then
                    errors[#errors + 1] = key .. "/" .. mode .. ": missing route"
                else
                    local trainerSteps = 0
                    for _, step in ipairs(route.steps) do
                        if step.kind == "train" then trainerSteps = trainerSteps + 1 end
                        if step.evidence ~= root.evidence then
                            errors[#errors + 1] = key .. "/" .. mode .. ": provenance mismatch"
                            break
                        end
                    end
                    if trainerSteps ~= 3 then errors[#errors + 1] = key .. "/" .. mode .. ": expected 3 rank gates" end
                    for _, gap in ipairs(route.stats and route.stats.gaps or {}) do
                        warnings[#warnings + 1] = string.format("%s/%s source gap %d-%d preserved", key, mode, tonumber(gap.fromSkill) or 0, tonumber(gap.toSkill) or 0)
                    end
                end
            end
        end
    end
    return errors, warnings
end

function ProfessionResearch:GetSummary()
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not root then return "Profession research catalogue unavailable." end
    local lines = {
        "Profession research: " .. tostring(root.sourceMetadata and root.sourceMetadata.source or "unknown source"),
        "Authority: research-reference-only; does not replace audited Planner routes",
    }
    for _, key in ipairs(ORDER) do
        local modes = root.professions and root.professions[key]
        local n, a = modes and modes.normal, modes and modes.aggressive
        lines[#lines + 1] = string.format(
            "%s · normal %d craft steps · aggressive %d craft steps · gaps %d/%d",
            key,
            tonumber(n and n.stats and n.stats.craftSteps) or 0,
            tonumber(a and a.stats and a.stats.craftSteps) or 0,
            #(n and n.stats and n.stats.gaps or {}),
            #(a and a.stats and a.stats.gaps or {})
        )
    end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ProfessionResearch", ProfessionResearch)
