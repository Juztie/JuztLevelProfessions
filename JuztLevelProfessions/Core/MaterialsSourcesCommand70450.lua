local _, JLP = ...
-- Read-only manual reference inspection. No AH action, shopping cart,
-- destination mutation or native craft dispatch.
local Command={contract="JLP-MATERIALS-SOURCES-COMMAND-70450-1"}
local function tell(t) if JLP.Print then JLP:Print(tostring(t)) end end
function Command:Handle(msg)
    local key,spell,crafts=msg:match("^materialsources70450%s+(%S+)%s+(%d+)%s*(%d*)$")
    if not key then
        tell("Usage: /jlp materialsources70450 PROFESSION SPELL_ID [CRAFTS]")
        return
    end
    local s=JLP:GetModule("MaterialsSources70450")
    local receipt,why=s and s:GetRecipe(key,tonumber(spell),tonumber(crafts) or 1,70450)
    if not receipt then tell("Materials & Sources: "..tostring(why or "UNAVAILABLE"));return end
    tell((receipt.professionKey or key).." #"..spell.." "..(receipt.recipeName or "[NAME UNKNOWN]")..
        " / "..receipt.crafts.." crafts / "..receipt.materialState)
    if receipt.requiredSpellFocusID then
        tell("  Client casting focus: "..tostring(receipt.requiredSpellFocusName)..
            " (#"..tostring(receipt.requiredSpellFocusID)..") (availability UNKNOWN)")
    else
        tell("  Client casting focus: not specified in supplied spell requirement rows")
    end
    for _,row in ipairs(receipt.itemRows) do
        tell("  #"..row.itemID.." "..(row.name or "[NAME UNVERIFIED]")..
            " x"..row.required.." ("..row.perCraft.."/craft)"..
            " | bags "..tostring(row.bags or "UNKNOWN")..
            " | bank "..tostring(row.bank or "UNKNOWN")..
            " | external "..tostring(row.missing or "UNKNOWN"))
    end
    for _,item in ipairs(receipt.teachingItems or {}) do
        tell("  Teaching item #"..tostring(item.itemID).." "..
            tostring(item.name or "[NAME UNVERIFIED]").." (acquisition UNKNOWN)")
    end
    for i,lead in ipairs(receipt.researchSources or {}) do
        if i<=6 then
            tell("  Research "..tostring(lead.sourceType or "UNKNOWN")..": "..
                tostring(lead.npcName or "NPC UNKNOWN").." #"..tostring(lead.npcID or "?")..
                " / "..tostring(lead.zone or "zone UNKNOWN")..
                ((lead.evidenceTier=="WOWHEAD_FOREVER_ALLIANCE_PUBLIC_REFERENCE" or
                    lead.evidenceTier=="WOWHEAD_FOREVER_HORDE_PUBLIC_REFERENCE") and
                    (" / "..tostring(lead.factionReference).." public skill "..
                    tostring(lead.guideSkillRequired)..
                    (lead.merchantFavorCost and (" / Merchant's Favor "..
                    tostring(lead.merchantFavorCost)) or "")) or "")..
                " (NOT live-verified)")
        end
    end
    if #(receipt.researchSources or {})>6 then
        tell("  More research leads available using /jlp source70450")
    end
    tell("Output: "..tostring(receipt.outputStatus).." (NOT live-verified). Acquisition: "..
        tostring(receipt.sourceStatus).." / AH costs UNKNOWN. No automatic crafting, travel or purchasing.")
    if receipt.hasSourceConflict then tell("WARNING: conflicting source evidence; do not act automatically.") end
end
JLP:RegisterModule("MaterialsSourcesCommand70450",Command)
