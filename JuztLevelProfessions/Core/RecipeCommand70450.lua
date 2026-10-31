local _, JLP = ...
-- Manual read-only exploration. No recipe is auto-applied to production planners.
local Commands = {contract="JLP-RECIPE-COMMAND-70450-1"}
local function output(msg) if JLP.Print then JLP:Print(tostring(msg)) end end
function Commands:Handle(msg)
    local ref=JLP:GetModule("Build70450RecipeCatalogue")
    if not ref then output("70450 recipe reference not loaded");return end
    local verb=msg:match("^(%S+)") or ""
    if verb=="recipeaudit70450" then
        local qa=JLP:GetModule("Build70450RecipeQualification")
        local c,e=qa and qa:GetCoverage()
        if not c then output("QA: "..tostring(e));return end
        output("70450: "..c.uniqueSpells.." unique identities / "..c.recipeCandidates..
            " recipe candidates / "..c.abilityOnly.." abilities / "..c.issueRows.." QA exception entries")
        output("12 client taxonomy hierarchies checked; LIVE faction/spec/trainer/phase/access verified: 0; READ ONLY")
    elseif verb=="recipeissues70450" then
        local k,off=msg:match("^recipeissues70450%s+(%S+)%s*(%d*)$")
        if k=="ALL" then k=nil end
        if not k and msg~="recipeissues70450" and msg~="recipeissues70450 ALL" then
            output("Usage: /jlp recipeissues70450 [PROFESSION|ALL] [OFFSET]");return
        end
        local qa=JLP:GetModule("Build70450RecipeQualification")
        local list,e=qa and qa:GetExceptions(k,tonumber(off) or 0,15,70450)
        if not list then output("Issues: "..tostring(e));return end
        output("70450 exceptions "..(list.professionKey or "ALL")..": "..list.totalMatches..
            " entries; offset "..list.offset)
        for _,v in ipairs(list.rows) do
            output("  "..v.professionKey.." #"..v.spellID.." "..v.code.." [NOT LIVE-VERIFIED]")
        end
    elseif verb=="recipecoverage70450" then
        local result,why=ref:GetCoverage()
        if not result then output("Coverage: "..tostring(why));return end
        output("70450 recipe reference: "..result.recipeCandidates.." classified candidates / "..
            result.abilityOnly.." abilities only; "..result.uniqueProfessionSpellRecords..
            " unique profession/spell pairs; "..result.duplicateSourceRows.." duplicate source rows.")
        output("Client: "..result.clientBuildRelation..
            "; FACTION / SPECIALIZATION / PHASE / TRAINERS / LIVE ACCESS: UNVERIFIED")
        local reg=JLP:GetModule("ProfessionRegistry")
        for _,key in ipairs(reg and reg:GetKeys() or {}) do
            local row=result.byProfession[key]
            if row then output(key..": "..row.recipeCandidates.." candidates ("..
                row.abilityRows.." source abilities, "..row.missingSpellNames.." names unavailable)") end
        end
    elseif verb=="recipeproof70450" then
        local key,spell=msg:match("^recipeproof70450%s+(%S+)%s+(%d+)$")
        if not key then output("Usage: /jlp recipeproof70450 PROFESSION SPELL_ID");return end
        local bundle=JLP:GetModule("RecipeEvidenceBundle70450")
        local proof,why=bundle and bundle:GetProof(key,tonumber(spell),70450)
        if not proof then output("Recipe proof: "..tostring(why or "BUNDLE_UNAVAILABLE"));return end
        output(proof.professionKey.." #"..proof.spellID.." "..(proof.name or "[UNKNOWN NAME]")..
            " | "..proof.classification.." | "..proof.state.." | NO NATIVE AUTHORITY")
        output("Reagents="..proof.reagentState.." | output="..proof.outputOutcome..
            " (yield UNVERIFIED) | raw min skill="..proof.rawMinSkillLineRank)
        output("Yellow="..tostring(proof.yellow or "UNKNOWN").." grey="..
            tostring(proof.grey or "UNKNOWN").." orange/green=UNKNOWN (client source only)")
        for _,r in ipairs(proof.reagents or {}) do
            output("  Reagent item #"..r.itemID.." x"..r.perCraft)
        end
        output("Teaching item links="..tostring(proof.teachingItemCount)..
            " | acquisition="..proof.acquisitionState.." (server access UNKNOWN)")
        for _,reason in ipairs(proof.sourceFlags) do output("  Evidence gap: "..reason) end
    elseif verb=="recipe70450" then
        local key,spell=msg:match("^recipe70450%s+(%S+)%s+(%d+)$")
        if not key then output("Usage: /jlp recipe70450 TAILORING 2963");return end
        local row,why=ref:GetRecipe(key,tonumber(spell),70450)
        if not row then output("Recipe: "..tostring(why));return end
        local name=row.name or "NAME_UNAVAILABLE"
        local path=row.categoryPath[1] and row.categoryPath[1].name or "UNCLASSIFIED"
        output(row.professionKey.." / "..row.spellID.." "..name..
            " | "..row.recordKind.." | "..path.." | client "..row.clientBuildRelation)
        output("Category evidence="..row.categoryStatus.."; QA="..table.concat(row.reviewCodes,",")..
            "; availability="..row.recipeAvailabilityStatus)
        output("Faction="..row.factionAccess.."; specialization gate="..row.specializationGate..
            (row.specializationNameHint and " (name hint "..row.specializationNameHint..")" or "")..
            "; phase="..row.phase.."; SoD category="..tostring(row.seasonOfDiscoveryCategory))
        output("Reagents="..row.reagentState.." ("..tostring(row.reagents and #row.reagents or "?")..
            " slots); outputs="..#row.outputs.." unverified yields; source actor UNKNOWN; no crafting authorization")
        if row.rawRaceMasks then output("Raw race masks: "..table.concat(row.rawRaceMasks,", ").." [not decoded]") end
        local craftOutput=row.craftOutput
        if craftOutput then
            output("Output reference: "..craftOutput.outcome.." (server yield NOT verified)")
            for _,eff in ipairs(craftOutput.effects) do
                if eff.kind=="CREATED_ITEM" then
                    output("  Crafted item #"..eff.itemID.." "..(eff.name or "[ItemSparse name unavailable]")..
                        ": "..eff.yieldState..(eff.perCraftQuantity and " x"..eff.perCraftQuantity or " count unknown"))
                elseif eff.kind=="TARGET_ITEM_ENCHANTMENT" then
                    output("  Existing target enchant #"..eff.enchantmentID..": "..eff.enchantmentName.." (no new item)")
                else output("  Disenchant outcome unknown; no fixed item count") end
            end
        end
        for _,r in ipairs(row.reagents or {}) do
            output("  Item #"..r.itemID.." x"..r.quantity.." "..(r.itemName or "[name unavailable]")..
                " ("..(r.itemNameState or "UNKNOWN")..")")
        end
    elseif verb=="recipes70450" then
        local key,offset,kind=msg:match("^recipes70450%s+(%S+)%s*(%d*)%s*(%S*)$")
        if not key then output("Usage: /jlp recipes70450 TAILORING 0 [sod|faction|spec|ability|issues]");return end
        local filter={}
        if kind=="sod" then filter.sodOnly=true
        elseif kind=="faction" then filter.unresolvedFaction=true
        elseif kind=="spec" then filter.specializationHintsOnly=true
        elseif kind=="ability" then filter.recordKind="ABILITY_ONLY"
        elseif kind=="issues" then filter.issuesOnly=true
        elseif kind~="" and kind~=nil then output("Unknown filter "..kind);return end
        local result,why=ref:GetPage(key,tonumber(offset) or 0,12,70450,filter)
        if not result then output("Page: "..tostring(why));return end
        output(result.professionKey.." build 70450 | "..result.totalMatches.." matches; page from "..result.offset..
            "; category/faction/spec/phase proof still UNKNOWN")
        for _,r in ipairs(result.rows) do
            local category=r.categoryPath[1] and r.categoryPath[1].name or "Uncategorized"
            output("  "..r.spellID.." "..(r.name or "[unnamed]").." ["..category.."]"..
                (r.duplicateSourceRows and " DUPLICATE_SLA" or ""))
        end
        if #result.rows>0 and result.offset+#result.rows<result.totalMatches then
            output("Next page: /jlp recipes70450 "..result.professionKey.." "..
                (result.offset+#result.rows)..(kind and kind~="" and " "..kind or ""))
        end
    elseif verb=="recipemissing70450" then
        local diff,why=ref:GetMissingFrom70374()
        if not diff then output("Recipe delta: "..tostring(why));return end
        for _,row in ipairs(diff.rows) do
            output(row.professionKey.." #"..row.spellID..
                " absent from 70450 profession line; not proof of removal from game")
        end
        if #diff.rows==0 then output("No ability spell identities absent from previous build") end
    else
        output("Usage: /jlp recipeproof70450 KEY SPELL | recipeaudit70450 | recipeissues70450 [KEY|ALL] [OFFSET] | recipecoverage70450 | recipe70450 KEY SPELL | recipes70450 KEY OFFSET [sod|faction|spec|ability|issues] | recipemissing70450")
    end
end
JLP:RegisterModule("RecipeCommand70450",Commands)
