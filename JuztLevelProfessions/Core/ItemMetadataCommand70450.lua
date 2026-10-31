local _, JLP = ...
local Command={contract="JLP-ITEM-METADATA-COMMAND-70450-1"}
local function tell(s) if JLP.Print then JLP:Print(tostring(s)) end end
function Command:Handle(msg)
    local service=JLP:GetModule("Build70450ItemMetadata")
    if not service then tell("Item metadata module unavailable");return end
    local verb=msg:match("^(%S+)") or ""
    if verb=="itemcover70450" then
        local c,err=service:GetCoverage()
        if not c then tell(err);return end
        local d=c.counts
        tell("70450 items: "..d.unique_item_ids.." relevant IDs; "..d.missing_names..
            " missing names; "..d.no_item.." missing Item rows; "..d.no_sparse.." missing ItemSparse rows")
        tell(d.recipe_reagent_ids.." reagent item IDs; "..d.craft_output_ids..
            " crafted output IDs; "..d.spell_linked_item_ids.." item/spell link candidates")
        tell("Vendor / trainer / quest / drop assignments not verified; client "..c.clientBuildRelation)
    elseif verb=="itemmeta70450" then
        local id=msg:match("^itemmeta70450%s+(%d+)$")
        if not id then tell("Usage: /jlp itemmeta70450 ITEM_ID");return end
        local a,err=service:GetItem(tonumber(id),70450)
        if not a then tell("Item: "..err);return end
        tell("#"..id.." "..(a.name or "[NAME UNKNOWN]").." ("..a.nameEvidence..") "..
            "["..table.concat(a.roles,",").."]")
        tell("Item row="..tostring(a.presentInItem).." Sparse="..tostring(a.presentInItemSparse)..
            " SearchName="..tostring(a.presentInItemSearchName).." client="..a.clientBuildRelation)
        tell("Raw class="..tostring(a.fields.ClassID or "?").." subclass="..tostring(a.fields.SubclassID or "?")..
            " stack="..tostring(a.fields.Stackable or "?").." quality="..tostring(a.fields.OverallQualityID or "?")..
            " sell="..tostring(a.fields.SellPrice or "?").." buy="..tostring(a.fields.BuyPrice or "?"))
        tell("Acquisition: UNKNOWN, price fields do not prove vendor stock")
    elseif verb=="itemaudit70450" then
        local id=msg:match("^itemaudit70450%s+(%d+)$")
        if not id then tell("Usage: /jlp itemaudit70450 ITEM_ID");return end
        local r,err=service:InspectItem(tonumber(id),70450)
        if not r then tell("Item audit: "..err);return end
        tell("#"..id.." "..(r.name or "[NAME UNKNOWN]").." name="..r.nameStatus.." item="..r.itemRowStatus)
        tell("Sparse="..r.sparseStatus.." SearchName="..r.searchNameStatus..
            " unknownFields="..r.missingFieldCount.."/"..r.fieldCount.." relations="..r.totalRelations)
        tell("Link="..r.clientItemLinkStatus.." acquisition="..r.acquisitionStatus..
            " (read-only; no native permissions)")
    elseif verb=="itemgaps70450" then
        local offset=msg:match("^itemgaps70450%s*(%d*)$")
        if offset==nil then tell("Usage: /jlp itemgaps70450 [OFFSET]");return end
        local page,err=service:GetPage(tonumber(offset) or 0,12,70450,{missingItemOnly=true})
        if not page then tell("Item rows: "..err);return end
        tell("Item.csv missing rows: "..page.totalMatches.."; from "..page.offset)
        for _,r in ipairs(page.rows) do tell(" #"..r.itemID.." "..(r.name or "[NAME UNKNOWN]")) end
    elseif verb=="itemprobe70450" then
        local id=msg:match("^itemprobe70450%s+(%d+)$")
        if not id then tell("Usage: /jlp itemprobe70450 ITEM_ID");return end
        local item,sourceErr=service:GetItem(tonumber(id),70450)
        if not item then tell("Item: "..sourceErr);return end
        local live,err=service:GetClientItemLink(tonumber(id),70450)
        if live then
            tell("#"..id.." "..live.itemLink.." [current-client link verified; snapshot name: "..
                (item.name or "UNKNOWN").."]")
        else
            tell("#"..id.." "..(item.name or "[NAME UNKNOWN]").."; no verified itemlink: "..err)
            if err=="CLIENT_ITEM_INFO_NOT_CACHED_OR_UNAVAILABLE" then
                local requested,reqErr=service:RequestClientItemData(tonumber(id),70450)
                tell(requested and "Client cache lookup requested; retry itemprobe70450 later" or
                    "Cache lookup not started: "..tostring(reqErr))
            end
        end
    elseif verb=="itemlinks70450" then
        local id,offset=msg:match("^itemlinks70450%s+(%d+)%s*(%d*)$")
        if not id then tell("Usage: /jlp itemlinks70450 ITEM_ID [OFFSET]");return end
        local p,err=service:GetRelations(tonumber(id),tonumber(offset) or 0,12,70450)
        if not p then tell("Links: "..err);return end
        tell("Item "..id.." links "..p.totalRelations.."; from "..p.offset.."; no acquisition verified")
        for _,r in ipairs(p.rows) do
            tell(" "..r.relation.." "..(r.professionKey or "ITEM").." "..
                tostring(r.spellID or r.relatedItemID or "?")..
                (r.itemEffectID and " effect="..r.itemEffectID or ""))
        end
    elseif verb=="itemscan70450" then
        local offset=msg:match("^itemscan70450%s*(%d*)$")
        if offset==nil then tell("Usage: /jlp itemscan70450 [OFFSET]");return end
        local page,err=service:ScanMissingNames(tonumber(offset) or 0,70450)
        if not page then tell("Scan: "..err);return end
        tell("Unresolved source names: "..page.totalMatches.."; scan offset "..page.offset.." (12 max, no saved changes)")
        for _,r in ipairs(page.rows) do
            tell(" #"..r.itemID.." "..(r.itemLink or "[SOURCE NAME UNKNOWN]").." "..r.status..
                (r.requestStatus and " / "..r.requestStatus or ""))
        end
    elseif verb=="itemissues70450" then
        local offset=msg:match("^itemissues70450%s*(%d*)$")
        local p,err=service:GetPage(tonumber(offset) or 0,12,70450,{missingNamesOnly=true})
        if not p then tell("Issues: "..err);return end
        tell("Missing names: "..p.totalMatches.."; from "..p.offset)
        for _,r in ipairs(p.rows) do tell("  #"..r.itemID.." "..r.nameEvidence) end
    else
        tell("Usage: /jlp itemcover70450 | itemmeta70450 ID | itemprobe70450 ID | itemlinks70450 ID [OFFSET] | itemissues70450 [OFFSET] | itemgaps70450 [OFFSET] | itemaudit70450 ID | itemscan70450 [OFFSET]")
    end
end
JLP:RegisterModule("ItemMetadataCommand70450",Command)
