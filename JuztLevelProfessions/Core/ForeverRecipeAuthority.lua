local _, JLP = ...
-- WOWHEAD FOREVER reference-first recipe authority for read-only profession route planning.
-- Historical user-research data is immutable audit history, never allowed to replace a
-- verified Forever direct reagent set in the effective route. No live QA / NPC requirement.
local S={contract="forever-reference-first-route-v1",sourcePriority="WOWHEAD_FOREVER",nativeDispatchAllowed=false,
    executionEligible=false,persisted=false}
local function clone(value,depth)
    if type(value)~="table" then return value end
    depth=(depth or 0)+1
    if depth>24 then return nil end
    local out={}
    for k,v in pairs(value) do out[k]=clone(v,depth) end
    return out
end
local function rawRoot() return JLP.data and JLP.data.professionResearchRoutes end
local function publicRoot() return JLP.data and JLP.data.publicCraftingRouteEvidence end
local function canonical(key)
    key=tostring(key or ""):upper()
    local public=publicRoot()
    local entry=public and public.professions and public.professions[key]
    if not entry then return nil end
    local registry=JLP:GetModule("ProfessionRegistry")
    local def=registry and registry:Get(key)
    if not def or tonumber(def.skillLineID)~=tonumber(entry.skillLineID) then return nil end
    return entry
end
local function valid(row,build)
    if type(row)~="table" or type(row.name)~="string" or row.name==""
       or type(row.recipeID)~="number" or row.recipeID<=0
       or tonumber(row.sourceBuild)~=tonumber(build)
       or row.sourceURL~="https://www.wowhead.com/forever/spell="..tostring(row.recipeID)
       or row.evidenceClass~="PUBLIC_FOREVER_RECIPE_REAGENTS"
       or row.status~="REFERENCE_VERIFIED" or type(row.reagents)~="table" or #row.reagents==0 then return false end
    local ids={}
    for _,item in ipairs(row.reagents) do
        if type(item.itemID)~="number" or item.itemID<=0 or ids[item.itemID]
        or type(item.name)~="string" or item.name=="" or type(item.quantity)~="number"
        or item.quantity<=0 or item.quantity~=math.floor(item.quantity) then return false end
        ids[item.itemID]=true
    end
    return true
end
-- For already-curated production candidate evidence, published reference rows
-- must remain an exact ID/quantity match. This is a DATA integrity check,
-- never a client/NPC corroboration gate.
local function matchesCuratedBuildEvidence(key,row)
    -- P0-222: opt-in exact immutable-source / DB70450 field parity for newly
    -- admitted records. Older reference rows retain their historical
    -- availability contract; this does NOT make DB70450 a live-build gate.
    if row.enforceDB70450Parity==true then
        local db=JLP.data and JLP.data.build70450Recipes
        local entry=db and db.professions and db.professions[key]
        if not entry or type(entry.packed)~="string" then return false end
        local found=0
        for line in entry.packed:gmatch("[^\n]+") do
            line=line:gsub("^.*%[==%[", "")
            if tonumber(line:match("^(%d+)%^"))==row.recipeID then
                found=found+1
                local fields={}
                for field in (line.."^"):gmatch("([^%^]*)%^") do fields[#fields+1]=field end
                if #fields~=12 or fields[12]~=row.name then return false end
                local expected={};local n=0
                for token in fields[10]:gmatch("[^,]+") do
                    local id,qty=token:match("^(%d+):(%d+)$")
                    id,qty=tonumber(id),tonumber(qty)
                    if not id or not qty or qty<=0 or expected[id] then return false end
                    expected[id]=qty;n=n+1
                end
                if n~=#row.reagents then return false end
                for _,mat in ipairs(row.reagents) do
                    if expected[mat.itemID]~=mat.quantity then return false end
                    expected[mat.itemID]=nil
                end
                if next(expected) then return false end
            end
        end
        if found~=1 then return false end
    end
    local root=JLP.data and JLP.data.currentBuildEvidence
    local ev=root and root.professions and root.professions[key]
    if not ev then return true end
    if tonumber(ev.build)~=tonumber(row.sourceBuild) then return false end
    local matches=0
    for _,expected in ipairs(ev.rows or {}) do
        if expected.recipeID==row.recipeID then
            matches=matches+1
            local seen={}
            for _,mat in ipairs(row.reagents or {}) do
                if seen[mat.itemID] then return false end
                seen[mat.itemID]=mat.quantity
            end
            local count=0
            for _,material in ipairs(expected.materials or {}) do
                if seen[material[1]]~=material[2] then return false end
                count=count+1
            end
            if count~=#(row.reagents or {}) then return false end
        end
    end
    return matches==1
end
function S:GetReference(key,recipeID,recipeName)
    local entry=canonical(key)
    local root=publicRoot()
    if not entry or not root then return nil,"no-curated-wowhead-reference" end
    local matches={}
    for _,row in ipairs(entry.recipes or {}) do
        if (recipeID and tonumber(recipeID)==row.recipeID) or (not recipeID and row.name==recipeName) then
            matches[#matches+1]=row
        end
    end
    if #matches~=1 then return nil,#matches>1 and "ambiguous-reference" or "recipe-not-referenced" end
    local row=matches[1]
    if not valid(row,root.build) then return nil,"invalid-reference-contract" end
    -- P0-222: exact SpellID is necessary but not sufficient: the user-facing
    -- historical recipe name must match the independently curated Forever
    -- identity. Never attach another spell-page name through an ID-only join.
    if recipeName~=nil and (type(recipeName)~="string" or recipeName~=row.name) then
        return nil,"recipe-name-source-conflict"
    end
    if not matchesCuratedBuildEvidence(key,row) then return nil,"current-build-reference-reagent-mismatch" end
    return clone(row)
end
local function requirementsFromReference(row,crafts)
    local out={}
    for _,m in ipairs(row.reagents) do
        out[#out+1]={itemID=m.itemID,name=m.name,quantity=m.quantity*crafts,perCraft=m.quantity,
            authority="WOWHEAD_FOREVER",sourceURL=row.sourceURL,sourceBuild=row.sourceBuild,
            evidence="wowhead-forever-direct-reagents"}
    end
    return out
end
local function comparable(legacy,canonicalReq)
    local old,new={},{}
    for _,m in ipairs(legacy or {}) do old[m.name]=(old[m.name] or 0)+(tonumber(m.quantity) or 0) end
    for _,m in ipairs(canonicalReq or {}) do new[m.name]=(new[m.name] or 0)+(tonumber(m.quantity) or 0) end
    for k,v in pairs(new) do if old[k]~=v then return false end end
    for k,v in pairs(old) do if new[k]~=v then return false end end
    return true
end
function S:GetEffectiveRoute(key,mode)
    key=tostring(key or ""):upper()
    mode=(mode=="aggressive" or mode=="fastest") and "aggressive" or "normal"
    local raw=rawRoot()
    local historical=raw and raw.professions and raw.professions[key] and raw.professions[key][mode]
    if not historical then return nil,"research-route-not-found" end
    local route=clone(historical)
    local starter=JLP:GetModule("ForeverStarterRoute")
    if starter and starter.CorrectEffectiveRoute then
        route=starter:CorrectEffectiveRoute(key,route)
    end
    route.dataPriority="WOWHEAD_FOREVER_OVER_LEGACY_RESEARCH"
    route.referenceContract=self.contract
    route.referenceMatches=0
    route.referenceCorrections=0
    route.unverifiedCraftSteps=0
    -- Never rewrite the original research route; this effective model is transient.
    for _,step in ipairs(route.steps or {}) do
        if step.kind=="craft" then
            local row=self:GetReference(key,step.recipeID,step.recipe)
            if row then
                local crafts=tonumber(step.expectedCrafts)
                if crafts and crafts>0 and crafts==math.floor(crafts) then
                    local direct=requirementsFromReference(row,crafts)
                    local changed=not comparable(step.requirements,direct)
                    step.legacyResearchRequirements=clone(step.requirements)
                    step.requirements=direct
                    step.recipeID=row.recipeID
                    step.recipeReferenceURL=row.sourceURL
                    step.recipeReferenceBuild=row.sourceBuild
                    step.requiredSkill=row.requiredSkill
                    step.requiredSkillAuthority=(row.skillBasis=="WOWHEAD_FOREVER" and tonumber(row.requiredSkill)) and "WOWHEAD_FOREVER" or "UNVERIFIED_SKILL_GATE"
                    step.referenceStatus="WOWHEAD_FOREVER_AUTHORITATIVE"
                    step.referenceMaterialCorrected=changed
                    step.directReagentAuthority="WOWHEAD_FOREVER"
                    step.routeQualification="RECIPE_REFERENCE_ONLY"
                    route.referenceMatches=route.referenceMatches+1
                    if changed then route.referenceCorrections=route.referenceCorrections+1 end
                    if step.requiredSkillAuthority=="WOWHEAD_FOREVER" and tonumber(step.skillMin) and tonumber(row.requiredSkill) and step.skillMin<row.requiredSkill then
                        step.skillGateConflict=true
                    end
                else
                    step.referenceStatus="CRAFT_COUNT_UNRESOLVED"
                    route.unverifiedCraftSteps=route.unverifiedCraftSteps+1
                end
            else
                step.referenceStatus="LEGACY_RESEARCH_UNVERIFIED"
                step.routeQualification="RESEARCH_ONLY"
                route.unverifiedCraftSteps=route.unverifiedCraftSteps+1
            end
        end
    end
    route.referenceComplete=route.unverifiedCraftSteps==0
    route.nativeDispatchAllowed=false
    route.executionEligible=false
    return route
end
function S:GetHistoricalRoute(key,mode)
    local raw=rawRoot()
    mode=(mode=="aggressive" or mode=="fastest") and "aggressive" or "normal"
    return raw and raw.professions and raw.professions[tostring(key or ""):upper()] and raw.professions[tostring(key or ""):upper()][mode]
end
function S:GetSummary(key,mode)
    if not key then return "Forever recipe authority: Wowhead current direct reagents > historical research; no Live-QA required" end
    local route,err=self:GetEffectiveRoute(key,mode)
    if not route then return "Forever recipe authority: "..tostring(err) end
    return string.format("%s %s · Wowhead overrides %d · material corrections %d · research-only craft steps %d · read-only, no native dispatch",
        tostring(key):upper(),mode=="aggressive" and "aggressive" or "normal",route.referenceMatches,
        route.referenceCorrections,route.unverifiedCraftSteps)
end
JLP:RegisterModule("ForeverRecipeAuthority",S)
