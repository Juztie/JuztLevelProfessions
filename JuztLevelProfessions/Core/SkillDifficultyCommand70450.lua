local _, JLP = ...
-- Diagnostic commands only. No automatic planning or crafting side effects.
local Command={contract="JLP-DIFFICULTY-COMMAND-70450-1"}
local function say(s) if JLP.Print then JLP:Print(tostring(s)) end end
function Command:Handle(msg)
    local service=JLP:GetModule("Build70450SkillDifficulty")
    if not service then say("70450 skill difficulty reference unavailable");return end
    local verb=msg:match("^(%S+)") or ""
    if verb=="difficultycover70450" then
        local c,err=service:GetCoverage();if not c then say(err);return end
        say("70450 skill difficulty: "..c.uniqueProfessionSpell.." identities; "..
            c.qualifiedYellowGrey.." usable yellow+grey; "..c.missing..
            " zero/zero; "..c.conflict.." conflicting; ORANGE/GREEN: UNKNOWN")
        for name,r in pairs(c.byProfession) do
            say(name..": "..(r.ordered+r.equal).." qualified / "..r.total..
                "; missing="..r.missing..", conflict="..r.conflict)
        end
    elseif verb=="difficulty70450" then
        local key,spell,skill=msg:match("^difficulty70450%s+(%S+)%s+(%d+)%s*(%d*)$")
        if not key then say("Usage: /jlp difficulty70450 TAILORING 2963 [skill]");return end
        local d,err=service:GetDifficulty(key,tonumber(spell),70450)
        if not d then say("Difficulty: "..tostring(err));return end
        say(d.professionKey.." spell #"..spell.." / "..d.yellowGreyState..
            " | ORANGE UNKNOWN, YELLOW "..(d.yellow or "UNKNOWN")..
            ", GREEN UNKNOWN, GREY "..(d.grey or "UNKNOWN"))
        say("Raw low="..d.rawTrivialSkillLineRankLow.." high="..
            d.rawTrivialSkillLineRankHigh.." | build "..tostring(d.clientBuildRelation)..
            "; learn rank UNKNOWN, no inferred thresholds")
        if skill~="" then
            local observed,why=service:GetAtSkill(key,tonumber(spell),tonumber(skill),70450)
            if observed then
                say("Skill "..skill..": "..observed.skillRegion..
                    "; verified color="..(observed.verifiedColor or "UNKNOWN"))
            else say("Rank: "..tostring(why)) end
        end
    elseif verb=="difficultylive70450" then
        local key,spell,index=msg:match("^difficultylive70450%s+(%S+)%s+(%d+)%s+(%d+)$")
        if not key then say("Usage: /jlp difficultylive70450 TAILORING 2963 INDEX");return end
        local snapshot,reason=service:GetLiveTradeSkillColor(key,tonumber(spell),tonumber(index),70450)
        if not snapshot then say("Live difficulty: "..tostring(reason));return end
        say(snapshot.professionKey.." spell #"..spell.." at skill "..snapshot.skillRank..
            ": "..snapshot.observedColor.." (live UI observation ONLY; numeric transitions UNKNOWN)")
    elseif verb=="difficultyissues70450" then
        local key,offset=msg:match("^difficultyissues70450%s+(%S+)%s*(%d*)$")
        if not key then say("Usage: /jlp difficultyissues70450 TAILORING [offset]");return end
        offset=tonumber(offset) or 0
        if offset>100000 then say("Offset out of range");return end
        local c=JLP:GetModule("Build70450RecipeCatalogue")
        local first,err=c:GetPage(key,0,1,70450)
        if not first then say(tostring(err));return end
        local index,shown=0,0
        for i=0,first.totalMatches-1,50 do
            local page,why=c:GetPage(key,i,50,70450)
            if not page then say(tostring(why));return end
            for _,r in ipairs(page.rows) do
                local d=r.skillDifficulty or service:ForDecodedRecipe(r)
                if d and d.yellowGreyState~="SOURCE_ORDERED" and
                    d.yellowGreyState~="SOURCE_EQUAL_YELLOW_GREY" then
                    if index>=offset and shown<12 then
                        say("#"..r.spellID.." "..(r.name or "[unnamed]")..": "..d.yellowGreyState..
                            " (raw "..d.rawTrivialSkillLineRankLow.."/"..d.rawTrivialSkillLineRankHigh..")")
                        shown=shown+1
                    end
                    index=index+1
                end
            end
        end
        if shown==0 then say("No further unresolved rows") end
    else
        say("Usage: /jlp difficultycover70450 | difficulty70450 KEY SPELL [skill] | difficultylive70450 KEY SPELL INDEX | difficultyissues70450 KEY [offset]")
    end
end
JLP:RegisterModule("SkillDifficultyCommand70450",Command)
