local _, JLP = ...
local Command={contract="JLP-RECIPE-ACQUISITION-COMMAND-70450-1"}
local function tell(s) if JLP.Print then JLP:Print(tostring(s)) end end
function Command:Handle(msg)
    local service=JLP:GetModule("Build70450RecipeAcquisition")
    if not service then tell("Acquisition lookup unavailable");return end
    local verb=msg:match("^(%S+)") or ""
    if verb=="sourcecover70450" then
        local c,e=service:GetCoverage();if not c then tell(e);return end
        local n=c.counts
        tell("70450: "..n.total.." profession/spell records; "..n.withTeachingItems.." exact teaching-item links")
        tell("Research NPC/drop leads: "..n.withResearchSource.." recipes; "..n.publicCorroborated.." public Forever corroborations; "..n.conflict.." conflicts")
        tell("LIVE 70450 NPC/vendor/trainer/drop verified: 0. Not authorization to buy, craft or route.")
    elseif verb=="source70450" then
        local k,spell=msg:match("^source70450%s+(%S+)%s+(%d+)$")
        if not k then tell("Usage: /jlp source70450 PROFESSION SPELL_ID");return end
        local row,e=service:GetRecipeSources(k,tonumber(spell),70450)
        if not row then tell("Acquisition: "..tostring(e));return end
        tell(row.professionKey.." #"..row.spellID.." "..(row.recipeName or "[NAME UNKNOWN]").." / "..row.sourceState)
        if #row.teachingItems==0 then tell("No exact teaching item in client DB2; trainer/drop/quest unknown") end
        for _,t in ipairs(row.teachingItems) do tell("  Teaches: #"..t.itemID.." "..(t.name or "[NAME UNKNOWN]")) end
        for _,s in ipairs(row.researchSources) do
            tell("  "..s.sourceType..": "..(s.npcName or "[NPC UNKNOWN]").." #"..tostring(s.npcID or "?").." ("..s.evidenceTier..")")
        end
        tell("Live source status: UNVERIFIED; faction, specialization, phase: UNKNOWN")
    elseif verb=="sourcenpc70450" then
        local k,spell=msg:match("^sourcenpc70450%s+(%S+)%s+(%d+)$")
        if not k then tell("Usage: /jlp sourcenpc70450 PROFESSION SPELL_ID");return end
        local row,e=service:GetRecipeSources(k,tonumber(spell),70450)
        if not row then tell("Source: "..tostring(e));return end
        tell(row.professionKey.." spell #"..row.spellID.." / exact teaching items "..#row.teachingItems)
        for _,lead in ipairs(row.researchSources) do
            tell("  "..lead.sourceType.." "..(lead.npcName or "[NPC UNKNOWN]").." NPC #"..
                tostring(lead.npcID or "UNKNOWN").." / "..(lead.factionReference or "FACTION UNKNOWN")..
                " / "..(lead.evidenceTier or "SOURCE UNKNOWN"))
            for _,cross in ipairs(lead.publicCrosschecks or {}) do
                tell("    public reference: "..cross.evidenceState.." / "..cross.referenceURL)
                if cross.position then tell("    HISTORICAL ONLY map="..cross.position.uiMapID..
                    " x="..cross.position.x.." y="..cross.position.y.." NOT FOREVER VERIFIED") end
            end
        end
        tell("NPC faction requirements and current Forever locations: UNKNOWN; no route authority")
    elseif verb=="sourceobserve70450" then
        local kind,k,spell=msg:match("^sourceobserve70450%s+(%S+)%s+(%S+)%s+(%d+)$")
        if not kind then tell("Usage: /jlp sourceobserve70450 vendor|trainer|drop PROFESSION SPELL_ID");return end
        local observer=JLP:GetModule("Build70450NPCSourceEvidence")
        if not observer then tell("Source observation service unavailable");return end
        local fn=kind=="vendor" and observer.ObserveMerchant or
                 kind=="trainer" and observer.ObserveTrainer or
                 kind=="drop" and observer.ObserveLoot
        if not fn then tell("Unknown source observation type");return end
        local r,e=fn(observer,k,tonumber(spell),70450)
        if not r then tell("Source observation refused: "..tostring(e));return end
        tell("Current UI "..r.observationType.." / NPC #"..r.npcID..
             " / spell #"..r.spellID.." / matches="..#(r.matches or r.trainerServiceSlots or {}))
        if r.position then tell("Nearby player coordinate (NOT NPC spawn): "..
            r.position.uiMapID.." "..string.format("%.1f",r.position.x)..", "..
            string.format("%.1f",r.position.y)) end
        tell("Session-only evidence. Faction requirements and general availability UNKNOWN. No production rights.")
    elseif verb=="sourcepage70450" then
        local key,o=msg:match("^sourcepage70450%s+(%S+)%s*(%d*)$")
        if not key then tell("Usage: /jlp sourcepage70450 PROFESSION [OFFSET]");return end
        local page,e=service:GetPage(key,tonumber(o) or 0,10,70450)
        if not page then tell("Acquisition: "..tostring(e));return end
        tell(page.professionKey.." sources: "..page.totalMatches.." total; offset="..page.offset)
        for _,r in ipairs(page.rows) do
            tell("  #"..r.spellID.." "..(r.name or "[UNKNOWN]").." / "..r.acquisitionReference.sourceState)
        end
    else tell("Usage: sourcecover70450 | source70450 PROFESSION SPELL_ID | sourcepage70450 PROFESSION [OFFSET]") end
end
JLP:RegisterModule("RecipeAcquisitionCommand70450",Command)
