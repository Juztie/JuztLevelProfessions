local _, JLP = ...
local Page = { name = "Overview" }

local function professionName(state, key)
    local p = state and state.detected and state.detected[key]
    local reg=JLP:GetModule("ProfessionRegistry")
    return p and p.name or (reg and reg:GetDisplayNameOrKey(key)) or "Unknown profession"
end

local function professionPercent(p)
    if not p or p.skill==nil or not p.maxSkill or p.maxSkill <= 0 then return nil end
    return math.floor(((p.skill or 0) / p.maxSkill) * 100 + 0.5)
end

local function buildProfessionBlock(parent, key, fallbackName)
    local W, C = JLP.UIWidgets, JLP.UIComponents
    local block=CreateFrame("Frame",nil,parent)
    block.key=key
    block.icon=C:Icon(block,48)
    block.icon:SetPoint("TOPLEFT",0,0)
    block.name=W:Label(block,fallbackName,"GameFontHighlightLarge")
    block.name:SetPoint("TOPLEFT",block.icon,"TOPRIGHT",14,-1)
    block.name:SetPoint("TOPRIGHT",-4,-1)
    block.name:SetJustifyH("LEFT")
    block.skill=W:Label(block,"0 / 300","GameFontHighlight")
    block.skill:SetPoint("TOPLEFT",block.name,"BOTTOMLEFT",0,-8)
    block.skill:SetTextColor(JLP.UITheme:Color("muted"))
    block.percent=W:Label(block,"0%","GameFontHighlight")
    block.percent:SetPoint("TOPRIGHT",-4,-31)
    block.percent:SetJustifyH("RIGHT")
    block.percent:SetTextColor(JLP.UITheme:Color("gold"))
    block.bar=W:Progress(block)
    block.bar:SetPoint("TOPLEFT",block.icon,"BOTTOMRIGHT",14,-14)
    block.bar:SetPoint("TOPRIGHT",-4,-62)
    block.bar:SetHeight(18)
    return block
end

local function addKV(parent, y, width, labelWidth)
    local row=JLP.UIComponents:KeyValueRow(parent,width)
    row:SetPoint("TOPLEFT",0,y)
    if labelWidth then row.label:SetWidth(labelWidth) end
    return row
end

local function addRule(parent, y)
    local rule=JLP.UIWidgets:SectionRule(parent)
    rule:SetPoint("TOPLEFT",0,y)
    rule:SetPoint("TOPRIGHT",0,y)
    return rule
end

local function stringHeight(region, fallback)
    if region and region.GetStringHeight then
        local ok, value = pcall(region.GetStringHeight, region)
        if ok and tonumber(value) and value > 0 then return value end
    end
    return fallback or 18
end

-- The existing card owns an inner scrollport, not a third primary slot.
local function layoutProfessionProgress(card)
    if not (card and card.scroll) then return end
    local width=card.scroll.__contentWidth;local y=0
    local function place(row)
        row:ClearAllPoints();row:SetPoint("TOPLEFT",card.scroll.content,"TOPLEFT",0,-y)
        row:SetWidth(width)
        local size=row.compact and 32 or 48
        row.icon:SetSize(size,size)
        row.name:ClearAllPoints();row.name:SetPoint("TOPLEFT",row.icon,"TOPRIGHT",12,-1)
        row.name:SetPoint("TOPRIGHT",row,"TOPRIGHT",-2,-1)
        row.name:SetHeight(math.max(18,stringHeight(row.name,18)))
        row.percent:ClearAllPoints();row.percent:SetPoint("TOPRIGHT",row.name,"BOTTOMRIGHT",0,-5)
        row.percent:SetWidth(72);row.percent:SetHeight(18)
        row.skill:ClearAllPoints();row.skill:SetPoint("TOPLEFT",row.name,"BOTTOMLEFT",0,-5)
        row.skill:SetPoint("TOPRIGHT",row.percent,"TOPLEFT",-6,0)
        local sh=math.max(18,stringHeight(row.skill,18));row.skill:SetHeight(sh)
        local barY=math.max(size+8,stringHeight(row.name,18)+5+sh+8)
        row.bar:ClearAllPoints();row.bar:SetPoint("TOPLEFT",row,"TOPLEFT",0,-barY)
        row.bar:SetPoint("TOPRIGHT",row,"TOPRIGHT",0,-barY)
        local bh=row.compact and 8 or 14;row.bar:SetHeight(bh)
        local height=barY+bh+12;row:SetHeight(height);row.__layoutHeight=height
        y=y+height
    end
    place(card.slot1);place(card.slot2)
    local function section(title,rows)
        if #rows==0 then title:Hide();return end
        title:Show();title:ClearAllPoints();title:SetPoint("TOPLEFT",card.scroll.content,"TOPLEFT",0,-y)
        title:SetPoint("TOPRIGHT",card.scroll.content,"TOPRIGHT",0,-y)
        title:SetHeight(math.max(18,stringHeight(title,18)));y=y+stringHeight(title,18)+8
        for _,row in ipairs(rows) do place(row) end
    end
    section(card.unplacedTitle,card.visibleUnplaced or {})
    section(card.secondaryTitle,card.visibleSecondaries or {})
    if #(card.visibleSecondaries or {})==0 then
        card.secondaryNotice:Show();card.secondaryNotice:ClearAllPoints()
        card.secondaryNotice:SetPoint("TOPLEFT",card.scroll.content,"TOPLEFT",0,-y)
        card.secondaryNotice:SetPoint("TOPRIGHT",card.scroll.content,"TOPRIGHT",0,-y)
        local h=math.max(18,stringHeight(card.secondaryNotice,18));card.secondaryNotice:SetHeight(h);y=y+h+8
    else card.secondaryNotice:Hide() end
    card.scroll:SetContentHeight(math.max(1,y),true)
end

local function professionRows(card,pool,count)
    while #pool<count do
        local row=buildProfessionBlock(card.scroll.content,nil,"")
        row.compact=true;pool[#pool+1]=row
    end
    local visible={}
    for i,row in ipairs(pool) do
        row:SetShown(i<=count)
        if i<=count then visible[#visible+1]=row
        elseif row.icon.ClearInteraction then row.icon:ClearInteraction() end
    end
    return visible
end

-- Overview's lower cards use *rendered text* rather than the generic
-- MaterialRow's conservative 76/108 unit reservation.  The latter is useful
-- for Guide but creates fake overflow with just two short Overview items.
-- Keep this local: other pages retain their authored row spacing.
local function layoutOverviewMaterialRow(row)
    local rowWidth=tonumber(row.GetWidth and row:GetWidth()) or 290
    -- A single TOPLEFT anchor plus explicit width/height is intentional:
    -- anchoring the right-hand *centre* back to the row would also constrain
    -- the label vertically and break the measured text flow.
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT",row.itemIcon,"TOPRIGHT",12,-1)
    row.name:SetWidth(math.max(60,rowWidth-184))
    local titleHeight=math.max(18,stringHeight(row.name,18))
    row.name:SetHeight(titleHeight)
    row.summary:ClearAllPoints()
    row.summary:SetPoint("TOPLEFT",row.name,"BOTTOMLEFT",0,-6)
    row.summary:SetWidth(math.max(60,rowWidth-56))
    local summaryHeight=math.max(16,stringHeight(row.summary,16))
    row.summary:SetHeight(summaryHeight)
    local bottom=titleHeight+6+summaryHeight
    if row.dependencyName and row.dependencyName.IsShown and row.dependencyName:IsShown() then
        row.dependencyName:ClearAllPoints()
        row.dependencyName:SetPoint("TOPLEFT",row.summary,"BOTTOMLEFT",0,-4)
        row.dependencyName:SetWidth(math.max(60,rowWidth-56))
        local depNameHeight=math.max(16,stringHeight(row.dependencyName,16))
        row.dependencyName:SetHeight(depNameHeight)
        row.dependencyCounts:ClearAllPoints()
        row.dependencyCounts:SetPoint("TOPLEFT",row.dependencyName,"BOTTOMLEFT",0,-3)
        row.dependencyCounts:SetWidth(math.max(60,rowWidth-56))
        local depCountHeight=math.max(14,stringHeight(row.dependencyCounts,14))
        row.dependencyCounts:SetHeight(depCountHeight)
        bottom=bottom+4+depNameHeight+3+depCountHeight
    end
    local height=math.max(48,bottom+5) -- icon (42) and final text descenders
    row:SetHeight(height)
    row.__layoutHeight=height
    return height
end

local function scanAgeText(scanner)
    if not scanner then return "Not available" end
    local guard=JLP:GetModule("AuctionScanGuard")
    local text = guard and guard:GetStatusText() or (scanner.GetStatusText and scanner:GetStatusText() or "")
    text = tostring(text or "")
    text = text:gsub("^Last successful scan:%s*", "")
    text = text:gsub("%s*%-%s*%d+%s+auctions%s*%-%s*%d+%s+item%s+types", "")
    return text ~= "" and text or "Not available"
end

local function ensureMaterialRows(card, count)
    local C=JLP.UIComponents
    while #card.rows < count do
        local row=C:MaterialRow(card.scroll.content, card.scroll.__contentWidth, false)
        card.rows[#card.rows+1]=row
    end
    for i,row in ipairs(card.rows) do row:SetShown(i<=count) end
end

local function ensureDecisionRows(card, count)
    local C=JLP.UIComponents
    while #card.decisionRows < count do
        local row=C:NoticeRow(card.scroll.content, card.scroll.__contentWidth, 58)
        card.decisionRows[#card.decisionRows+1]=row
    end
    for i,row in ipairs(card.decisionRows) do row:SetShown(i<=count) end
end

function Page:Create(parent)
    if self.frame then return self.viewport or self.frame end
    local W,C,L=JLP.UIWidgets,JLP.UIComponents,JLP.UILayout
    local base=JLP.UITheme.overview
    local bounds=L:PageGeometry(parent,base.contentWidth,base.contentHeight)
    local O=setmetatable({contentWidth=bounds.width,contentHeight=bounds.height,
        lowerWidth=math.max(240,(bounds.width-2*base.gap)/3),
        topHeight=math.max(300,bounds.height-base.bottomHeight-base.gap)}, {__index=base})
    local viewport=L:ScrollArea(parent,{width=bounds.width,height=bounds.height,
        contentWidth=math.max(1,bounds.width-12),scrollbarGutter=12,wheelStep=42})
    viewport:SetPoint("TOPLEFT",parent,"TOPLEFT",0,0)
    viewport:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",0,0)
    local f=viewport.content
    f.pageGeometry=bounds
    self.viewport=viewport
    -- Normal artwork and card positioning retain their original geometry.
    -- Smaller parent bounds are handled by ApplyLayout and the outer scrollport.
    local progress=W:Card(f,"Profession Progress","primary")
    progress:SetPoint("TOPLEFT",0,0); progress:SetSize(O.progressWidth,O.topHeight)
    progress.scroll=L:ScrollArea(progress,{
        width=O.progressWidth-O.cardContentLeft-O.cardContentRight,
        height=O.topHeight-O.cardContentTop-O.cardContentBottom,
        scrollbarGutter=O.scrollbarGutter,
    })
    progress.scroll:SetPoint("TOPLEFT",O.cardContentLeft,-O.cardContentTop)
    progress.slot1=buildProfessionBlock(progress.scroll.content,nil,"Primary Profession 1")
    progress.slot2=buildProfessionBlock(progress.scroll.content,nil,"Primary Profession 2")
    progress.unplacedTitle=C:SectionTitle(progress.scroll.content,"PRIMARY SLOT NOT CONFIRMED")
    progress.secondaryTitle=C:SectionTitle(progress.scroll.content,"SECONDARY PROFESSIONS")
    progress.secondaryNotice=W:Body(progress.scroll.content)
    progress.secondaryNotice:SetText("Secondary ownership not confirmed.")
    progress.unplacedRows={};progress.secondaryRows={}

    local currentWidth=O.contentWidth-O.progressWidth-O.gap
    local current=W:Card(f,"Current Action","secondary")
    current:SetPoint("TOPLEFT",progress,"TOPRIGHT",O.gap,0); current:SetSize(currentWidth,O.topHeight)
    current.scroll=L:ScrollArea(current,{
        width=currentWidth-O.cardContentLeft-O.cardContentRight,
        height=O.topHeight-O.cardContentTop-O.cardContentBottom,
        contentWidth=currentWidth-O.cardContentLeft-O.cardContentRight-O.scrollbarGutter,
        scrollbarGutter=O.scrollbarGutter,
    })
    current.scroll:SetPoint("TOPLEFT",O.cardContentLeft,-O.cardContentTop)
    local cc=current.scroll.content

    current.stepLabel=C:SectionTitle(cc,"CURRENT STEP"); current.stepLabel:SetPoint("TOPLEFT",0,0)
    current.badge=W:StatusPill(current,"ACTIVE","gold",96); current.badge:SetPoint("TOPRIGHT",-22,-16)
    current.stepTitle=W:Label(cc,"","GameFontNormalLarge")
    -- A centered, single-line step name sits between the section heading
    -- and the first KV row without moving away from the left-hand anchor.
    current.stepTitle:SetPoint("TOPLEFT",0,-22); current.stepTitle:SetPoint("TOPRIGHT",-118,-22); current.stepTitle:SetHeight(20)
    current.stepTitle:SetJustifyH("LEFT"); current.stepTitle:SetJustifyV("MIDDLE")
    if current.stepTitle.SetWordWrap then current.stepTitle:SetWordWrap(false) end
    current.stepTitle:SetTextColor(JLP.UITheme:Color("cyan"))
    -- Keep the authored one-line layout but expose the entire localized step
    -- name through a hover tooltip when it does not fit the title region.
    local titleHit=CreateFrame("Frame",nil,cc)
    titleHit:SetAllPoints(current.stepTitle)
    if titleHit.EnableMouse then titleHit:EnableMouse(true) end
    titleHit:SetScript("OnEnter",function(self)
        local label=current.stepTitle
        if not (label and GameTooltip) then return end
        local text=label.GetText and label:GetText() or ""
        if type(text)~="string" or text=="" then return end
        GameTooltip:SetOwner(self,"ANCHOR_CURSOR")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    titleHit:SetScript("OnLeave",function(self)
        if JLP.UIInteraction and JLP.UIInteraction.HideTooltip then
            JLP.UIInteraction:HideTooltip(self)
        elseif GameTooltip then GameTooltip:Hide() end
    end)
    current.stepTitleHit=titleHit
    current.stepAction=C:ActionBlock(cc,430,true); current.stepAction:Hide()
    current.progressRows={addKV(cc,-48,542,180),addKV(cc,-68,542,180),addKV(cc,-88,542,180)}
    current.rule1=addRule(cc,-112)
    current.requireLabel=C:SectionTitle(cc,"REQUIREMENTS"); current.requireLabel:SetPoint("TOPLEFT",0,-122)
    current.requireRows={}
    for i=1,6 do current.requireRows[i]=addKV(cc,-144-((i-1)*20),542,180) end
    current.rule2=addRule(cc,-266)
    current.nextLabel=C:SectionTitle(cc,"NEXT ACTION"); current.nextLabel:SetPoint("TOPLEFT",0,-276)
    current.strategy=W:Label(cc,"","GameFontHighlightSmall")
    current.strategy:SetPoint("TOPRIGHT",-2,-296); current.strategy:SetWidth(150); current.strategy:SetJustifyH("RIGHT"); current.strategy:SetTextColor(JLP.UITheme:Color("muted"))
    current.nextAction=W:Label(cc,"","GameFontHighlight")
    current.nextAction:SetPoint("TOPLEFT",0,-296); current.nextAction:SetPoint("RIGHT",current.strategy,"LEFT",-12,0); current.nextAction:SetHeight(32)
    current.nextAction:SetJustifyH("LEFT"); current.nextAction:SetJustifyV("TOP"); current.nextAction:SetTextColor(JLP.UITheme:Color("cyan"))
    current.scroll:SetContentHeight(306)

    local materials=W:Card(f,"Materials","primary")
    materials:SetPoint("BOTTOMLEFT",0,0); materials:SetSize(O.lowerWidth,O.bottomHeight)
    materials.scroll=L:ScrollArea(materials,{
        width=O.lowerWidth-O.cardContentLeft-O.cardContentRight,
        height=O.bottomHeight-O.cardContentTop-O.cardContentBottom,
        contentWidth=O.lowerWidth-O.cardContentLeft-O.cardContentRight-O.scrollbarGutter,
        scrollbarGutter=O.scrollbarGutter,
    })
    materials.scroll:SetPoint("TOPLEFT",O.cardContentLeft,-O.cardContentTop)
    materials.rows={}

    local disenchant=W:Card(f,"Acquisition","primary")
    disenchant:SetPoint("BOTTOMLEFT",materials,"BOTTOMRIGHT",O.gap,0); disenchant:SetSize(O.lowerWidth,O.bottomHeight)
    disenchant.scroll=L:ScrollArea(disenchant,{
        width=O.lowerWidth-O.cardContentLeft-O.cardContentRight,
        height=O.bottomHeight-O.cardContentTop-O.cardContentBottom,
        contentWidth=O.lowerWidth-O.cardContentLeft-O.cardContentRight-O.scrollbarGutter,
        scrollbarGutter=O.scrollbarGutter,
    })
    disenchant.scroll:SetPoint("TOPLEFT",O.cardContentLeft,-O.cardContentTop)
    local dc=disenchant.scroll.content
    disenchant.kind=C:SectionTitle(dc,"MATERIAL ACQUISITION"); disenchant.kind:SetPoint("TOPLEFT",0,0)
    disenchant.explainer=W:Body(dc); disenchant.explainer:SetPoint("TOPLEFT",0,-24); disenchant.explainer:SetPoint("TOPRIGHT",0,-24); disenchant.explainer:SetHeight(48)
    disenchant.notice=C:NoticeRow(dc,disenchant.scroll.__contentWidth,62); disenchant.notice:SetPoint("TOPLEFT",0,-88)
    disenchant.note=disenchant.notice
    disenchant.decisionRows={}
    disenchant.scroll:SetContentHeight(158)

    local snapshot=W:Card(f,"Auction House","primary")
    snapshot:SetPoint("BOTTOMLEFT",disenchant,"BOTTOMRIGHT",O.gap,0); snapshot:SetSize(O.lowerWidth,O.bottomHeight)
    snapshot.scroll=L:ScrollArea(snapshot,{
        width=O.lowerWidth-O.cardContentLeft-O.cardContentRight,
        height=O.bottomHeight-O.cardContentTop-O.cardContentBottom,
        contentWidth=O.lowerWidth-O.cardContentLeft-O.cardContentRight-O.scrollbarGutter,
        scrollbarGutter=O.scrollbarGutter,
    })
    snapshot.scroll:SetPoint("TOPLEFT",O.cardContentLeft,-O.cardContentTop)
    local sc=snapshot.scroll.content
    snapshot.status=W:Label(snapshot,"","GameFontHighlight"); snapshot.status:SetPoint("TOPRIGHT",-22,-16); snapshot.status:SetJustifyH("RIGHT")
    snapshot.rows={C:InlineRow(sc,snapshot.scroll.__contentWidth),C:InlineRow(sc,snapshot.scroll.__contentWidth)}
    snapshot.rows[1]:SetPoint("TOPLEFT",0,0); snapshot.rows[2]:SetPoint("TOPLEFT",0,-26)
    snapshot.rule2=addRule(sc,-52)
    snapshot.nextLabel=C:SectionTitle(sc,"NEXT SCAN"); snapshot.nextLabel:SetPoint("TOPLEFT",0,-62)
    snapshot.nextNotice=C:NoticeRow(sc,snapshot.scroll.__contentWidth,46); snapshot.nextNotice:SetPoint("TOPLEFT",0,-80)
    snapshot.scan=W:Button(sc,"Scan Auction House",160); snapshot.scan:SetPoint("TOPLEFT",0,-138)
    snapshot.scan:SetScript("OnClick",function()
        local guard=JLP:GetModule("AuctionScanGuard")
        local ok,reason=false,"Auction scan guard unavailable."
        if guard then ok,reason=guard:BeginManualScan() end
        JLP:Print(reason or (ok and "Auction scan requested." or "Auction scan unavailable.")); Page:Refresh()
    end)
    snapshot.scroll:SetContentHeight(174)

    f.progress=progress; f.current=current; f.materials=materials; f.disenchant=disenchant; f.snapshot=snapshot
    f.deterministicLayout=true
    self.frame=f
    if viewport.SetScript then
        viewport:SetScript("OnSizeChanged",function() Page:ApplyLayout() end)
    end
    self:ApplyLayout()
    return viewport
end

-- One container owns each card's bounds.  At 1078x636 the result is exactly
-- the authored 450+614 top row and three 350-unit lower cards.  Narrow parent
-- content stacks all five cards, with a wheel-scrollable page container.
function Page:ApplyLayout()
    if self.__applyingLayout then return false end
    local f,viewport=self.frame,self.viewport
    if not (f and viewport and f.progress and f.current) then return false end
    local base=JLP.UITheme.overview
    local w=tonumber(viewport.GetWidth and viewport:GetWidth()) or base.contentWidth
    local h=tonumber(viewport.GetHeight and viewport:GetHeight()) or base.contentHeight
    if w<1 then w=base.contentWidth end
    if h<1 then h=base.contentHeight end
    w=math.max(260,w);h=math.max(1,h)
    local gutter=base.scrollbarGutter or 12
    -- Keep the original authored 1078-wide card coordinates when the outer
    -- scroll track is hidden. Reserve its gutter only for compact overflow.
    local stacked=w<980
    local gap=base.gap or 14
    local top=math.max(340,h-base.bottomHeight-gap)
    local bottomY=stacked and (top*2+gap*2) or (top+gap)
    local docHeight=stacked and (top*2+gap*2+3*base.bottomHeight+2*gap) or
        (top+gap+base.bottomHeight)
    -- The outer ScrollArea's ScrollFrame normally keeps a permanent 12-unit
    -- gutter, even when its scrollbar is hidden.  In FULL Overview the cards
    -- span all 1078 units, so that fixed clip rectangle sheared the right
    -- border/corners of Current Action and Auction House.  Only reserve a
    -- gutter when this page's document actually overflows vertically.
    local needsPageScrollbar=docHeight>h+0.5
    local pageClipRightInset=needsPageScrollbar and gutter or 0
    local inner=math.max(248,w-pageClipRightInset)
    local progressWidth=stacked and inner or math.min(base.progressWidth,math.max(335,inner*0.44))
    local currentWidth=stacked and inner or inner-progressWidth-gap
    local bottomWidth=stacked and inner or math.max(230,(inner-2*gap)/3)
    local function at(card,x,y,cw,ch)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT",f,"TOPLEFT",x,-y)
        card:SetSize(cw,ch)
    end
    at(f.progress,0,0,progressWidth,top)
    at(f.current,stacked and 0 or progressWidth+gap,stacked and top+gap or 0,currentWidth,top)
    for i,card in ipairs({f.materials,f.disenchant,f.snapshot}) do
        at(card,stacked and 0 or (i-1)*(bottomWidth+gap),
            bottomY+(stacked and (i-1)*(base.bottomHeight+gap) or 0),
            bottomWidth,base.bottomHeight)
    end
    local function resizeCard(card,cw,ch)
        if card.scroll and card.scroll.Resize then
            local rw=math.max(1,cw-base.cardContentLeft-base.cardContentRight)
            local rh=math.max(1,ch-base.cardContentTop-base.cardContentBottom)
            card.scroll:Resize(rw,rh,math.max(1,rw-gutter))
        end
    end
    resizeCard(f.progress,progressWidth,top)
    layoutProfessionProgress(f.progress)
    resizeCard(f.current,currentWidth,top)
    for _,card in ipairs({f.materials,f.disenchant,f.snapshot}) do
        resizeCard(card,bottomWidth,base.bottomHeight)
    end
    local currentRowWidth=f.current.scroll and f.current.scroll.__contentWidth or 542
    for _,row in ipairs(f.current.progressRows or {}) do if row.SetWidth then row:SetWidth(currentRowWidth) end end
    for _,row in ipairs(f.current.requireRows or {}) do if row.SetWidth then row:SetWidth(currentRowWidth) end end
    if f.current.stepAction and f.current.stepAction.SetWidth then
        f.current.stepAction:SetWidth(math.max(180,currentRowWidth))
    end
    for _,card in ipairs({f.materials,f.disenchant,f.snapshot}) do
        local width=card.scroll and card.scroll.__contentWidth or bottomWidth
        for _,row in ipairs(card.rows or {}) do if row.SetWidth then row:SetWidth(width) end end
        for _,row in ipairs(card.decisionRows or {}) do if row.SetWidth then row:SetWidth(width) end end
        if card.notice and card.notice.SetWidth then card.notice:SetWidth(width) end
        if card.nextNotice and card.nextNotice.SetWidth then card.nextNotice:SetWidth(width) end
    end
    self.__applyingLayout=true
    viewport:Resize(w,h,inner)
    -- Match the actual ScrollFrame's clip bounds to the computed card layout.
    -- Changing the document width alone does not resize the inner viewport:
    -- ScrollArea creates it with a permanent -gutter right anchor.
    if viewport.SetViewportGutter then viewport:SetViewportGutter(pageClipRightInset) end
    viewport:SetContentHeight(docHeight,true)
    self.__applyingLayout=false
    f.pageGeometry={width=inner,height=docHeight,stacked=stacked,clipRightInset=pageClipRightInset}
    return true
end

function Page:Refresh()
    if not self.frame then return end
    local planner=JLP:GetModule("Planner")
    local workspace=JLP:GetModule("ProfessionWorkspace")
    local workspaceModel=workspace and workspace:GetOverviewModel() or {slots={},secondaryCardKind="acquisition"}
    local state=planner and planner:GetState(workspaceModel.focusedKey) or {status="blocked",action="Planner unavailable.",actionKind="blocked",materials={},detected={}}
    local O=JLP.UITheme.overview
    self:ApplyLayout()

    local function updateSlot(block,slot)
        slot=slot or {state="unknown",name="Primary slot not confirmed"}
        block.presentationState=slot.state
        if slot.profession then
            local p=slot.profession
            block.key=p.key;block.name:SetText(slot.name or p.name or p.key)
            local known=p.skill~=nil and p.maxSkill~=nil and p.maxSkill>0
            local skillText=known and string.format("%d / %d",p.skill,p.maxSkill) or "Skill / cap unknown"
            local historical=slot.state=="historical"
            block.skill:SetText(historical and ("Last known: "..skillText) or skillText)
            local percent=known and professionPercent(p)
            block.percent:SetText(slot.state=="conflict" and "CONFLICT" or historical and "HISTORY" or percent and (percent.."%") or "Unknown")
            block.bar:SetSkill(known and p.skill or 0,known and p.maxSkill or 1)
            block.icon:SetProfession(p.key,p)
            if p.presentationConflict and block.icon.ClearInteraction then block.icon:ClearInteraction() end
        else
            block.key=nil;block.name:SetText(slot.name)
            block.skill:SetText(slot.state=="empty" and "Not learned" or "Unknown")
            block.percent:SetText("-");block.bar:SetSkill(0,1)
            block.icon:SetResolved(JLP.UIIconResolver:GetFallback())
            if block.icon.ClearInteraction then block.icon:ClearInteraction() end
        end
    end
    local progress=self.frame.progress
    updateSlot(progress.slot1,workspaceModel.slots and workspaceModel.slots[1])
    updateSlot(progress.slot2,workspaceModel.slots and workspaceModel.slots[2])
    local unplaced=workspaceModel.unplacedHistorical or {}
    progress.visibleUnplaced=professionRows(progress,progress.unplacedRows,#unplaced)
    for i,p in ipairs(unplaced) do
        updateSlot(progress.visibleUnplaced[i],{state=p.presentationState,name=tostring(p.name or p.key)..
            (p.slotConflict and " (slot conflict)" or " (slot not confirmed)"),profession=p})
    end
    local secondaries=workspaceModel.secondaries or {}
    progress.visibleSecondaries=professionRows(progress,progress.secondaryRows,#secondaries)
    for i,p in ipairs(secondaries) do
        updateSlot(progress.visibleSecondaries[i],{state=p.presentationState,name=p.name,profession=p})
    end
    progress.secondaryNotice:SetText(workspaceModel.secondaryOwnershipUnknown and
        "Secondary ownership not confirmed." or "No secondary professions learned.")
    layoutProfessionProgress(progress)

    local readinessModule=JLP:GetModule("CraftReadiness")
    local readiness=state.key and readinessModule and readinessModule:Get(state.key,state) or nil
    local badgeText,badgeTone="ONBOARDING","gold"
    if state.key then badgeText,badgeTone="ACTIVE","gold" end
    if state.actionKind=="train" then badgeText,badgeTone="TRAINER","gold"
    elseif readiness then
        badgeText=string.upper(tostring(readiness.status or "ACTIVE"))
        badgeTone=(readiness.status=="ready" or readiness.status=="complete") and "good" or (readiness.status=="prepare" or readiness.status=="bank" or readiness.status=="verify" or readiness.status=="materials" or readiness.status=="read-only") and "warn" or "bad"
    end
    if state.readOnly==true then badgeText,badgeTone="READ-ONLY","gold" end
    local current=self.frame.current; current.badge:SetStatus(badgeText,badgeTone)

    local queueModule=JLP:GetModule("ActionQueue"); local tracker=JLP:GetModule("ProgressTracker"); local executionFlow=JLP:GetModule("ExecutionFlow")
    local queue=state.key and queueModule and queueModule:Build(state.key,state,readiness) or nil
    local tracking=state.key and tracker and tracker:GetStatus(state.key) or nil
    local action=queue and queue.actions and queue.actions[queue.currentIndex] or nil
    local flow=state.key and executionFlow and executionFlow:Build(state.key,queue) or nil

    if state.actionKind=="craft" and state.step then
        current.stepAction:SetAction(JLP.UIIconResolver:GetRecipe(state.step.recipe,state.key),state.step.craftInstruction or ("Craft "..tostring(state.step.remainingCrafts or "?").." "..tostring(state.step.recipe or "item")),"",nil,nil,state.step.recipe)
        current.stepTitle:SetText(state.step.craftInstruction or ("Craft "..tostring(state.step.remainingCrafts or "?").." "..tostring(state.step.recipe or "item")))
        current.progressRows[1]:SetRow("skill","Skill",string.format("%d / %d",tonumber(state.profession and state.profession.skill) or 0,tonumber(state.profession and state.profession.maxSkill) or 300))
        current.progressRows[2]:SetRow("target","Target",tostring(tonumber(state.step.skillTarget) or 0),"good")
        current.progressRows[3]:SetRow("estimate","Estimated",string.format("%d casts",tonumber(state.step.remainingCrafts) or 0))
    elseif state.actionKind=="train" then
        local gate=state.step and state.step.trainer
        current.stepAction:SetAction(JLP.UIIconResolver:GetProfession(state.key,state.profession),"Profession rank training","")
        current.stepTitle:SetText("Profession rank training")
        current.progressRows[1]:SetRow("skill","Skill",string.format("%d / %d",tonumber(state.profession and state.profession.skill) or 0,tonumber(state.profession and state.profession.maxSkill) or 0))
        current.progressRows[2]:SetRow("target","Unlock cap",tostring(gate and gate.nextCap or 300),"good")
        current.progressRows[3]:SetRow("trainer","State","Trainer required","warn")
    else
        current.stepAction:SetAction(state.key and JLP.UIIconResolver:GetProfession(state.key,state.profession) or JLP.UIIconResolver:GetFallback(),state.action or "Profession planner unavailable","")
        current.stepTitle:SetText(state.action or "Profession planner unavailable")
        current.progressRows[1]:SetRow("info","State",state.key and "No active action" or "No primary profession selected",state.key and "muted" or "warn")
        current.progressRows[2]:SetRow("target","Target","-")
        current.progressRows[3]:SetRow("estimate","Estimated","-")
    end

    -- Shared bounded FontString paint contract, after selecting the current
    -- action, so long localized steps cannot spill beyond their title region.
    if JLP.UIWidgets and JLP.UIWidgets.SetAdvisoryStatusText and current.stepTitle then
        JLP.UIWidgets:SetAdvisoryStatusText(current.stepTitle,
            current.stepTitle.GetText and current.stepTitle:GetText() or "",nil,20)
        -- Shared advisory labels normally reserve 40+ units for wrapping;
        -- the Overview step name owns exactly one 20-unit line here.
        current.stepTitle:SetHeight(20)
        if current.stepTitle.SetWordWrap then current.stepTitle:SetWordWrap(false) end
        if current.stepTitle.SetJustifyV then current.stepTitle:SetJustifyV("MIDDLE") end
    end
    local recipeText="-"; local recipeTone="muted"
    if readiness and readiness.recipe then
        recipeText=readiness.recipeKnowledge=="known" and "Learned" or readiness.recipeKnowledge=="not-known" and "Not learned" or "Not verified"
        recipeTone=readiness.recipeKnowledge=="known" and "good" or readiness.recipeKnowledge=="not-known" and "bad" or "warn"
    elseif readiness and readiness.blocker=="trainer" then recipeText="Rank training"; recipeTone="warn" end
    current.requireRows[1]:SetRow("recipe","Recipe",recipeText,recipeTone)
    current.requireRows[2]:SetRow("bag","Bag estimate",(readiness and readiness.immediateBagsKnown == false and "UNKNOWN" or string.format("%d from bags",tonumber(readiness and readiness.immediateBags) or 0)))
    current.requireRows[3]:SetRow("bank","Storage estimate",(readiness and readiness.preparedStorageKnown == false and "UNKNOWN" or string.format("%d with bags + current bank",tonumber(readiness and readiness.preparedStorage) or 0)))
    local live=tracking and tracking.actionKind=="craft" and string.format("%d crafts observed | +%d skill",tracking.stepCraftsObserved or 0,tracking.stepSkillGains or 0) or (tracking and tracking.actionKind=="train" and "Waiting for profession rank update..." or "No live progress")
    current.requireRows[4]:SetRow("live","Live",live)
    current.requireRows[5]:SetRow("workspace","Next workspace",flow and (flow.nextStationLabel or (flow.currentContext and flow.currentContext.label)) or (state.key and "Other" or "Profession trainer"),"cyan")
    current.requireRows[6]:SetRow("switches","Switches",tostring(flow and flow.switchCount or 0))
    local advisory=JLP.UIWidgets and JLP.UIWidgets.AdvisoryUnavailable and
        JLP.UIWidgets:AdvisoryUnavailable("planner")
    local nextText=action and action.text or state.action or
        (state.key and advisory and advisory.text) or "Learn a primary profession to begin."
    local req=JLP:GetModule("RequirementPlan")
    local currentRequirements
    if state.key and req and state.actionKind=="craft" then
        local model=req:Build(state.key,state)
        currentRequirements=model
        local safe=req:NextSafeAction(model)
        nextText=nextText.."\nMaterials: "..req:FormatAvailability(model).."\nSafe next step: "..safe.text
    end
    current.nextAction:SetText(nextText)
    local strategy=tostring((JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical")
    local maturity=JLP:GetModule("ProfessionMaturityPresentation")
    local capability=state.key and maturity and maturity:Build(state.key)
    current.strategy:SetText("Strategy: "..strategy..(capability and ("\n"..capability.label) or ""))
    local nextActionHeight=math.max(18,stringHeight(current.nextAction,18)); current.nextAction:SetHeight(math.max(32,nextActionHeight))
    local h=math.max(306,296+math.max(32,nextActionHeight)+12)
    if JLP.UILayout and JLP.UILayout.BoundedContentHeight then
        h=JLP.UILayout:BoundedContentHeight(h,current.scroll.__layoutHeight or 306,16000)
    end
    current.scroll:SetContentHeight(h,true)

    local rows=currentRequirements and currentRequirements.rows or state.materials or {}
    ensureMaterialRows(self.frame.materials,#rows)
    local materialY=0
    for i,widget in ipairs(self.frame.materials.rows) do
        if rows[i] then
            widget:SetMaterial(rows[i])
            local rowHeight=layoutOverviewMaterialRow(widget)
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT",0,-materialY)
            materialY=materialY+rowHeight+O.materialRowGap
        end
    end
    -- ScrollArea already hides its track for content <= the viewport.  Give it
    -- the true last-child bottom, not the generic MaterialRow minimum height.
    self.frame.materials.scroll:SetContentHeight(#rows>0 and math.max(1,materialY-O.materialRowGap) or 1,true)

    local secondary=self.frame.disenchant
    local acquisition=JLP:GetModule("AcquisitionPlanner")
    if workspaceModel.secondaryCardKind=="disenchant" then
        secondary.kind:SetText("ENCHANTING + DISENCHANT")
        secondary.explainer:SetText("Expected yield uses the selected planning scope and the last successful AH snapshot.")
        local selectedPlan=acquisition and acquisition:BuildSelected() or nil
        local decisions=selectedPlan and selectedPlan.decisions or {}
        if #decisions>0 then
            secondary.notice:Hide(); ensureDecisionRows(secondary,#decisions)
            for i,d in ipairs(decisions) do
                local recommendation=d.recommended=="tailoring-disenchant" and "Tailor + Disenchant" or d.recommended=="direct-ah" and "Direct AH" or "Unresolved"
                local row=secondary.decisionRows[i]; row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-82-((i-1)*64)); row:SetNotice("info",tostring(d.name or "Material").." x"..tostring(d.quantity or 0).."\nRecommended: "..recommendation,"text")
            end
            secondary.scroll:SetContentHeight(82+(#decisions*64),true)
        else
            for _,row in ipairs(secondary.decisionRows) do row:Hide() end
            secondary.notice:Show(); secondary.notice:ClearAllPoints(); secondary.notice:SetPoint("TOPLEFT",0,-88); secondary.notice:SetNotice("info","No disenchant cost decision is required for the selected scope.","text"); secondary.scroll:SetContentHeight(158,true)
        end
    else
        secondary.kind:SetText("MATERIAL ACQUISITION")
        secondary.explainer:SetText("Sources are ranked independently from CraftReadiness. Alt-bank snapshots require transfer and never count as immediately craftable.")
        local requirementPlan=JLP:GetModule("RequirementPlan")
        local req=state.key and requirementPlan and requirementPlan:Build(state.key,state) or {rows={}}
        local missingRows={}
        for _,row in ipairs(req.rows or {}) do if (tonumber(row.missing) or 0)>0 then missingRows[#missingRows+1]=row end end
        if #missingRows>0 then
            secondary.notice:Hide(); ensureDecisionRows(secondary,#missingRows)
            for i,rowData in ipairs(missingRows) do
                local row=secondary.decisionRows[i]; row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-82-((i-1)*64)); row:SetNotice("info",tostring(rowData.name or "Material").." x"..tostring(rowData.missing or 0).."\nSources: "..tostring(rowData.optionsText or "External source"),"text")
            end
            secondary.scroll:SetContentHeight(82+(#missingRows*64),true)
        else
            for _,row in ipairs(secondary.decisionRows) do row:Hide() end
            secondary.notice:Show(); secondary.notice:ClearAllPoints(); secondary.notice:SetPoint("TOPLEFT",0,-88)
            secondary.notice:SetNotice("info",state.key and "No missing materials for the current profession step." or "Learn a primary profession to populate material acquisition guidance.","text")
            secondary.scroll:SetContentHeight(158,true)
        end
    end

    local scanner=JLP:GetModule("AuctionScanner"); local snap=scanner:GetSnapshot(); local snapshot=self.frame.snapshot
    local guard=JLP:GetModule("AuctionScanGuard")
    local diag=guard and guard:GetDiagnostics() or {snapshotComplete=false,state="GUARD_UNAVAILABLE"}
    local verifiedSnapshot=snap and diag.snapshotComplete==true
    local resolver=JLP:GetModule("PriceResolver")
    local q=resolver and resolver.QualifySnapshot and resolver:QualifySnapshot()
    local scanStatus=q and q.trustedForCostEstimate and "Qualified snapshot" or
        (q and q.status or "No Snapshot")
    -- The same bounded, wrapping read-only status region used by Gathering
    -- and Guide prevents long localized scan failure labels from spilling into
    -- the heading. Scanner/source authority and manual scan CTA are untouched.
    if JLP.UIWidgets and JLP.UIWidgets.SetAdvisoryStatusText then
        JLP.UIWidgets:SetAdvisoryStatusText(snapshot.status,scanStatus,170,30)
    else snapshot.status:SetText(scanStatus) end
    snapshot.status:SetTextColor(JLP.UITheme:Color(verifiedSnapshot and "good" or "warn"))
    snapshot.rows[1]:SetRow("auction","Coverage",snap and string.format("%d auctions  |  %d item types",tonumber(snap.auctionCount) or 0,tonumber(snap.itemCount) or 0) or "No market data")
    snapshot.rows[2]:SetRow("scan","Last successful scan",snap and scanAgeText(scanner) or "Not available",snap and "good" or "warn")
    local scanNote=snap and (verifiedSnapshot and "Snapshot retained until a newer successful manual scan completes." or "Partial or unverified snapshot: available prices are advisory; item details may be missing.") or "Open the Auction House and run a manual scan to enable current market pricing."
    if diag.state=="SCAN_TIMEOUT" then scanNote="Latest scan timed out. Previous prices were retained; retry at the Auction House." end
    snapshot.nextNotice:SetNotice("cooldown",scanNote,"muted")
    local canScan=guard and guard:CanStartScan() or false
    if snapshot.scan.SetEnabled then snapshot.scan:SetEnabled(canScan==true) end
    snapshot.scan:SetAlpha(canScan and 1 or 0.55)
    local noticeBodyHeight=math.max(34,stringHeight(snapshot.nextNotice.body,34))
    local noticeHeight=math.max(46,noticeBodyHeight+2)
    snapshot.nextNotice:SetHeight(noticeHeight)
    -- The static 86+6 offsets produced a scrollbar for a two-/three-line
    -- advisory even when the complete Scan button would fit in the card.
    -- Preserve the full interactive height and reveal a scrollbar if the
    -- actual advisory text grows beyond the available viewport.
    local scanTop=80+noticeHeight+2
    snapshot.scan:ClearAllPoints()
    snapshot.scan:SetPoint("TOPLEFT",0,-scanTop)
    snapshot.scroll:SetContentHeight(scanTop+38,true)
end

JLP.UIPages=JLP.UIPages or {}
JLP.UIPages[Page.name]=Page
