local _, JLP = ...
-- Public evidence and historical strategies are separate proof domains.
-- A drifted research route does not invalidate the published Forever recipe.
local Service={contract="public-crafting-route-comparison-v3",nativeDispatchAllowed=false,persisted=false}
local function catalogue() return JLP.data and JLP.data.publicCraftingRouteEvidence end
local function research() return JLP.data and JLP.data.professionResearchRoutes end
local function strategyName(name) if name=="aggressive" or name=="AGGRESSIVE" then return "aggressive" end return "normal" end
local function findStep(key,name,strategy)
    local entry=research() and research().professions and research().professions[key]
    for _,step in ipairs(entry and entry[strategy] and entry[strategy].steps or {}) do
        if step.kind=="craft" and step.recipe==name then return step end
    end
end
local function matchResearch(key,row,strategy)
    local step=findStep(key,row.name,strategy)
    if not step then return {status="PUBLIC_ALTERNATIVE",issues={"absent-from-"..strategy.."-research-route"},step=nil} end
    local problems={}
    local crafts=tonumber(step.expectedCrafts)
    if not crafts or crafts<=0 then problems[#problems+1]="invalid-expected-crafts" end
    local totals={}
    for _,m in ipairs(step.requirements or {}) do totals[m.name]=(totals[m.name] or 0)+(tonumber(m.quantity) or 0) end
    local expected={}
    for _,m in ipairs(row.reagents or {}) do
        expected[m.name]=(expected[m.name] or 0)+(tonumber(m.quantity) or 0)
    end
    for name,perCraft in pairs(expected) do
        if not crafts or totals[name]~=crafts*perCraft then problems[#problems+1]="reagent-total-mismatch:"..name end
    end
    for name in pairs(totals) do if not expected[name] then problems[#problems+1]="research-extra-reagent:"..name end end
    table.sort(problems)
    return {status=#problems==0 and "RESEARCH_MATERIAL_MATCH" or "RESEARCH_MATERIAL_DRIFT",issues=problems,
        step=step,expectedCrafts=crafts,skillMin=step.skillMin,skillTarget=step.skillTarget,estimated=step.estimated}
end
function Service:Audit(key)
    local reg=JLP:GetModule("ProfessionRegistry")
    key=tostring(key or ""):upper()
    local def=reg and reg:Get(key)
    local catalog=catalogue()
    local data=def and catalog and catalog.professions[key]
    if not data then return nil,"PUBLIC_CRAFT_ROUTE_UNAVAILABLE" end
    if tonumber(data.skillLineID)~=tonumber(def.skillLineID) then return nil,"PROFESSION_SKILL_ID_MISMATCH" end
    local report={professionKey=key,sourceBuild=catalog.build,recipes={},verifiedCount=0,researchMatchCount=0,
        researchDriftCount=0,alternativesCount=0,aggressiveMatchCount=0,aggressiveDriftCount=0,
        aggressiveAlternativesCount=0,completeRoute=false,production=false,nativeDispatchAllowed=false}
    local ids={}
    for _,row in ipairs(data.recipes or {}) do
        local issues={}
        if not tonumber(row.recipeID) or row.recipeID<=0 or ids[row.recipeID] then issues[#issues+1]="invalid-or-duplicate-recipe-id" end
        ids[row.recipeID]=true
        if row.sourceURL~="https://www.wowhead.com/forever/spell="..tostring(row.recipeID) then issues[#issues+1]="source-id-link-mismatch" end
        if tonumber(row.sourceBuild)~=tonumber(catalog.build) then issues[#issues+1]="reference-build-mismatch" end
        if type(row.reagents)~="table" or #row.reagents==0 then issues[#issues+1]="no-reagents" end
        local evidence=JLP.data and JLP.data.currentBuildEvidence
        if evidence and evidence.professions and evidence.professions[key] then
            local source=JLP:GetModule("ForeverRecipeAuthority")
            local corroborated=source and source:GetReference(key,row.recipeID)
            if not corroborated then issues[#issues+1]="invalid-or-drifted-reference-evidence" end
        end
        local reagentIDs={}
        for _,mat in ipairs(row.reagents or {}) do
            if not tonumber(mat.itemID) or mat.itemID<=0 or not tonumber(mat.quantity) or mat.quantity<=0 then issues[#issues+1]="invalid-reagent" end
            if reagentIDs[mat.itemID] then issues[#issues+1]="duplicate-reagent-id" end
            reagentIDs[mat.itemID]=true
        end
        local normal=matchResearch(key,row,"normal")
        local aggressive=matchResearch(key,row,"aggressive")
        local accepted=#issues==0
        local out={recipeID=row.recipeID,name=row.name,sourceURL=row.sourceURL,requiredSkill=row.requiredSkill,
            skillBasis=row.skillBasis,reagents=row.reagents,tools=row.tools,outputPerCraft=row.outputPerCraft,
            status=normal.status,issues=issues,accepted=accepted,
            normal=normal,aggressive=aggressive,
            researchSkillMin=normal.skillMin,researchSkillTarget=normal.skillTarget,
            researchExpectedCrafts=normal.expectedCrafts}
        report.recipes[#report.recipes+1]=out
        if accepted then report.verifiedCount=report.verifiedCount+1 end
        if normal.status=="RESEARCH_MATERIAL_MATCH" then report.researchMatchCount=report.researchMatchCount+1 end
        if normal.status=="RESEARCH_MATERIAL_DRIFT" then report.researchDriftCount=report.researchDriftCount+1 end
        if normal.status=="PUBLIC_ALTERNATIVE" then report.alternativesCount=report.alternativesCount+1 end
        if aggressive.status=="RESEARCH_MATERIAL_MATCH" then report.aggressiveMatchCount=report.aggressiveMatchCount+1 end
        if aggressive.status=="RESEARCH_MATERIAL_DRIFT" then report.aggressiveDriftCount=report.aggressiveDriftCount+1 end
        if aggressive.status=="PUBLIC_ALTERNATIVE" then report.aggressiveAlternativesCount=report.aggressiveAlternativesCount+1 end
    end
    return report
end
function Service:GetCandidates(key,skill,strategy)
    local audit,err=self:Audit(key)
    if not audit then return nil,err end
    local result={}
    skill=tonumber(skill)
    if not skill then return result end
    strategy=strategyName(strategy)
    for _,row in ipairs(audit.recipes) do
        local plan=row[strategy]
        if row.accepted and plan.step and plan.skillMin and plan.skillTarget
           and skill>=plan.skillMin and skill<plan.skillTarget
           and (row.requiredSkill==nil or skill>=row.requiredSkill) then result[#result+1]=row end
    end
    return result
end
-- Pricing is deliberately incomplete unless EVERY directly required item has an input unit price.
-- A research expectedCrafts estimate cannot be sold as expected skill-ups or an optimal strategy.
function Service:GetCostComparison(key,prices)
    local audit,err=self:Audit(key)
    if not audit then return nil,err end
    prices=type(prices)=="table" and prices or {}
    local result={professionKey=key,strategies={},basis="ESTIMATED_RESEARCH_CRAFT_COUNTS",optimalRouteProven=false}
    for _,strategy in ipairs({"normal","aggressive"}) do
        local entry={strategy=strategy,coveredSteps=0,knownCost=0,missingPriceItemIDs={},materialDrifts=0,
            unsupportedSteps=0,complete=false,expectedSkillUpProbability="UNKNOWN"}
        local seen={}
        local route=research() and research().professions and research().professions[key]
        for _,step in ipairs(route and route[strategy] and route[strategy].steps or {}) do
            if step.kind=="craft" then
                local matched
                for _,row in ipairs(audit.recipes) do if row.name==step.recipe then matched=row break end end
                if not matched or not matched.accepted then entry.unsupportedSteps=entry.unsupportedSteps+1
                else
                    if matched[strategy].status=="RESEARCH_MATERIAL_DRIFT" then entry.materialDrifts=entry.materialDrifts+1 end
                    entry.coveredSteps=entry.coveredSteps+1
                    for _,mat in ipairs(matched.reagents) do
                        local unit=tonumber(prices[mat.itemID])
                        if not unit or unit<0 then
                            if not seen[mat.itemID] then entry.missingPriceItemIDs[#entry.missingPriceItemIDs+1]=mat.itemID;seen[mat.itemID]=true end
                        else entry.knownCost=entry.knownCost+unit*mat.quantity*step.expectedCrafts end
                    end
                end
            end
        end
        table.sort(entry.missingPriceItemIDs)
        entry.complete=entry.unsupportedSteps==0 and #entry.missingPriceItemIDs==0
        entry.cost=entry.complete and entry.knownCost or nil
        result.strategies[strategy]=entry
    end
    return result
end
function Service:GetSummary(key)
    if not key or key=="" then return "Public crafting evidence: ALCHEMY, BLACKSMITHING, ENGINEERING, LEATHERWORKING · /jlp routecompare PROFESSION" end
    local report,err=self:Audit(key)
    if not report then return "Public craft comparison: "..tostring(err) end
    local lines={report.professionKey.." · "..report.verifiedCount.."/"..#report.recipes.." public ID/material rows",
        "Normal match "..report.researchMatchCount.." · drift "..report.researchDriftCount.." · alternatives "..report.alternativesCount,
        "Aggressive match "..report.aggressiveMatchCount.." · drift "..report.aggressiveDriftCount.." · alternatives "..report.aggressiveAlternativesCount}
    for _,row in ipairs(report.recipes) do
        lines[#lines+1]=row.name.." (#"..row.recipeID..") · public "..(row.accepted and "REFERENCE_VALID" or "INVALID")..
            " · Normal "..row.normal.status.." · Aggressive "..row.aggressive.status
    end
    lines[#lines+1]="Reference materials are independent of historical research · skill-up chance and AH prices unknown · no native authority"
    return table.concat(lines,"\n")
end
function Service:Validate()
    local problems={}
    for _,key in ipairs({"ALCHEMY","BLACKSMITHING","ENGINEERING","LEATHERWORKING"}) do
        local report,err=self:Audit(key)
        if not report then problems[#problems+1]=key..":"..tostring(err)
        else for _,row in ipairs(report.recipes) do
            if not row.accepted then problems[#problems+1]=key..":"..row.recipeID..":"..table.concat(row.issues,",") end
        end end
    end
    return problems
end
JLP:RegisterModule("PublicCraftingRouteComparison",Service)
