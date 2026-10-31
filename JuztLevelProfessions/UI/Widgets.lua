local _, JLP = ...
local Widgets = {}

local function color(name)
    return JLP.UITheme:Color(name)
end

-- Both Gathering map entrypoints use this read-only, theme-safe status text.
-- Receipt lifecycle and native permission remain with route services.
function Widgets:GatheringFeedback(model,receipt)
    local presenter=JLP:GetModule("GatheringRoutePresentation")
    if presenter and type(presenter.Feedback)=="function" then
        return presenter:Feedback(model,receipt)
    end
    return type(receipt)=="table" and receipt.message or (model and model.header),
        type(receipt)=="table" and receipt.detail or (model and model.detail)
end

-- Provenance wording is presentation-only and cannot promote research to live evidence.
function Widgets:GatheringLegend()
    return {full=JLP.UITheme.gathering.legend,
        short="Historical pins: prior references / observations, not live spawns",
        readOnly=true,nativeDispatchAllowed=false}
end

-- Shared read-only recovery guidance for both Gathering map canvases.
-- Never implies that historical nodes are current/live or that a retry is native work.
function Widgets:GatheringMapFailure(status)
    local messages={
        MAP_ID_INVALID={"Map ID unavailable", "Select a supported zone; no map data was changed"},
        MAP_UNAVAILABLE={"Map unavailable", "Select a client-supported zone before planning"},
        MAP_ART_FETCH_ERROR={"Map tiles could not be loaded", "Try a map refresh or select another zone"},
        MAP_SERVICE_UNAVAILABLE={"Map service unavailable", "Blizzard map data is not accessible here"},
        ART_UNAVAILABLE={"Map artwork unavailable", "Try a map refresh or select another zone"},
        ART_RENDER_FAILED={"Map tiles could not be drawn", "Partial map art was invalidated; retry map refresh"},
        ART_RENDER_INCOMPLETE={"Map tiles are incomplete", "The client returned fewer map tiles than expected; retry map refresh"},
        ART_OVERLAY_FAILED={"Map markers could not be drawn", "Partial pin and route display was cleared; retry refresh"},
    }
    local info=messages[status] or {"Map artwork unavailable", "Select another client-supported zone"}
    return {status=status or "ART_UNAVAILABLE",title=info[1],detail=info[2],
        ready=false,readOnly=true,nativeDispatchAllowed=false}
end

-- Shared display-only map-art recovery control for both viewers.
-- Never starts gathering, crafting or native route execution.
function Widgets:GatheringMapRetryAction(hasZone,ready)
    local label=not hasZone and "Choose Zone" or (ready and "Reload Map" or "Retry Map")
    return {label=label,enabled=hasZone==true,readOnly=true,nativeDispatchAllowed=false}
end

-- Ephemeral, map-bound manual retry intent. A retry clicked for zone A must
-- never turn into an unrelated forced C_Map fetch when the next refresh is B.
-- Navigation refreshes without a manual target preserve their own semantics.
function Widgets:GatheringMapFetchIntent(requested,manualTargetMapID,currentMapID)
    -- No manual fetch may migrate from zone A to B. A nil target remains the
    -- existing navigation-triggered (nonmanual) refresh contract.
    local dropped=requested==true and manualTargetMapID~=nil and
        manualTargetMapID~=currentMapID
    return {forceArtFetch=requested==true and currentMapID~=nil and not dropped,
        dropped=dropped,reason=dropped and "RETRY_ZONE_CHANGED" or nil,
        readOnly=true,nativeDispatchAllowed=false}
end

-- Display-only context for Why this route in both Gathering viewers. This
-- receipt never infers live spawn presence, required skill or action authority.
function Widgets:GatheringRouteEvidence(snapshot,workflow,options,mapID)
    -- A snapshot from another zone is never a source for this map's route
    -- explanation. Do not mutate it, reload DB or infer current spawns.
    local stale=type(snapshot)=="table" and snapshot.mapID~=nil and
        mapID~=snapshot.mapID
    local summary=self:GatheringPointSummary(stale and nil or snapshot)
    local stage=workflow=="GENERATING" and "Route calculation in progress (preview, NOT ready)" or
        workflow=="READY" and "Route calculation committed (advisory only)" or
        workflow=="CANCELLED" and "Route cancelled; no committed route from this attempt" or
        workflow=="EMPTY" and "No eligible route nodes for this selection" or
        workflow=="ERROR" and "Route calculation failed; review resources and retry" or
        "No committed route for this map and resource selection"
    if stale then stage="Map changed; this route evidence is stale (NOT ready)" end
    local note=stale and "The displayed references belong to another map; refresh this map before interpreting the counts." or
        summary.total==0 and
        "No eligible POINT references for the current layers/filters; Fishing and Skinning AREA evidence cannot create route nodes." or
        ("Candidate reference locations: "..summary.historicalOnly.." historical and "..
        summary.personal.." personally observed. Prior observations are NOT guaranteed current spawns.")
    local context="Map, mode and resource filters unavailable"
    local savedCount,effectiveCount,inactiveSavedCount=0,0,0
        local layerBreakdown={}
    if type(options)=="table" then
        local mode=options.mode=="SMART_PROFESSION" and "Smart Profession" or
            options.mode=="CUSTOM_LOOP" and "Custom Loop" or "Unknown (planning disabled)"
        local smart=options.mode=="SMART_PROFESSION"
        local focus=options.focus=="MATERIALS" and "Materials" or
            options.focus=="SKILL" and "Skill" or
            options.focus=="BALANCED" and "Balanced" or "Unknown"
        local source=options.routeSource=="OBSERVED_ONLY" and "Personally observed only" or
            options.routeSource=="PREFER_OBSERVED" and "Prefer personally observed" or
            options.routeSource=="ALL" and "All historical and personal references" or
            "Unknown source filter (review before planning)"
        local layers={}
        local byMap=type(options.resourceSelectionsByMap)=="table" and
            options.resourceSelectionsByMap[mapID] or nil
        local explicitlyFiltered=false
        local activeExplicit=false
        for _,profession in ipairs({"HERBALISM","MINING"}) do
            local enabled=type(options.layerEnabled)=="table" and
                options.layerEnabled[profession]==true
            if enabled then layers[#layers+1]=profession=="HERBALISM" and "Herbalism" or "Mining" end
            local selected=type(byMap)=="table" and byMap[profession] or nil
            if type(selected)=="table" then
                explicitlyFiltered=true
                if enabled and not smart then activeExplicit=true end
                local selectedCount=0
                for _,isSelected in pairs(selected) do
                    if isSelected==true then
                        selectedCount=selectedCount+1
                        savedCount=savedCount+1
                        if enabled and not smart then effectiveCount=effectiveCount+1
                        else inactiveSavedCount=inactiveSavedCount+1 end
                    end
                end
                local name=profession=="HERBALISM" and "Herbalism" or "Mining"
                layerBreakdown[#layerBreakdown+1]=name..": "..selectedCount..
                    (not enabled and " saved (layer off)" or
                     smart and " saved (Smart planner separate)" or " effective")
            end
        end
        local selection="Resource selection: all eligible within active filters"
        if explicitlyFiltered then
            selection="Explicit resource choices: "..savedCount..
                " saved, "..effectiveCount.." effective for active layers"
            if smart then
                selection=selection.." (Smart Profession uses its own candidate selection)"
            elseif not activeExplicit then
                selection=selection.." (saved choices belong to disabled layers)"
            end
        end
        context="Mode: "..mode.." · Focus: "..focus..
            "\nRoute sources: "..source.." · Layers: "..
            (#layers>0 and table.concat(layers,", ") or "none enabled")..
            "\n"..selection..". Historical references are not a skill guarantee."
        if #layerBreakdown>0 then
            context=context.."\nPer-layer resource choices: "..table.concat(layerBreakdown,"; ")
        end
        if stale then context="STALE MAP EVIDENCE · "..context end
    end
    return {title=stage,detail=note,context=context,readOnly=true,
        savedSelectionCount=savedCount,effectiveSelectionCount=effectiveCount,
        inactiveSavedCount=inactiveSavedCount,
        stale=stale==true,nativeDispatchAllowed=false}
end

-- Summary from the ALREADY BUILT, source-filtered overlay receipt. No new
-- snapshot scan on refresh. Historical references and personal evidence are
-- never advertised as live spawns; AREA research is not a point coordinate.
function Widgets:GatheringPointSummary(snapshot)
    local total=type(snapshot)=="table" and math.max(0,tonumber(snapshot.total) or 0) or 0
    local personal=type(snapshot)=="table" and math.max(0,math.min(total,tonumber(snapshot.observationCount) or 0)) or 0
    local label
    if total==0 then
        label="No eligible POINT markers · check layers, zone and resource filters; Fishing/Skinning AREA is not a node"
    else
        label="Historical-only "..tostring(total-personal).." · personally observed "..tostring(personal)..
            " · prior evidence, not active spawns"
    end
    return {label=label,total=total,personal=personal,historicalOnly=total-personal,
        readOnly=true,nativeDispatchAllowed=false}
end

-- One source-qualified resource receipt used by standalone and embedded.
-- The map layer is the sole learned/enabled authority; saved choices can be
-- retained while disabled without becoming candidate/production permission.
function Widgets:GatheringResourceSelectionFeedback(layer,selectedCount,mode,matchingCount,totalCount)
    local saved=math.max(0,math.floor(tonumber(selectedCount) or 0))
    local learned=type(layer)=="table" and layer.learned==true
    local enabled=learned and layer.enabled==true
    local smart=mode=="SMART_PROFESSION"
    local effective=(enabled and not smart) and saved or 0
    local label=not learned and "Not learned" or not enabled and "Layer off" or
        smart and "Smart candidates independent" or "Custom resources"
    local text=label.." · "..tostring(effective).." effective · "..
        tostring(saved).." saved"
    if type(totalCount)=="number" then
        text=text.." / "..tostring(totalCount).." types"
        if type(matchingCount)=="number" and matchingCount<totalCount then
            text=text.." · "..tostring(matchingCount).." matches"
        end
    end
    return {text=text,saved=saved,effective=effective,learned=learned,
        enabled=enabled,smartIndependent=smart,readOnly=true,nativeDispatchAllowed=false}
end

-- A material estimate is not bag withdrawal or an acquisition instruction.
-- Split compact counts from the source note so narrow secondary cards do not
-- concatenate every field into a single unbounded line.
function Widgets:MaterialAdvisoryLines(row)
    if type(row)~="table" then return "No qualified material evidence", "Verify source manually" end
    local name=tostring(row.name or "Unnamed reference")
    -- Alchemy candidate materials and secondary leveling plans have distinct
    -- source-qualified field contracts. Do not display a missing secondary
    -- estimate as zero inventory or 'undocumented' when Alchemy has evidence.
    -- This is informational only; an UNKNOWN bank is never coerced to zero.
    local alchemy=row.grossRequired~=nil or row.bagsAvailable~=nil or row.sourceText~=nil
    local bankQuantity=alchemy and row.currentBankAvailable or row.bank
    local bankQualified=row.bankKnown==true and type(bankQuantity)=="number" and
        bankQuantity==bankQuantity and bankQuantity>=0 and bankQuantity<math.huge and
        bankQuantity==math.floor(bankQuantity) and row.snapshotStale~=true and
        row.bankStale~=true and row.materialDecisionStatus~="STALE"
    local stale=row.snapshotStale==true or row.bankStale==true or
        row.materialDecisionStatus=="STALE"
    local bank=stale and "STALE" or
        (bankQualified and tostring(bankQuantity) or "UNKNOWN")
    local headline,detail,source
    if alchemy then
        headline=name..(row.sourceVerifiedPerCraft and " · ESTIMATED gross " or " · required ")..
            tostring(row.grossRequired or "UNKNOWN")
        local observed=row.bagsAvailable
        local bagsKnown=row.bagsKnown~=false and row.snapshotStale~=true and
            type(observed)=="number" and
            observed==observed and observed>=0 and observed<math.huge and
            observed==math.floor(observed)
        detail="Bags "..(bagsKnown and tostring(observed) or "UNKNOWN").." · bank "..bank..
            " · external "..tostring(row.externalRequired or "UNKNOWN")
        source=tostring(row.sourceText or "Source undocumented")
        if row.sourceVerifiedPerCraft==true then
            source="SOURCE-VERIFIED REAGENT: "..tostring(row.perCraft)..
                " per craft × HISTORICAL ESTIMATE "..tostring(row.estimatedCraftCount)..
                " crafts; gross/missing are CONDITIONAL. "..source
        end
    else
        headline=name.." · guide ~"..tostring(row.guideEstimate or "?")
        local observed=row.bags
        local bagsKnown=row.bagsKnown==true and row.snapshotStale~=true and
            type(observed)=="number" and
            observed==observed and observed>=0 and observed<math.huge and
            observed==math.floor(observed)
        local bags=bagsKnown and tostring(observed) or "UNKNOWN"
        local missing=row.externalNeededIfGuideEstimateHolds
        detail="Bags "..bags.." · bank "..bank..
            " · estimated external "..(missing~=nil and ("~"..tostring(missing)) or "UNKNOWN")
        if row.externalUpperBoundIfBankUnknown~=nil then
            detail=detail.." · upper bound if bank has zero: ~"..
                tostring(row.externalUpperBoundIfBankUnknown)
        end
        source=tostring(row.source or "Source undocumented")
    end
    local bands={}
    for _,step in ipairs(row.recipeBands or {}) do
        if type(step)=="table" and type(step.recipe)=="string" then
            bands[#bands+1]=step.recipe.." ("..tostring(step.skillMin or "?").."-"..tostring(step.skillMax or "?")..")"
        end
    end
    local linked=#bands>0 and (" · recipe: "..table.concat(bands, "; ")) or
        " · recipe attribution unavailable"
    return headline,detail.." | "..source.." · procurement manual",linked
end
-- Presentation-only, bounded materials decision list. No new planner,
-- inventory authority, price data, or SavedVariables; consumers page existing
-- qualified rows. UNKNOWN is never coerced into KNOWN_ZERO.
-- Source-aware presentation adapter. Its result has NO inventory or execution
-- authority; source modules remain the only owners of qualified observations.
-- Do not infer a known zero from missing, invalid, or stale stock fields.
local function wholeStock(value)
    return type(value)=="number" and value==value and value>=0 and
        value<math.huge and value==math.floor(value) and value or nil
end
function Widgets:NormalizeMaterialDecision(row)
    if type(row)~="table" then return nil end
    local guide=row.grossRequired~=nil or row.bagsAvailable~=nil or
        row.sourceVerifiedPerCraft==true
    local bagsValue=wholeStock(guide and row.bagsAvailable or row.bags)
    -- Guide's source-qualified bagsAvailable predates the explicit bagsKnown
    -- field. If present, bagsKnown overrides the legacy field, never vice versa.
    local bagsKnown=(row.bagsKnown==true or (guide and row.bagsKnown==nil)) and
        bagsValue~=nil and row.snapshotStale~=true
    local bankValue=wholeStock(guide and row.currentBankAvailable or row.bank)
    local stale=row.snapshotStale==true or row.bankStale==true or
        row.materialDecisionStatus=="STALE"
    local bankKnown=row.bankKnown==true and bankValue~=nil and not stale
    local gross=wholeStock(guide and row.grossRequired or row.guideEstimate)
    local perCraft=wholeStock(row.perCraft)
    local crafts=wholeStock(guide and row.estimatedCraftCount or row.expectedCrafts)
    local sourceVerified=(row.sourceVerifiedPerCraft==true or
        (not guide and type(row.sourceURL)=="string" and row.sourceURL~="" and
         type(row.recipeBands)=="table" and #row.recipeBands>0)) and
        perCraft~=nil and perCraft>0 and crafts~=nil and crafts>0 and
        gross~=nil and gross==perCraft*crafts
    local missing=nil
    if sourceVerified and gross~=nil and bagsKnown and bankKnown and not stale then
        missing=math.max(0,gross-bagsValue-bankValue)
    end
    return {readOnly=true,nativeDispatchAllowed=false,
        itemID=wholeStock(row.itemID),name=tostring(row.name or "Material"),
        perCraft=perCraft,expectedCrafts=crafts,gross=gross,missing=missing,
        sourceVerified=sourceVerified,stale=stale,
        bags=bagsKnown and (bagsValue>0 and tostring(bagsValue) or "KNOWN_ZERO") or "BAGS_UNKNOWN",
        bank=stale and "STALE" or bankKnown and
            (bankValue>0 and tostring(bankValue) or "KNOWN_ZERO") or "BANK_UNKNOWN"}
end
function Widgets:MaterialDecisionList(rows,selected,maxRows)
    local lines={}
    local count=0
    local limit=math.max(1,math.min(12,tonumber(maxRows) or 8))
    for i,row in ipairs(type(rows)=="table" and rows or {}) do
        if type(row)=="table" then
            count=count+1
            if count<=limit then
                local q=self:NormalizeMaterialDecision(row)
                local code=q.itemID and q.itemID>0 and ("item "..q.itemID) or "ITEM_UNAVAILABLE"
                lines[#lines+1]=(i==selected and "> " or "  ")..q.name..
                    " ["..code.."] ×"..tostring(q.perCraft or "?")..
                    "/craft (source "..(q.sourceVerified and "qualified" or "UNAVAILABLE")..")"..
                    " · ~"..tostring(q.expectedCrafts or "?")..
                    " crafts (guide estimate) · gross ~"..tostring(q.gross or "UNKNOWN")..
                    " · missing "..(q.missing~=nil and ("~"..q.missing) or "UNKNOWN")..
                    " · bags "..q.bags.." · bank "..q.bank
            end
        end
    end
    if count>limit then lines[#lines+1]="More reagents: use the existing material pager" end
    if #lines==0 then return "SOURCE_UNAVAILABLE · no qualified reagent rows" end
    return table.concat(lines,"\n")
end
-- Source/recipe detail is strictly informational and uses the same widget
-- contract in Guide and Secondaries. Never performs an action or opens the AH.
function Widgets:AdvisoryMaterialTooltip(owner,row)
    if not owner or not owner.SetScript then return false end
    -- Preserve existing Button hover/focus scripts instead of shadowing them.
    if not owner.__jlpAdvisoryTooltipInstalled then
        owner.__jlpAdvisoryOriginalEnter=owner.GetScript and owner:GetScript("OnEnter")
        owner.__jlpAdvisoryOriginalLeave=owner.GetScript and owner:GetScript("OnLeave")
        owner.__jlpAdvisoryTooltipInstalled=true
    end
    local priorEnter=owner.__jlpAdvisoryOriginalEnter
    local priorLeave=owner.__jlpAdvisoryOriginalLeave
    owner:SetScript("OnEnter",function(control,...)
        if type(priorEnter)=="function" then pcall(priorEnter,control,...) end
        if not GameTooltip or not GameTooltip.SetOwner then return end
        GameTooltip:SetOwner(control,"ANCHOR_RIGHT")
        if GameTooltip.ClearLines then GameTooltip:ClearLines() end
        local title,detail,recipes=self:MaterialAdvisoryLines(row)
        if GameTooltip.AddLine then
            GameTooltip:AddLine(title or "Qualified material",0.45,0.85,1,true)
            GameTooltip:AddLine(detail or "Source unavailable",1,1,1,true)
            GameTooltip:AddLine(recipes or "Recipe attribution unavailable",1,0.82,0.42,true)
            if type(row)=="table" and type(row.sourceURL)=="string" then
                GameTooltip:AddLine(row.sourceURL,0.7,0.85,1,true)
            end
        end
        if GameTooltip.Show then GameTooltip:Show() end
    end)
    owner:SetScript("OnLeave",function(control,...)
        if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(control)
        elseif GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==control then GameTooltip:Hide() end
        if type(priorLeave)=="function" then pcall(priorLeave,control,...) end
    end)
    return true
end

-- A material detail is permission to inspect read-only pages, never to
-- request a scan, a purchase, a withdrawal or a craft. Fail closed on absent
-- recipe/material identity; do not infer a zero from an UNKNOWN snapshot.
function Widgets:QualifiedMaterialReference(row)
    if type(row)~="table" then return nil,"NO_SOURCE_QUALIFIED_MATERIAL" end
    local id=tonumber(row.itemID)
    local required=wholeStock(row.grossRequired or row.guideEstimate)
    if not id or id~=id or id==math.huge or id<=0 or id%1~=0 or
        not required or required<=0 then
        return nil,"MATERIAL_ID_OR_NEED_UNQUALIFIED"
    end
    return {itemID=id,name=tostring(row.name or ("Item "..id)),required=required,
        bagStock=((row.bagsKnown==true or
            (row.bagsKnown==nil and row.bagsAvailable~=nil)) and
            row.snapshotStale~=true and
            wholeStock(row.bagsAvailable~=nil and row.bagsAvailable or row.bags)) or nil,
        bankStock=(row.bankKnown==true and row.bankStale~=true and
            row.snapshotStale~=true and row.materialDecisionStatus~="STALE") and
            wholeStock(row.currentBankAvailable~=nil and row.currentBankAvailable or row.bank) or nil,
        bankKnown=row.bankKnown==true and row.bankStale~=true and
            row.snapshotStale~=true and row.materialDecisionStatus~="STALE" and
            wholeStock(row.currentBankAvailable~=nil and row.currentBankAvailable or row.bank)~=nil,
        source=tostring(row.sourceText or row.source or "UNKNOWN"),
        manualOnly=true,readOnly=true,nativeDispatchAllowed=false},nil
end
-- Exact transient identity for one source-qualified material. Equivalent
-- material rows recreated by Refresh may retain their scroll; changed recipe,
-- source or inventory estimates MUST invalidate old details, even at same count.
function Widgets:MaterialReferenceIdentity(row)
    if type(row)~="table" then return nil end
    local r=self:QualifiedMaterialReference(row)
    if not r then return nil end
    local parts={tostring(r.itemID),tostring(r.required),tostring(r.bagStock),
        tostring(r.bankKnown),tostring(r.bankStock),tostring(r.source),
        tostring(row.sourceURL),tostring(row.externalRequired),
        tostring(row.externalNeededIfGuideEstimateHolds),
        tostring(row.externalUpperBoundIfBankUnknown),tostring(row.bagsKnown),
        tostring(row.materialDecisionStatus),
        tostring(row.referenceProfessionKey),tostring(row.perCraft),
        tostring(row.estimatedCraftCount),tostring(row.sourceVerifiedPerCraft),
        tostring(row.selectedRecipeID),tostring(row.selectedSkillMin),
        tostring(row.selectedSkillTarget),tostring(row.outputQuantity),
        tostring(row.snapshotStale),tostring(row.bankStale),tostring(row.bagsAvailable),
        tostring(row.bank),tostring(row.bags),tostring(row.bankKnown)}
    for _,band in ipairs(type(row.recipeBands)=="table" and row.recipeBands or {}) do
        parts[#parts+1]=table.concat({tostring(band.recipe),tostring(band.recipeID),
            tostring(band.skillMin),tostring(band.skillMax),tostring(band.sourceURL)},":")
    end
    return table.concat(parts,"|")
end
-- One bounded informational source sheet usable by secondaries and guide consumers.
-- The owner decides visibility and receipt validity; this widget owns no saved
-- variables, inventory actions, native dispatch or background polling.
function Widgets:AdvisorySourceSheet(parent,width,height)
    if not parent or type(CreateFrame)~="function" then return nil end
    width=math.max(180,tonumber(width) or 344)
    height=math.max(120,tonumber(height) or 350)
    local sheet=CreateFrame("Frame",nil,parent)
    sheet:SetSize(width,height)
    self:Fill(sheet,"panelAlt")
    self:Border(sheet,"border",1)
    local title=self:Label(sheet,"Source-qualified recipe evidence · read-only","GameFontHighlight")
    title:SetPoint("TOPLEFT",12,-12)
    title:SetWidth(width-72)
    if title.SetWordWrap then title:SetWordWrap(true) end
    local close=self:Button(sheet,"Close",52)
    close:SetSize(52,24)
    close:SetPoint("TOPRIGHT",-8,-7)
    local viewport=CreateFrame("ScrollFrame",nil,sheet)
    -- A read-only material lookup can fail because the owner or source is
    -- no longer current. Reserve feedback space, rather than silently doing
    -- nothing on an AH/Bank click inside a SourceSheet.
    local decisionStatus=self:Label(sheet,"Manual decision · no scan, price or withdrawal",
        "GameFontHighlightSmall")
    decisionStatus:SetPoint("TOPLEFT",12,-44)
    decisionStatus:SetWidth(width-24)
    if decisionStatus.SetWordWrap then decisionStatus:SetWordWrap(true) end
    viewport:SetPoint("TOPLEFT",12,-67)
    viewport:SetPoint("BOTTOMRIGHT",-26,42)
    if viewport.EnableMouseWheel then viewport:EnableMouseWheel(true) end
    local content=CreateFrame("Frame",nil,viewport)
    content:SetSize(width-24,800)
    if viewport.SetScrollChild then viewport:SetScrollChild(content) end
    local text=self:Label(content,"No qualified source", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT",0,0)
    text:SetWidth(width-30)
    if text.SetWordWrap then text:SetWordWrap(true) end
    -- A dedicated thumb replaces the former Up/Down buttons. Mousewheel and
    -- hardware drag/click share the existing native scroll offset.
    local scrollBar=JLP.UILayout and JLP.UILayout:AttachNativeScrollbar(viewport,
        {owner=sheet,right=-11,top=-67,bottom=42,gutter=10})
    -- Two hardware-click-only links to the existing read-only pages. The
    -- source owner supplies navigation; this widget owns no page or snapshot.
    local bankLink=self:Button(sheet,"Review Bank",126)
    bankLink:SetSize(126,23); bankLink:SetPoint("BOTTOMLEFT",12,10)
    local ahLink=self:Button(sheet,"Review AH snapshot",142)
    ahLink:SetSize(142,23); ahLink:SetPoint("BOTTOMRIGHT",-12,10)
    local function bounds()
        local contentHeight=content.GetHeight and content:GetHeight() or 800
        local visibleHeight=viewport.GetHeight and viewport:GetHeight() or height-88
        if type(visibleHeight)~="number" or visibleHeight<=0 then visibleHeight=height-88 end
        return math.max(0,contentHeight-visibleHeight)
    end
    local function updateButtons()
        if scrollBar then scrollBar:Refresh() end
    end
    local function scroll(delta)
        if not viewport.SetVerticalScroll or not viewport.GetVerticalScroll then return end
        viewport:SetVerticalScroll(math.max(0,math.min(bounds(),(viewport:GetVerticalScroll() or 0)+delta)))
        updateButtons()
    end
    viewport:SetScript("OnMouseWheel",function(_,delta) scroll(-(delta or 0)*36) end)
    sheet:SetScript("OnMouseWheel",function(_,delta) scroll(-(delta or 0)*36) end)
    -- The parent may reflow after this sheet was created. Measurements stay
    -- owner-relative and never change source qualification or link authority.
    function sheet:ApplyBounds(newWidth,newHeight)
        local w=tonumber(newWidth) or width
        local h=tonumber(newHeight) or height
        if w<180 or h<180 then return false end
        width=w;height=h
        self:SetSize(w,h)
        title:SetWidth(math.max(1,w-(self.__jlpHideClose and 24 or 72)))
        decisionStatus:SetWidth(math.max(1,w-24))
        -- Compact host cards must not overlap the two independent footer rows.
        -- Their native click owners remain unchanged; only widths/labels adapt.
        local compact=w<315
        local half=math.max(70,math.floor((w-32)/2))
        for _,b in ipairs({bankLink,ahLink}) do
            if b.SetWidth then b:SetWidth(compact and half or
                (b==bankLink and 126 or 142)) end
        end
        if bankLink.SetText then bankLink:SetText(compact and "Bank" or "Review Bank") end
        if ahLink.SetText then ahLink:SetText(compact and "AH snapshot" or "Review AH snapshot") end
        content:SetWidth(math.max(1,w-40))
        text:SetWidth(math.max(1,w-42))
        -- A narrower host may wrap more text without a new source receipt.
        -- Preserve the current offset, but expand the scroll child if needed.
        if text.GetStringHeight then
            local ok,measured=pcall(text.GetStringHeight,text)
            if ok and tonumber(measured) and measured>0 then
                local visible=viewport.GetHeight and tonumber(viewport:GetHeight()) or h-109
                content:SetHeight(math.max(1,visible or (h-109),measured+28))
            end
        end
        local limit=bounds()
        if viewport.GetVerticalScroll and viewport.SetVerticalScroll then
            viewport:SetVerticalScroll(math.min(limit,math.max(0,viewport:GetVerticalScroll() or 0)))
        end
        updateButtons()
        return true
    end
    local receipt={frame=sheet,viewport=viewport,content=content,text=text,close=close,
        scrollbar=scrollBar,bankLink=bankLink,ahLink=ahLink,
        decisionStatus=decisionStatus,
        readOnly=true,nativeDispatchAllowed=false}
    function receipt:SetCloseButtonVisible(visible)
        local show=visible~=false
        self.frame.__jlpHideClose=not show
        self.close:SetShown(show)
        title:SetWidth(math.max(1,width-(show and 72 or 24)))
    end
    -- Host owns geometry.  FitHost does not change qualified-source receipts,
    -- scroll content, or native actions; it only recomputes the visible bounds.
    local authoredWidth,authoredHeight=width,height
    function receipt:FitHost()
        local w=parent.GetWidth and tonumber(parent:GetWidth()) or width+24
        local h=parent.GetHeight and tonumber(parent:GetHeight()) or height+80
        if not w or w<=0 then w=width+24 end
        if not h or h<=0 then h=height+80 end
        return sheet:ApplyBounds(math.max(180,math.min(authoredWidth,w-24)),
            math.max(180,math.min(authoredHeight,h-80)))
    end
    if parent.HookScript then
        parent:HookScript("OnSizeChanged",function() receipt:FitHost() end)
    end
    function receipt:SetNavigation(callback)
        self.onNavigate=type(callback)=="function" and callback or nil
    end
    local function manualReference(target)
        local current=receipt.currentReference
        if not current or not receipt.onNavigate or not receipt.frame:IsShown() then
            return false,"SOURCE_UNAVAILABLE"
        end
        local ok,reason=receipt.onNavigate(target,current)
        if not ok and receipt.decisionStatus then
            receipt.decisionStatus:SetText("Inspection unavailable: "..
                tostring(reason or "SOURCE_CHANGED").." · Return/reopen source")
        end
        return ok==true,reason
    end
    bankLink:SetScript("OnClick",function() manualReference("Bank") end)
    ahLink:SetScript("OnClick",function() manualReference("Auction House") end)
    local function updateNavigation()
        local enabled=receipt.currentReference~=nil and receipt.onNavigate~=nil
        for _,b in ipairs({bankLink,ahLink}) do
            if b.SetEnabled then b:SetEnabled(enabled) end
            if b.SetAlpha then b:SetAlpha(enabled and 1 or 0.45) end
        end
    end
    function receipt:Reset()
        self.frame:Hide()
        self.currentReference=nil
        self.currentRow=nil
        self.currentIdentity=nil
        if self.decisionStatus then
            self.decisionStatus:SetText("Manual decision · no scan, price or withdrawal")
        end
        local layout=JLP.UILayout
        if layout and layout.ReturnToScrollOrigin then layout:ReturnToScrollOrigin(self.viewport)
        elseif self.viewport.SetVerticalScroll then self.viewport:SetVerticalScroll(0) end
        self.text:SetText("No current qualified recipe evidence")
        -- A previous long recipe may have left thousands of scroll units.
        -- Unavailable evidence must not keep an active empty scrollbar.
        local visible=self.viewport.GetHeight and self.viewport:GetHeight() or height-88
        self.content:SetHeight(math.max(1,tonumber(visible) or height-88))
        updateButtons();updateNavigation()
    end
    function receipt:SetRow(row,decisionRows,selectedMaterial)
        if type(row)~="table" then
            self:Reset()
            return {readOnly=true,nativeDispatchAllowed=false,status="REFERENCE_UNAVAILABLE"}
        end
        local head,source,recipes=Widgets:MaterialAdvisoryLines(row)
        self.currentReference=Widgets:QualifiedMaterialReference(row)
        self.currentRow=row
        self.currentIdentity=Widgets:MaterialReferenceIdentity(row)
        if self.decisionStatus then
            self.decisionStatus:SetText("Manual Bank/AH review · snapshot is not a live item quote")
        end
        updateNavigation()
        -- Name the evidence contract without giving it production authority.
        -- This source sheet is shared by Alchemy Guide and both Secondaries.
        if title.SetText then
            local profession=tostring(row.referenceProfessionKey or ""):upper()
            title:SetText((profession~="" and profession~="ALCHEMY") and
                (profession.." research reference · read-only") or
                (row.grossRequired~=nil or row.sourceText~=nil) and
                "Alchemy candidate material · read-only" or
                "Secondary material · recipe evidence · read-only")
        end
        local url=row.sourceURL
        -- All verified reagents of the chosen step are visible in this
        -- already-bounded scroll viewport; per-reagent actions still use the
        -- existing pager and only the CURRENT qualified receipt.
        local decisions=type(decisionRows)=="table" and
            ("QUALIFIED MATERIALS ON THIS PAGE · selected "..
             tostring(selectedMaterial or "?").."/"..tostring(#decisionRows)..
             " · manual only\n"..
                Widgets:MaterialDecisionList(decisionRows,selectedMaterial,12).."\n\n") or ""
        local detail=decisions.."MATERIAL\n"..tostring(head).."\n\nSOURCE & STOCK\n"..
            tostring(source).."\n\nQUALIFIED RECIPES\n"..tostring(recipes)..
            "\n\nAcquisition is manual. Bag/bank estimates are not withdrawals or purchases."
        if type(url)=="string" and url~="" then detail=detail.."\nReference: "..url end
        text:SetText(detail)
        -- WoW may resolve line heights only on the next frame. Use a bounded
        -- generous content height so long localized rows remain scrollable;
        -- never allow text to paint over the surrounding material controls.
        local measured=nil
        if text.GetStringHeight then
            local ok,value=pcall(text.GetStringHeight,text)
            if ok then measured=value end
        end
        local layout=JLP.UILayout
        local estimated=layout and layout.AdvisoryTextContentHeight and
            layout:AdvisoryTextContentHeight(detail,viewport:GetHeight() or height-109,measured) or
            math.max(viewport:GetHeight() or height-109,math.min(8000,math.ceil(#detail/45)*20+120))
        content:SetHeight(estimated)
        local layout=JLP.UILayout
        if layout and layout.ReturnToScrollOrigin then layout:ReturnToScrollOrigin(viewport)
        elseif viewport.SetVerticalScroll then viewport:SetVerticalScroll(0) end
        updateButtons()
        return {readOnly=true,nativeDispatchAllowed=false,text=detail}
    end
    receipt:FitHost()
    sheet:Hide()
    return receipt
end

-- Pure, read-only reference context in the existing Bank/AH page chrome.
-- Missing data NEVER becomes a verified zero/price. No purchasing or scanning.
-- A known full bank snapshot may qualify absence as zero; an absent,
-- unowned or malformed snapshot may NEVER qualify absence as zero.
function Widgets:ValidReadOnlyMaterialID(itemID)
    return type(itemID)=="number" and itemID==itemID and itemID>0 and
        itemID<2147483648 and itemID%1==0
end
function Widgets:QualifiedBankMaterialCount(snapshot,itemID)
    local id=tonumber(itemID)
    if type(snapshot)~="table" or snapshot.known~=true or
        type(snapshot.items)~="table" or not id or id~=id or id<=0 or
        id==math.huge or id%1~=0 then return nil end
    local count=snapshot.items[id]
    if count==nil then count=snapshot.items[tostring(id)] end
    if count==nil then return 0 end
    if type(count)~="number" or count~=count or count==math.huge or
        count<0 or count%1~=0 then return nil end
    return count
end
-- WoW supports UTF-8 localized names; bytewise sub can bisect multibyte
-- glyphs. Cap by characters, never promote arbitrary control bytes to labels.
function Widgets:BoundedUTF8Label(value,maximum)
    if type(value)~="string" then return "Material" end
    maximum=math.max(1,math.min(96,math.floor(tonumber(maximum) or 26)))
    local i,n,total=1,#value,0
    while i<=n and total<maximum do
        local b=value:byte(i)
        local width=b<128 and 1 or b>=194 and b<=223 and 2 or
            b>=224 and b<=239 and 3 or b>=240 and b<=244 and 4 or 0
        if width==0 or i+width-1>n then break end
        local valid=true
        for j=i+1,i+width-1 do
            local continuation=value:byte(j)
            if not continuation or continuation<128 or continuation>191 then valid=false;break end
        end
        if not valid then break end
        i=i+width;total=total+1
    end
    return value:sub(1,i-1)..(i<=n and "…" or "")
end
function Widgets:MaterialInspectionSummary(receipt,kind,stock,freshness)
    if type(receipt)~="table" or receipt.readOnly~=true or
        receipt.nativeDispatchAllowed~=false or
        type(receipt.materialID)~="number" then return nil end
    local name=tostring(receipt.materialName or "Material")
    name=self:BoundedUTF8Label(name,26)
    local header=name.." (#"..tostring(receipt.materialID)..") · manual review"
    if kind=="Bank" then
        local count=type(stock)=="number" and stock>=0 and stock==stock and
            stock~=math.huge and stock~=-math.huge and math.floor(stock)==stock and
            tostring(stock) or "UNKNOWN"
        return header.." | Bank quantity: "..count.." | Snapshot: "..
            tostring(freshness or "UNKNOWN")
    end
    return header.." | AH item quote: UNKNOWN | Snapshot: "..
        tostring(freshness or "UNKNOWN").." | No item-level live price verified"
end
-- One neutral/read-only unavailable-state contract for non-Gathering pages.
-- It cannot grant crafting, shopping or bank access; views own their actions.
function Widgets:AdvisoryUnavailable(kind)
    local descriptions={
        planner="No verified profession plan is available. Review the Guide or refresh the profession state.",
        acquisition="Acquisition planning unavailable. Verify source data manually; nothing will be purchased.",
        snapshot="No current Auction House snapshot. Open the AH and start a manual scan when permitted.",
    }
    return {text=descriptions[kind] or "Reference information unavailable. Refresh or review the source.",
        status="UNAVAILABLE",readOnly=true,nativeDispatchAllowed=false}
end

-- Shared informational feedback contract; native permissions belong to
-- ProfessionRegistry/CraftReadiness and cannot be granted by a UI state.
function Widgets:GatheringPhaseLabel(router,mapID)
    local progress=router and type(router.GetProgressForMap)=="function" and
        router:GetProgressForMap(mapID) or nil
    local phase=progress and progress.stage
    local labels={REFERENCE_LOAD="Loading sourced references",ZONE_SUITABILITY="Checking zone suitability",
        CANDIDATE_SELECTION="Filtering eligible nodes",CANDIDATE_SORT="Sorting candidates",
        CANDIDATE_DIVERSIFY="Balancing route coverage",CANDIDATE_SCORING="Scoring route stops",
        ROUTE_GEOMETRY="Building route geometry"}
    if not phase or not labels[phase] then
        return {text="Planning route · advisory preview",phase="GENERATING",
            readOnly=true,nativeDispatchAllowed=false}
    end
    return {text=labels[phase].." · advisory preview",phase="GENERATING",
        workChecks=progress.workChecks,readOnly=true,nativeDispatchAllowed=false}
end
function Widgets:GatheringLifecycleReceipt(router,mapID,status)
    local result={readOnly=true,nativeDispatchAllowed=false,committed=false,phase=status or "IDLE"}
    if status=="GENERATING" then
        local stage=self:GatheringPhaseLabel(router,mapID)
        result.text=stage.text
        result.workChecks=stage.workChecks
    elseif status=="READY" then
        result.text="Route committed · inspect advisory waypoints and map overlay"
        result.committed=true
        -- MarkOverlayPresented is a post-paint receipt, not a frame-time or
        -- isolated overlay-CPU measurement (Embedded passes nil intentionally).
        local diagnostic=router and router.GetSchedulerDiagnostics and
            router:GetSchedulerDiagnostics() or nil
        if type(diagnostic)=="table" and diagnostic.mapID==mapID and
            diagnostic.overlayPresentedElapsedMs~=nil then
            result.presentation="MAP_RENDER_PRESENTED"
            result.text="Route ready · advisory map presented · Why this route"
        else result.presentation="READY_AWAITING_MAP_PAINT" end
    elseif status=="NO_ELIGIBLE_ROUTE" or status=="EMPTY" then
        result.text="No eligible route · review learned layers, resources and focus"
        result.phase="EMPTY"
    elseif status=="CANCELLED" or status=="CLEARED_BY_USER" then
        result.text="Route cancelled · change selection or Generate again"
    elseif status=="ROUTE_ERROR" or status=="ERROR" then
        result.text="Route generation failed · review selections and retry manually"
        result.phase="ERROR"
    else
        result.text="No committed route · select resources and Generate"
    end
    return result
end
-- Presentation-only breakdown. Timestamps are sampled at service Tick
-- boundaries and may be UNKNOWN; none is a WoW frame/FPS measurement.
function Widgets:GatheringTimingSummary(router,mapID)
    local d=router and type(router.GetSchedulerDiagnostics)=="function" and
        router:GetSchedulerDiagnostics() or nil
    if type(d)~="table" or d.mapID~=mapID then return nil end
    local function sampled(value)
        if type(value)=="number" and value==value and value>=0 and
            value<math.huge and value<1000000 then
            return string.format("%.0f ms",value)
        end
        return "UNKNOWN"
    end
    local phases={}
    for _,key in ipairs({"REFERENCE_LOAD","CANDIDATE_SELECTION","CANDIDATE_SORT",
        "CANDIDATE_SCORING","ROUTE_GEOMETRY"}) do
        local v=d.phaseFirstObservedMs and d.phaseFirstObservedMs[key]
        if type(v)=="number" and v==v and v>=0 and v<1000000 then
            phases[#phases+1]=key.." "..sampled(v)
        end
    end
    return "Scheduler observations (not native latency): first feedback "..
        sampled(d.firstFeedbackStagedMs)..", READY "..sampled(d.commitElapsedMs)..
        ", map art + overlay "..sampled(d.overlayPresentedElapsedMs)..
        "; map render CPU "..sampled(d.mapRenderCpuSampleMs)..
        "; WoW FPS UNKNOWN"..(#phases>0 and ("\nStages: "..table.concat(phases,", ")) or "")
end

-- Shared visual-only status receipt for map, guide and overview labels.
-- Bounds the FontString's hitless paint region; never alters route/plan state.
function Widgets:SetAdvisoryStatusText(region,value,width,maxHeight)
    if not (region and region.SetText) then return false end
    local message=tostring(value or "")
    region:SetText(message)
    if region.SetWordWrap then region:SetWordWrap(true) end
    if type(width)=="number" and width>0 and region.SetWidth then region:SetWidth(width) end
    if region.SetHeight then
        -- The previous unconditional 40-unit FontString height clipped
        -- longer localized status receipts, even with word wrapping enabled.
        -- Source-derived estimate stays bounded; native font pixels await QA.
        local columns=math.max(12,math.floor((tonumber(width) or 190)/7))
        local rows=math.max(1,math.ceil(#message/columns))
        local estimated=math.max(40,rows*14+4)
        local height=JLP.UILayout and JLP.UILayout.BoundedContentHeight and
            JLP.UILayout:BoundedContentHeight(estimated,16,maxHeight or 48) or
            math.min(maxHeight or 48,estimated)
        region:SetHeight(height)
    end
    return true
end
function Widgets:FeedbackState(kind,reason)
    local names={empty="No data available",loading="Gathering information",disabled="Action unavailable",
        error="Unable to complete the request",stale="Cached information; advisory only",ready="Ready to review"}
    kind=names[kind] and kind or "empty"
    return {contract="jlp-ui-feedback-v1",kind=kind,label=names[kind],
        detail=type(reason)=="string" and reason or "",tone=(kind=="ready" and "good" or
            (kind=="loading" and "cyan" or "warn")),readOnly=true,nativeDispatchAllowed=false}
end
-- Display-only pager presentation, shared across Guide and Secondaries.
-- Navigation remains in the owning view; this method cannot mutate plans.
function Widgets:ApplyAdvisoryPager(previousButton,nextButton,pageLabel,receipt,text)
    local ready=type(receipt)=="table" and (receipt.total or 0)>0
    local previous=ready and receipt.canPrevious==true or false
    local nextPage=ready and receipt.canNext==true or false
    if previousButton and previousButton.SetEnabled then previousButton:SetEnabled(previous) end
    if nextButton and nextButton.SetEnabled then nextButton:SetEnabled(nextPage) end
    -- Shared source-page disabled-state treatment for Guide and Secondaries.
    -- The buttons retain their own OnClick; this only communicates eligibility.
    if previousButton and previousButton.SetAlpha then previousButton:SetAlpha(previous and 1 or 0.45) end
    if nextButton and nextButton.SetAlpha then nextButton:SetAlpha(nextPage and 1 or 0.45) end
    if pageLabel and pageLabel.SetText then
        pageLabel:SetText(text or (ready and
            ("Page "..tostring(receipt.page).." / "..tostring(receipt.pageCount)) or
            "No qualified materials"))
    end
    return {canPrevious=previous,canNext=nextPage,readOnly=true,nativeDispatchAllowed=false}
end

function Widgets:Fill(frame, colorName, layer)
    local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetVertexColor(color(colorName or "panel"))
    return tex
end

function Widgets:Border(frame, colorName, thickness)
    thickness = thickness or 1
    local r,g,b,a = color(colorName or "border")
    frame.__jlpBorder = frame.__jlpBorder or {}
    local specs = {
        top = {"TOPLEFT","TOPRIGHT",nil,thickness},
        bottom = {"BOTTOMLEFT","BOTTOMRIGHT",nil,thickness},
        left = {"TOPLEFT","BOTTOMLEFT",thickness,nil},
        right = {"TOPRIGHT","BOTTOMRIGHT",thickness,nil},
    }
    for key,s in pairs(specs) do
        local t = frame.__jlpBorder[key] or frame:CreateTexture(nil,"BORDER")
        frame.__jlpBorder[key] = t
        t:ClearAllPoints()
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(r,g,b,a)
        t:SetPoint(s[1], frame, s[1])
        t:SetPoint(s[2], frame, s[2])
        if s[3] then t:SetWidth(s[3]) else t:SetHeight(s[4]) end
    end
end

function Widgets:Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    local rawSetText = fs.SetText
    function fs:SetText(value)
        local safe = JLP.SafeText and JLP:SafeText(value) or tostring(value or "")
        return rawSetText(self, safe)
    end
    fs:SetText(text or "")
    fs:SetTextColor(color("text"))
    return fs
end

function Widgets:SkinPanel(frame, variant)
    if not frame or frame.__jlpSkin then return end
    frame.__jlpSkin = {}
    variant = variant == "secondary" and "card_secondary" or "card_primary"
    local root = JLP.UITheme:Asset(variant .. "\\")
    local corner = 28

    local function tex(key, file, layer)
        local t = frame:CreateTexture(nil, layer or "BACKGROUND")
        t:SetTexture(root .. file)
        frame.__jlpSkin[key] = t
        return t
    end

    local tl=tex("tl","top_left.tga")
    tl:SetPoint("TOPLEFT",0,0)
    tl:SetSize(corner,corner)

    local tr=tex("tr","top_right.tga")
    tr:SetPoint("TOPRIGHT",0,0)
    tr:SetSize(corner,corner)

    local bl=tex("bl","bottom_left.tga")
    bl:SetPoint("BOTTOMLEFT",0,0)
    bl:SetSize(corner,corner)

    local br=tex("br","bottom_right.tga")
    br:SetPoint("BOTTOMRIGHT",0,0)
    br:SetSize(corner,corner)

    local top=tex("top","top_edge.tga")
    top:SetPoint("TOPLEFT",tl,"TOPRIGHT",0,0)
    top:SetPoint("TOPRIGHT",tr,"TOPLEFT",0,0)
    top:SetHeight(corner)

    local bottom=tex("bottom","bottom_edge.tga")
    bottom:SetPoint("BOTTOMLEFT",bl,"BOTTOMRIGHT",0,0)
    bottom:SetPoint("BOTTOMRIGHT",br,"BOTTOMLEFT",0,0)
    bottom:SetHeight(corner)

    local left=tex("left","left_edge.tga")
    left:SetPoint("TOPLEFT",tl,"BOTTOMLEFT",0,0)
    left:SetPoint("BOTTOMLEFT",bl,"TOPLEFT",0,0)
    left:SetWidth(corner)

    local right=tex("right","right_edge.tga")
    right:SetPoint("TOPRIGHT",tr,"BOTTOMRIGHT",0,0)
    right:SetPoint("BOTTOMRIGHT",br,"TOPRIGHT",0,0)
    right:SetWidth(corner)

    local center=tex("center","center_fill.tga")
    center:SetPoint("TOPLEFT",tl,"BOTTOMRIGHT",0,0)
    center:SetPoint("BOTTOMRIGHT",br,"TOPLEFT",0,0)
    center:SetVertexColor(1,1,1,0.99)
end

function Widgets:Card(parent, title, variant)
    local f = CreateFrame("Frame", nil, parent)
    self:SkinPanel(f, variant)

    local heading = self:Label(f, title or "", "GameFontNormalLarge")
    -- The heading is bounded by its owning card, rather than having an
    -- unconstrained fontstring that can render over adjacent components.
    heading:SetPoint("TOPLEFT", 22, -16)
    heading:SetPoint("TOPRIGHT", -22, -16)
    heading:SetHeight(23)
    if heading.SetWordWrap then heading:SetWordWrap(false) end
    if heading.SetMaxLines then heading:SetMaxLines(1) end
    heading:SetJustifyH("LEFT")
    heading:SetTextColor(color("text"))
    f.heading = heading
    function f:SetHeadingRightInset(inset)
        inset=math.max(22,tonumber(inset) or 22)
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT",self,"TOPLEFT",22,-16)
        heading:SetPoint("TOPRIGHT",self,"TOPRIGHT",-inset,-16)
    end

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(0.31,0.48,0.61,0.55)
    line:SetPoint("TOPLEFT", 22, -45)
    line:SetPoint("TOPRIGHT", -22, -45)
    line:SetHeight(1)
    f.rule = line

    return f
end

function Widgets:Progress(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(0, 300)
    bar:SetValue(0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.00, 0.68, 1.00, 1.0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.006,0.025,0.045,0.95)
    bar.background = bg

    self:Border(bar, "border", 1)

    local text = self:Label(bar, "0 / 300", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    bar.valueText = text

    function bar:SetSkill(value, cap)
        value = tonumber(value) or 0
        cap = tonumber(cap) or 300
        self:SetMinMaxValues(0, math.max(1, cap))
        self:SetValue(value)
        self.valueText:SetText(string.format("%d / %d", value, cap))
    end

    return bar
end

function Widgets:Button(parent, text, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 180, 38)
    local bg=b:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(JLP.UITheme:Asset("buttons\\medium_blank.tga"))
    b.background=bg
    local label = self:Label(b, text or "Action", "GameFontHighlight")
    -- A centered, unbounded FontString rendered outside 46-92 unit dock
    -- buttons. Anchor both ends to the Button hitbox, not the text width.
    label:SetPoint("LEFT",b,"LEFT",7,0)
    label:SetPoint("RIGHT",b,"RIGHT",-7,0)
    label:SetHeight(24)
    label:SetJustifyH("CENTER")
    if label.SetWordWrap then label:SetWordWrap(false) end
    if label.SetMaxLines then label:SetMaxLines(1) end
    b.label = label
    function b:SetText(value) self.label:SetText(value or "") end
    function b:SetActiveState(active, tone)
        self.__jlpActiveState=active and true or false
        self.background:SetTexture(JLP.UITheme:Asset(self.__jlpActiveState and
            "buttons\\medium_blank_active_green.tga" or "buttons\\medium_blank.tga"))
        self.background:SetVertexColor(1,1,1,1)
        self.label:SetTextColor(color("text"))
        -- Keep only the rounded button-shell asset: legacy square borders
        -- may already exist when a frame is reused after a theme change.
        for _,edge in pairs(self.__jlpBorder or {}) do edge:Hide() end
    end
    b:SetScript("OnEnter", function(self)
        if not self.__hover then
            local overlay=self:CreateTexture(nil,"ARTWORK")
            overlay:SetAllPoints(self)
            self.__hover=overlay
        end
        -- Hover artwork must share the rounded silhouette, not create a
        -- square filled overlay around an otherwise rounded button.
        self.__hover:SetTexture(JLP.UITheme:Asset(self.__jlpActiveState and
            "buttons\\medium_blank_active_green.tga" or "buttons\\medium_blank.tga"))
        self.__hover:SetAlpha(0.15)
    end)
    b:SetScript("OnLeave", function(self)
        if self.__hover then self.__hover:SetAlpha(0) end
    end)
    -- New buttons shown while the main UI is click-through must not wait for
    -- the periodic reconciliation. Restrict to descendants of MainWindow;
    -- standalone map buttons are deliberately independent.
    b:SetScript("OnShow",function(self)
        local main=JLP.MainWindow
        local profile=JLP.DB and JLP.DB.profile
        if not (main and main.frame and profile and profile.clickThrough) then return end
        local owner=self
        for _=1,48 do
            if owner==main.frame then
                if self.__jlpMouseIntent==nil and self.IsMouseEnabled then
                    self.__jlpMouseIntent=self:IsMouseEnabled() and true or false
                end
                if self.EnableMouse then self:EnableMouse(false) end
                break
            end
            owner=owner and owner.GetParent and owner:GetParent() or nil
            if not owner then break end
        end
    end)
    return b
end

function Widgets:NavButton(parent, definition)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(62)

    local normal = b:CreateTexture(nil, "BACKGROUND")
    normal:SetAllPoints()
    normal:SetTexture("Interface\\Buttons\\WHITE8X8")
    normal:SetVertexColor(0.004,0.020,0.034,0.50)
    b.normal = normal

    local active = b:CreateTexture(nil,"BACKGROUND",nil,1)
    active:SetAllPoints()
    active:SetTexture("Interface\\Buttons\\WHITE8X8")
    active:SetVertexColor(0.05,0.30,0.45,0)
    b.active = active

    local icon = b:CreateTexture(nil,"ARTWORK")
    icon:SetTexture(definition.texture or JLP.UITheme:Asset(definition.icon))
    icon:SetSize(34,34)
    icon:SetPoint("LEFT",16,0)
    b.icon=icon

    local label = Widgets:Label(b, definition.label, "GameFontHighlightLarge")
    label:SetPoint("LEFT",icon,"RIGHT",14,0)
    label:SetPoint("RIGHT",-8,0)
    label:SetJustifyH("LEFT")
    b.label=label

    b:SetScript("OnEnter", function(self)
        if not self.__active then
            self.active:SetVertexColor(0.04,0.32,0.50,0.30)
        end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.__active then
            self.active:SetVertexColor(0.04,0.32,0.50,0)
        end
    end)

    function b:SetActive(value)
        self.__active = value and true or false
        self.active:SetVertexColor(0.04,0.36,0.56,value and 0.68 or 0)
        if self.icon.SetDesaturated then self.icon:SetDesaturated(not value) end
        self.label:SetTextColor(color(value and "gold" or "text"))
        if value then Widgets:Border(self,"cyan",1) else Widgets:Border(self,"sidebar",1) end
    end
    return b
end

function Widgets:SubNavButton(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(36)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.004,0.020,0.034,0.38)
    b.background = bg

    local accent = b:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT",0,0)
    accent:SetPoint("BOTTOMLEFT",0,0)
    accent:SetWidth(2)
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetVertexColor(color("cyan"))
    accent:SetAlpha(0)
    b.accent = accent

    local label = self:Label(b, text or "", "GameFontHighlight")
    label:SetPoint("LEFT",18,0)
    label:SetPoint("RIGHT",-8,0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(color("muted"))
    b.label = label

    b:SetScript("OnEnter", function(self)
        if not self.__active then
            self.background:SetVertexColor(0.02,0.16,0.25,0.42)
        end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.__active then
            self.background:SetVertexColor(0.004,0.020,0.034,0.38)
        end
    end)

    function b:SetText(value)
        self.label:SetText(value or "")
    end

    function b:SetActive(value)
        self.__active = value and true or false
        self.accent:SetAlpha(value and 1 or 0)
        self.background:SetVertexColor(0.03,0.24,0.36,value and 0.62 or 0.38)
        self.label:SetTextColor(color(value and "gold" or "muted"))
    end

    return b
end

function Widgets:Body(parent)
    local fs = self:Label(parent, "", "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetSpacing(4)
    return fs
end


function Widgets:StatusPill(parent, text, tone, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 104, 24)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.background = bg
    local label = self:Label(f, text or "STATUS", "GameFontHighlightSmall")
    label:SetPoint("CENTER", 0, 0)
    f.label = label
    function f:SetStatus(value, colorName)
        self.label:SetText(string.upper(tostring(value or "STATUS")))
        local r,g,b,a = JLP.UITheme:Color(colorName or "muted")
        self.background:SetVertexColor(r,g,b,0.18)
        self.label:SetTextColor(r,g,b,1)
        Widgets:Border(self, colorName or "muted", 1)
    end
    f:SetStatus(text or "STATUS", tone or "muted")
    return f
end

function Widgets:SectionRule(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(0.22,0.38,0.50,0.38)
    line:SetHeight(1)
    return line
end

function Widgets:SectionLabel(parent, text, tone)
    local fs = self:Label(parent, text or "", "GameFontNormal")
    fs:SetTextColor(color(tone or "gold"))
    return fs
end

-- Advisory route phase only. A phase sample is never proof of READY or
-- an ETA. Kept short enough for compact dock and embedded caption regions.
function Widgets:GatheringProgressLabel(receipt)
    if type(receipt)~="table" or receipt.status~="GENERATING" or
        receipt.nativeDispatchAllowed~=false then return "Route status unavailable" end
    local names={REFERENCE_LOAD="Loading references",CANDIDATE_SELECTION="Selecting candidates",
        CANDIDATES="Selecting candidates",SCORING="Scoring route candidates",
        ROUTE_GEOMETRY="Planning route geometry",GEOMETRY="Planning route geometry",
        PUBLISH="Finalizing advisory route",ZONE_SUITABILITY="Checking zone suitability",
        CANDIDATE_SORT="Sorting candidates",CANDIDATE_DIVERSIFY="Balancing candidates",
        CANDIDATE_SCORING="Scoring candidates"}
    local name=names[receipt.stage] or "Planning advisory route"
    local checks=tonumber(receipt.workChecks)
    if checks and checks>=0 and checks<1e10 then
        return name.." · "..math.floor(checks).." work checks (preview)"
    end
    return name.." (preview)"
end

JLP.UIWidgets = Widgets
