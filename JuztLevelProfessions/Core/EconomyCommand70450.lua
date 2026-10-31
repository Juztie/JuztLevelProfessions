local _,JLP=...
-- Manual diagnostics only. No auctions, buys, bank withdrawals or crafts.
local Command={contract="JLP-ECONOMY-COMMAND-70450-1"}
local function say(t) if JLP.Print then JLP:Print(tostring(t)) end end
local function show(receipt)
    say(tostring(receipt.status).." | "..#receipt.recipes.." recipe(s), "..
        receipt.materialTypes.." materials | external "..
        tostring(receipt.totalExternalRequired or "UNKNOWN").." | cost "..
        tostring(receipt.totalCostEstimate or "UNKNOWN").." copper (advisory)")
    for _,r in ipairs(receipt.rows) do
        say("#"..r.itemID.." "..tostring(r.name or "[NAME UNKNOWN]")..
            " x"..r.required.." | bags "..tostring(r.stock.currentBags or "UNKNOWN")..
            " | current bank "..tostring(r.stock.currentBank or "UNKNOWN")..
            " | cached bank "..tostring(r.stock.savedBankAdvisory or "UNKNOWN")..
            " | external "..tostring(r.externalRequired or "UNKNOWN")..
            " | AH "..r.price.state)
    end
    say("No automated purchase/craft rights; cached bank, market depth and route access must be reviewed.")
end
function Command:Handle(msg)
    local service=JLP:GetModule("EconomyIntegration70450")
    if not service then say("70450 economy service unavailable");return end
    local key,spell,crafts=msg:match("^economy70450%s+(%S+)%s+(%d+)%s*(%d*)$")
    local step=msg:match("^economystep70450%s+(%S+)$")
    local result,why
    if key then result,why=service:GetRecipePlan(key:upper(),tonumber(spell),
        crafts~="" and tonumber(crafts) or 1,70450)
    elseif step then result,why=service:GetCurrentStep(step:upper(),70450)
    else
        say("Usage: /jlp economy70450 TAILORING SPELL_ID [CRAFTS] or /jlp economystep70450 TAILORING")
        return
    end
    if not result then say("Economy 70450: "..tostring(why));return end
    show(result)
end
JLP:RegisterModule("EconomyCommand70450",Command)
