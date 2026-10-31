local _, JLP = ...
local Command={contract="JLP-OUTPUT-COMMAND-70450-1"}
local function say(t) if JLP.Print then JLP:Print(tostring(t)) end end
function Command:Handle(msg)
    local output=JLP:GetModule("Build70450CraftOutput")
    if not output then say("70450 output reference unavailable");return end
    local cmd=msg:match("^(%S+)") or ""
    if cmd=="yieldcover70450" then
        local page,why=output:GetCoverage();if not page then say(tostring(why));return end
        local c=page.counts
        say("Build 70450 output: "..c.uniqueProfessionSpellPairs.." spell/prof pairs; "..
            c.SOURCE_FIXED_REFERENCE.." static source bases; "..c.VARIABLE_VARIANCE_UNRESOLVED..
            " variable; "..c.BASE_ZERO_OR_NONINTEGER_UNRESOLVED.." unknown bases; "..
            c.TARGET_ITEM_ENCHANTMENT_NO_NEW_ITEM.." enchantments; "..
            c.RANDOM_DISENCHANT_LOOT_UNRESOLVED.." disenchant; "..
            c.NO_DIRECT_OUTPUT_EFFECT.." no direct output effect")
        say("Client build: "..page.clientBuildRelation..". Reference only: source base is not an in-game yield guarantee.")
    elseif cmd=="yield70450" then
        local key,spell,qty=msg:match("^yield70450%s+(%S+)%s+(%d+)%s*(%d*)$")
        if not key then say("Usage: /jlp yield70450 TAILORING 2963 [crafts]");return end
        local result,why=output:GetOutputWithMaterials(key,tonumber(spell),tonumber(qty) or 1,70450)
        if not result then say("Output: "..tostring(why));return end
        local r=result.output
        say(r.professionKey.." #"..spell.." x"..r.crafts.." | "..r.outcome.." | build "..r.clientBuildRelation)
        for _,eff in ipairs(r.effects) do
            if eff.kind=="CREATED_ITEM" then
                say("  Item #"..eff.itemID.." "..(eff.name or "[ItemSparse name missing]")..
                    " / "..eff.yieldState.." / raw base="..eff.rawEffectBasePointsF..
                    " variance="..eff.rawVariance..
                    (eff.totalQuantity and " / source x"..eff.totalQuantity or " / total UNKNOWN")..
                    (eff.referenceComparison and " / old external "..eff.referenceComparison or ""))
            elseif eff.kind=="TARGET_ITEM_ENCHANTMENT" then
                say("  Enchantment #"..eff.enchantmentID.." "..eff.enchantmentName..
                    " on existing target; 0 standard new items")
            else say("  Disenchant: random loot; materials and quantities UNKNOWN") end
        end
        if #r.effects==0 then say("  No direct item/enchant output effect in the provided export. Not proof of no output.") end
        if r.sourceReferenceConflict then say("  WARNING: Unpinned external yield conflicts with raw 70450 effect base") end
        say("Material status: "..(result.materials and "RAW_SOURCE_REQUIREMENTS" or
            (result.materialsError or "UNKNOWN")).." | output NOT live-confirmed")
    elseif cmd=="yieldlive70450" then
        local key,spell,index,qty=msg:match("^yieldlive70450%s+(%S+)%s+(%d+)%s+(%d+)%s*(%d*)$")
        if not key then say("Usage: /jlp yieldlive70450 TAILORING 2963 1 [crafts]");return end
        local r,why=output:GetClientTradeSkillYield(key,tonumber(spell),tonumber(index),tonumber(qty) or 1,70450)
        if not r then say("Client UI yield: "..tostring(why));return end
        say("UI recipe #"..spell.." / "..r.uiName.." x"..r.crafts..": "..r.uiMinMade.."-"..r.uiMaxMade..
            " per craft; assignment="..r.quantityAssignmentState)
        if r.createdItemID then
            say("  Created item #"..r.createdItemID.." / observed interval "..
                r.createdItemMinTotal.."-"..r.createdItemMaxTotal.."; source comparison="..r.rawSourceComparison)
        elseif r.noSeparateItemOutput then
            say("  Target enchantment: existing item modified; 0 separately created items")
        else say("  UI amount cannot be assigned to a unique created item") end
        say("UI evidence only. NOT an executed craft receipt or production authorization.")
    elseif cmd=="yieldissues70450" then
        local key,offset=msg:match("^yieldissues70450%s+(%S+)%s*(%d*)$")
        if not key then say("Usage: /jlp yieldissues70450 TAILORING [offset]");return end
        offset=tonumber(offset) or 0
        if offset<0 or offset>100000 then say("Invalid offset");return end
        local catalog=JLP:GetModule("Build70450RecipeCatalogue")
        local all,err=catalog:GetPage(key,0,1,70450)
        if not all then say(tostring(err));return end
        local problems={}
        for p=0,all.totalMatches-1,50 do
            local page=catalog:GetPage(key,p,50,70450)
            for _,r in ipairs(page.rows) do
                local result=output:ForKnownRecipe(r.professionKey,r.spellID,1,70450)
                if result and result.outcome~="ITEM_OUTPUT_STATIC_REFERENCE" and #problems<offset+12 then
                    problems[#problems+1]={r.spellID,result.outcome} end
            end
        end
        for i=offset+1,math.min(#problems,offset+12) do
            local v=problems[i];say(v[1].." "..v[2])
        end
        if #problems<=offset then say("No further issues in this page") end
    else
        say("Usage: /jlp yield70450 KEY SPELL [crafts] | yieldlive70450 KEY SPELL INDEX [crafts] | yieldcover70450 | yieldissues70450 KEY [offset]")
    end
end
JLP:RegisterModule("CraftOutputCommand70450",Command)
