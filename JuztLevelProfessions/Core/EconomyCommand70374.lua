local _,JLP=...
-- Manual, read-only commands; no protected API calls and no automatic scans.
local Command={contract="JLP-ECONOMY-70374-COMMAND-1"}
local function output(text)
    if JLP.Print then JLP:Print(text) end
end
local function parseNumbers(command)
    local key,spell,quantity=command:match("^%S+%s+(%S+)%s+(%d+)%s*(%d*)$")
    return key and key:upper() or nil,tonumber(spell),quantity~="" and tonumber(quantity) or 1
end
function Command:Handle(command)
    local econ=JLP:GetModule("ProfessionEconomy70374")
    if not econ then output("Economy reference is unavailable"); return end
    -- Command arguments below specify the archived CSV SOURCE build; they
    -- must not be populated with GetBuildInfo() from the running client.
    -- Current AH/inventory scopes remain independently validated elsewhere.
    local build=70374
    local verb=command:match("^(%S+)")
    if verb=="datacheck70374" then
        local key=command:match("^datacheck70374%s+(%S+)$")
        if not key then output("Usage: /jlp datacheck70374 TAILORING");return end
        local bridge=JLP:GetModule("ProfessionDataBridge70374")
        local state,err=bridge and bridge:GetProfessionState(key)
        if not state then output("Data communication unavailable: "..tostring(err or "BRIDGE_MISSING"));return end
        local valid,status=bridge:ValidateState(state)
        output(state.professionKey.." | SkillLine "..state.skillLineID..
            " | Enum "..state.professionEnum.." | "..state.abilityRows..
            " abilities | "..state.rowsWithReagents.." reagent records | "..
            (valid and "SYNC_OK" or "SYNC_INVALID").." ("..tostring(status)..") | research only")
    elseif verb=="recipecheck70374" then
        local key,spell,crafts=command:match("^recipecheck70374%s+(%S+)%s+(%d+)%s*(%d*)$")
        if not key then output("Usage: /jlp recipecheck70374 TAILORING 2963 4");return end
        local bridge=JLP:GetModule("ProfessionDataBridge70374")
        local state,err=bridge and bridge:GetRecipeState(key,tonumber(spell),tonumber(crafts) or 1,
            {includeEconomy=true,priceStrategy="AH_ONLY"})
        if not state then output("Recipe communication unavailable: "..tostring(err or "BRIDGE_MISSING"));return end
        local valid,status=bridge:ValidateState(state)
        output(state.professionKey.." / "..spell.." | "..state.materialState..
            " | "..state.priceState.." | "..(valid and "SYNC_OK" or "SYNC_INVALID")..
            " ("..tostring(status)..") | no craft authorization")
    elseif verb=="progresscheck70374" then
        local key,skill=command:match("^progresscheck70374%s+(%S+)%s+(%d+)$")
        if not key then output("Usage: /jlp progresscheck70374 MINING 125");return end
        local bridge=JLP:GetModule("ProfessionDataBridge70374")
        local state,err=bridge and bridge:GetProgressionState(key,tonumber(skill))
        if not state then output("Progress communication unavailable: "..tostring(err or "BRIDGE_MISSING"));return end
        local valid,status=bridge:ValidateState(state)
        output(state.professionKey.." / skill "..skill.." | "..state.candidates.total..
            " raw candidates | "..(valid and "SYNC_OK" or "SYNC_INVALID")..
            " ("..tostring(status)..") | no guaranteed skill-ups")
    elseif verb=="econ" then
        local key,spell,quantity=parseNumbers(command)
        if not key or not spell then output("Usage: /jlp econ TAILORING 2963 4"); return end
        output(econ:GetSummary(key,spell,quantity,build))
    elseif verb=="mats" then
        local key,spell,quantity=parseNumbers(command)
        if not key or not spell then output("Usage: /jlp mats TAILORING 2963 4"); return end
        local materials,err=econ:GetRecipeMaterials(key,spell,quantity,build)
        if not materials then output("Materials unavailable: "..tostring(err));return end
        output(materials.recipeName.." x"..quantity.." · "..#materials.requirements..
            " reagent item types (raw DB2 reference, not a certified crafting plan)")
        for _,row in ipairs(materials.requirements) do
            output((row.name or ("Item #"..row.itemID)).." ["..row.itemID.."] "..
                row.perCraft.." x "..quantity.." = "..row.rawTotal)
        end
        if materials.emptyReagents then output("No reagent entries; cannot infer free crafting") end
    elseif verb=="profit70374" then
        local key,spell,crafts,yieldCount,fee=command:match(
            "^profit70374%s+(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
        if not key then
            output("Usage: /jlp profit70374 TAILORING 2963 1 2 500 (500 bps = 5% fee; assumed yield)")
            return
        end
        local result,err=econ:ProjectSaleScenario(key:upper(),tonumber(spell),tonumber(crafts),build,
            {priceStrategy="AH_ONLY",outputUnitsPerCraft=tonumber(yieldCount),saleFeeBps=tonumber(fee)})
        if not result then output("Profit what-if unavailable: "..tostring(err));return end
        output(result.professionKey.." / "..spell..": AH ask "..econ:FormatCopper(result.observedAHAskCopper)..
            ", scenario fee "..econ:FormatCopper(result.projectedFeeCopper)..
            ", projected margin "..(result.marginKnown and econ:FormatCopper(result.projectedMarginCopper)
                or "UNKNOWN")..". NOT a verified yield/sale/profit; deposits excluded.")
    elseif verb=="econplan70374" then
        local key,first,last=command:match("^econplan70374%s+(%S+)%s+(%d+)%s+(%d+)$")
        if not key then output("Usage: /jlp econplan70374 MINING 1 300");return end
        local plan,err=econ:BuildProgressionWorksheet(key:upper(),tonumber(first),tonumber(last),build,
            {interval=25})
        if not plan then output("Worksheet unavailable: "..tostring(err));return end
        output(plan.professionKey.." · "..plan.strategy.." · "..#plan.checkpoints..
            " research checkpoints (NOT an executable full progression route)")
        for _,row in ipairs(plan.checkpoints) do
            output(row.fromSkill.."-"..row.toSkill.." · "..row.activityKind..
                " · candidates "..row.rawBandCandidateCount.." · craft count UNKNOWN")
        end
    elseif verb=="progress70374" then
        local key,skill=command:match("^progress70374%s+(%S+)%s+(%d+)$")
        if not key then output("Usage: /jlp progress70374 BLACKSMITHING 125");return end
        local candidates,err=econ:GetProgressionCandidates(key:upper(),tonumber(skill),build,0,8)
        if not candidates then output("Progression unavailable: "..tostring(err));return end
        output(key:upper().." skill "..skill.." · "..candidates.total..
            " raw-range reagent candidates (not a guaranteed skill-up route)")
        for _,row in ipairs(candidates.rows) do
            output("Spell "..row.spellID.." "..row.name.." · DB2 range "..row.rawLow.."-"..row.rawHigh)
        end
        if #candidates.rows==0 then output("No candidates in this raw band; gathering/fishing requires area guidance") end
    else
        output(econ:GetSummary())
    end
end
JLP:RegisterModule("EconomyCommand70374",Command)
