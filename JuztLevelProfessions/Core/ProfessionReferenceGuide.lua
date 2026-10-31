local _, JLP = ...
-- Read-only research guide built only from source-backed Forever catalog entries.
local Service={contract="profession-public-reference-guide-v1",nativeDispatchAllowed=false}
local function data() return JLP.data and JLP.data.publicProfessionGuides end
function Service:Get(key)
    local reg=JLP:GetModule("ProfessionRegistry")
    local def=reg and reg:Get(key)
    local row=def and data() and data().professions[def.key]
    if not row then return nil,"REFERENCE_GUIDE_UNAVAILABLE" end
    if tonumber(row.skillLineID)~=tonumber(def.skillLineID) then return nil,"SKILL_ID_MISMATCH" end
    return row
end
function Service:GetCurrentBand(key,skill)
    local row,err=self:Get(key)
    if not row then return nil,err end
    skill=tonumber(skill)
    if not skill then return nil,"SKILL_UNAVAILABLE" end
    for _,entry in ipairs(row.bands or {}) do
        if skill>=entry.skillMin and skill<entry.skillMax then return entry end
    end
    return nil,"SKILL_BAND_NOT_DOCUMENTED"
end
function Service:GetSummary(key)
    local reg=JLP:GetModule("ProfessionRegistry")
    if not key or key=="" then
        local keys={}
        for _,k in ipairs(reg and reg:GetKeys() or {}) do keys[#keys+1]=k end
        return "Public reference guides · "..table.concat(keys,", ").." · /jlp professionguide PROFESSION"
    end
    local row,err=self:Get(key)
    if not row then return "Public reference guide "..tostring(key).." · "..tostring(err) end
    local def=reg:Get(key)
    local api=JLP:GetModule("ProfessionAPI")
    local state=api and api.Get and api:Get(def.key)
    local current=state and tonumber(state.skill)
    local band= current and self:GetCurrentBand(def.key,current)
    local output={def.label.." · "..row.coverage.." · "..row.levelingType}
    if band then
        output[#output+1]="skill "..band.skillMin.."-"..band.skillMax.." · "..band.action..
            " · "..table.concat(band.resources or {},", ").." · "..table.concat(band.zones or {},", ")
    else output[#output+1]="No verified band for current skill; source reference remains available" end
    local comparison=JLP:GetModule("PublicCraftingRouteComparison")
    local compare=comparison and comparison:Audit(def.key)
    if compare then
        output[#output+1]="Public recipe references "..compare.verifiedCount.."/"..#compare.recipes..
            " · Normal matches "..compare.researchMatchCount.." · Normal drift "..compare.researchDriftCount..
            " · Aggressive matches "..compare.aggressiveMatchCount.." · alternatives "..compare.alternativesCount
        output[#output+1]="Samples establish identities/materials, NOT a complete or optimized 1-300 route"
    end
    local bands=JLP:GetModule("ForeverSkillBandPlanner")
    if bands then
        local plan=bands:Build(def.key,"normal")
        if plan then
            output[#output+1]="Forever-backed craft steps "..plan.sourceMatched.."/"..#plan.steps..
                " · Historical skill bands / craft counts are estimates; /jlp skillband "..def.key.." 150"
        end
    end
    local acquisition=JLP:GetModule("ForeverRouteAcquisition")
    local preview=acquisition and acquisition:Build(def.key,"normal")
    if preview then
        output[#output+1]=string.format("Referenced route acquisition: %d conditional material IDs · %d research-only steps; /jlp routeacquire %s [normal|aggressive]",
            #preview.materials,preview.unknownReferenceSteps,def.key)
    end
    output[#output+1]="Source: "..tostring(row.guideURL or row.source)
    local alt=data() and data().comparisonGuides and data().comparisonGuides[def.key]
    if alt then output[#output+1]="Route candidate (not ID evidence): "..alt end
    output[#output+1]="Reference only · no NPC/client snapshot required · no native execution"
    return table.concat(output,"\n")
end
function Service:Validate()
    local errors={}
    local reg=JLP:GetModule("ProfessionRegistry")
    for _,key in ipairs(reg and reg:GetKeys() or {}) do
        local row=self:Get(key)
        if not row then errors[#errors+1]="missing-guide:"..key
        else
            if type(row.source)~="string" or not row.source:match("^https://www%.wowhead%.com/forever/") then errors[#errors+1]="non-wowhead-reference:"..key end
            for _,b in ipairs(row.bands or {}) do
                if not tonumber(b.skillMin) or not tonumber(b.skillMax) or b.skillMin>=b.skillMax then errors[#errors+1]="invalid-band:"..key end
            end
        end
    end
    return errors
end
JLP:RegisterModule("ProfessionReferenceGuide",Service)
