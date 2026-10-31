local _, JLP = ...
local Page={name="Auction House"}

local SCOPE_BUTTONS={{key="current",label="Current Segment"},{key="next_trainer",label="To Next Trainer"},{key="to_300",label="To 300"}}

-- A missing or half-initialized scanner must never be mistaken for a scan
-- result, and must never enable the manual scan button.
local function advisoryCall(service,method,...)
    if type(service)~="table" or type(service[method])~="function" then return nil end
    local ok,result=pcall(service[method],service,...)
    return ok and result or nil
end

local function money(value)
    local optimizer=JLP:GetModule("CostOptimizer")
    return tostring(advisoryCall(optimizer,"Money",tonumber(value) or 0) or (tonumber(value) or 0))
end

local function ageText(scanner)
    local guard=JLP:GetModule("AuctionScanGuard")
    local text=advisoryCall(guard,"GetStatusText") or advisoryCall(scanner,"GetStatusText") or ""
    text=tostring(text):gsub("^Last successful scan:%s*","")
    text=text:gsub("%s*%-%s*%d+%s+auctions%s*%-%s*%d+%s+item%s+types","")
    return text~="" and text or "Unavailable"
end

local function stringHeight(region,fallback)
    if region and region.GetStringHeight then
        local ok,value=pcall(region.GetStringHeight,region)
        if ok and tonumber(value) and value>0 then return value end
    end
    return fallback or 18
end

-- Untrusted advisory source metadata is not an authority to construct labels.
-- Never stringify an arbitrary table/userdata or claim a verified source name.
local function sourceInline(source)
    source=type(source)=="table" and source or {}
    local name=type(source.name)=="string" and source.name~="" and source.name or nil
    local zone=type(source.zone)=="string" and source.zone~="" and source.zone or nil
    local label=name or zone or "Source unavailable; verify manually"
    local zoneText=name and zone and zone~=name and (" | "..zone) or ""
    local coord=""
    if type(source.nav)=="table" then
        local x,y=tonumber(source.nav.x),tonumber(source.nav.y)
        if x and y and x==x and y==y and x>=0 and x<=1 and y>=0 and y<=1 then
            coord=string.format(" | %.1f, %.1f",x*100,y*100)
        end
    end
    return label..zoneText..coord
end

-- Non-mutating receipt qualification for a manual map click. GetCurrent()
-- WITHOUT a plan reads SourceRoute's existing receipt; passing a plan would
-- call Sync and could rebuild/mutate the route during the authority check.
local function navigationIdentity(stop)
    if type(stop)~="table" or stop.navigable~=true or type(stop.sourceInfo)~="table" then return nil end
    local source=stop.sourceInfo
    if (source.name~=nil and type(source.name)~="string") or
       (source.zone~=nil and type(source.zone)~="string") then return nil end
    local nav=source.nav
    if type(nav)~="table" then return nil end
    local x,y,mapID=tonumber(nav.x),tonumber(nav.y),tonumber(nav.mapID or nav.uiMapID)
    if not x or not y or x~=x or y~=y or x==math.huge or y==math.huge or
       x<0 or x>1 or y<0 or y>1 or
       ((nav.mapID~=nil or nav.uiMapID~=nil) and
       (not mapID or mapID~=mapID or mapID<=0 or mapID==math.huge)) then return nil end
    -- Coordinate/source identity is frozen at Refresh, so a mutated stop cannot
    -- silently reuse the previous page's navigability even if it is the same table.
    return table.concat({tostring(source.name or ""),tostring(source.zone or ""),
        tostring(nav.mapID or nav.uiMapID or ""),tostring(x),tostring(y)},"|")
end

local function currentMapStopVerified(route,plan)
    if Page.currentStopNavigable~=true or type(Page.currentStop)~="table" or
        type(route)~="table" or type(route.GetCurrent)~="function" then return false end
    local receipt=Page.currentNavigationIdentity
    if not receipt or receipt~=navigationIdentity(Page.currentStop) then return false end
    local ok,stop,index,count=pcall(route.GetCurrent,route) -- no Sync/side effects
    if not ok or stop~=Page.currentStop or tonumber(index)~=Page.currentStopIndex or
        tonumber(count)~=Page.currentStopCount or receipt~=navigationIdentity(stop) then return false end
    if Page.currentRouteSignature~=nil and route.signature~=Page.currentRouteSignature then return false end
    if Page.currentRouteRef~=nil and route.route~=Page.currentRouteRef then return false end
    if type(route.PlanSignature)=="function" and type(route.signature)=="string" then
        local valid,signature=pcall(route.PlanSignature,route,plan)
        if not valid or signature~=route.signature then return false end
    end
    local acquisition=JLP:GetModule("AcquisitionPlanner")
    if Page.currentSelectedScope~=nil and type(acquisition)=="table" and type(acquisition.GetSelectedScope)=="function" then
        local scope=advisoryCall(acquisition,"GetSelectedScope")
        if scope~=Page.currentSelectedScope then return false end
    end
    local navigation=JLP:GetModule("Navigation")
    if type(navigation)=="table" then
        -- The actual Navigation:GetTarget is the source-of-truth qualification
        -- for audited map ID and coordinates; no waypoint/map operation here.
        if type(navigation.GetTarget)~="function" or
            type(advisoryCall(navigation,"GetTarget",stop.sourceInfo))~="table" then return false end
    end
    return true
end

-- The route controls are manual advisory actions. Preserve both return values
-- and report failures without turning an unsuccessful result into success.
local function routeAction(method)
    local plan=Page.currentPlan
    if type(plan)~="table" then
        if type(JLP.Print)=="function" then JLP:Print("No active acquisition plan; select a plan manually.") end
        return
    end
    -- An old/hidden Map Stop callback must not navigate an unqualified stop.
    -- Visibility is presentation, not a substitute for this action guard.
    local route=JLP:GetModule("SourceRoute")
    if method=="ShowCurrent" and not currentMapStopVerified(route,plan) then
        if type(JLP.Print)=="function" then JLP:Print("No verified navigable source stop; refresh the route before opening the map.") end
        return
    end
    -- Freeze the displayed stop's exact identity BEFORE any route operation.
    -- SourceRoute:ShowCurrent revalidates it AFTER its internal Sync, so a
    -- progress annotation cannot silently navigate a different target.
    local expected=nil
    if method=="ShowCurrent" then
        local stop=Page.currentStop
        local nav=stop and stop.sourceInfo and stop.sourceInfo.nav
        local navigation=JLP:GetModule("Navigation")
        local target=advisoryCall(navigation,"GetTarget",stop and stop.sourceInfo)
        if type(nav)~="table" or type(target)~="table" then
            if type(JLP.Print)=="function" then JLP:Print("Navigation target unavailable; refresh the route manually.") end
            return
        end
        expected={stop=stop,route=Page.currentRouteRef,signature=Page.currentRouteSignature,
            source=stop.sourceInfo,index=Page.currentStopIndex,count=Page.currentStopCount,
            planScope=plan.scope,name=stop.sourceInfo.name,zone=stop.sourceInfo.zone,
            recipe=stop.sourceInfo.recipe,material=stop.sourceInfo.material,stopKey=stop.key,
            nav={mapID=nav.mapID,uiMapID=nav.uiMapID,x=tonumber(nav.x),y=tonumber(nav.y)},
            targetMapID=tonumber(target.mapID or target.uiMapID),
            targetX=tonumber(target.x),targetY=tonumber(target.y)}
    end
    local ok,first,second=false,nil,nil
    if type(route)=="table" and type(route[method])=="function" then
        ok,first,second=pcall(route[method],route,plan,expected)
    end
    local success=false
    if ok then
        if method=="ShowCurrent" then success=first==true
        elseif method=="SkipCurrent" then success=type(first)=="number" and first>0
        else success=type(first)=="table" end
    end
    local text
    if type(second)=="string" and second~="" then text=second
    elseif success then text=method=="ShowCurrent" and "Map stop opened." or "Source route updated."
    else text="Source route action unavailable; verify the current stop manually." end
    if type(JLP.Print)=="function" then JLP:Print(text) end
    if method~="ShowCurrent" then Page:Refresh() end
end

local function planSummaryText(plan,scanner)
    if type(plan)~="table" then
        local feedback=JLP.UIWidgets and JLP.UIWidgets:FeedbackState("empty","No acquisition plan selected; select a profession step first.")
        return feedback and (feedback.label.." - "..feedback.detail) or "Plan unavailable."
    end
    local resolver=JLP:GetModule("PriceResolver")
    local qualification=advisoryCall(resolver,"QualifySnapshot")
    if type(qualification)~="table" then qualification=nil end
    local pricing=not qualification and "Quote unavailable" or
        (qualification.trustedForCostEstimate and (plan.complete and "Qualified estimate (manual only)" or "Partially priced") or
        ("Advisory only: "..tostring(qualification.status)))
    -- An advisory legacy accumulator is not a quote receipt, even if the
    -- current scanner independently has a trusted snapshot. Fail closed when
    -- the central qualifier is absent/malformed. No new native authority.
    local planner=JLP:GetModule("AcquisitionPlanner")
    local costState=advisoryCall(planner,"QualifyCost",plan,qualification)
    if type(costState)~="table" then costState={status="UNKNOWN"} end
    local status=costState.status
    if plan.routeCoverageIncomplete==true then
        status="ROUTE_INCOMPLETE"
    end
    if costState.trustedForCostEstimate~=true then
        pricing="Plan price unverified ("..tostring(status or "UNKNOWN")..")"
    end
    local knownCost=type(costState.amount)=="number" and costState.amount or nil
    if not knownCost or knownCost~=knownCost or knownCost==math.huge or
        knownCost==-math.huge or knownCost<0 then knownCost=nil end
    local costLabel
    if status=="ROUTE_INCOMPLETE" then
        costLabel="Route incomplete: material totals cannot establish full progression."
    elseif status=="NO_NEEDS" then
        costLabel="No materials require purchase."
    elseif status=="PARTIAL" and knownCost then
        costLabel="Partial known cost (unverified): "..money(knownCost)..
            " — check missing prices manually"
    elseif status=="TRUSTED" and costState.trustedForCostEstimate==true and knownCost then
        costLabel="Qualified cost: "..money(knownCost)
    elseif status=="UNVERIFIED" and knownCost then
        costLabel="Previously calculated cost (unverified): "..money(knownCost)
    else
        costLabel="Cost unavailable — check Auction House manually"
    end
    local parts={
        "Scope: "..tostring(plan.scopeLabel or "Current Segment"),
        costLabel,
        "Last snapshot: "..(plan.snapshotAvailable and ageText(scanner) or "Unavailable"),
        "Status: "..pricing,
    }
    -- Strategy is attached to the exact Planner route used for this material
    -- basket. Display its reason without claiming a globally optimal route.
    local routeDecisions={}
    for key,scopePlan in pairs(type(plan.professionPlans)=="table" and plan.professionPlans or {}) do
        if type(scopePlan)=="table" then
            local first=scopePlan.segments and scopePlan.segments[1]
            local receipt=first and first.routeSelection
            routeDecisions[#routeDecisions+1]=tostring(key)..": "..
                tostring(receipt and receipt.selectedRecipe or "no qualified step")..
                " ["..tostring(receipt and receipt.reason or
                    scopePlan.routeCoverageStatus or "ROUTE_SELECTION_UNAVAILABLE").."]"
        end
    end
    table.sort(routeDecisions)
    parts[#parts+1]="Strategy: "..tostring(plan.strategy or "UNKNOWN")..
        " · route decision(s): "..(#routeDecisions>0 and table.concat(routeDecisions,"; ") or "none")
    local stepRows={}
    for key,receipt in pairs(type(plan.currentStepEconomy70450)=="table" and
        plan.currentStepEconomy70450 or {}) do
        if type(receipt)=="table" and receipt.readOnly==true then
            stepRows[#stepRows+1]=tostring(key).." #"..tostring(receipt.spellID or "?")..
                " "..tostring(receipt.status or "UNKNOWN")
        end
    end
    table.sort(stepRows)
    if #stepRows>0 then
        parts[#parts+1]="Current Step 70450 (advisory): "..table.concat(stepRows,"; ")
    end
    if plan.routeCoverageIncomplete then
        local session=JLP:GetModule("AcquisitionSession")
        local warning=advisoryCall(session,"FormatRouteCoverage",plan)
        parts[#parts+1]="ROUTE INCOMPLETE: "..tostring(warning or "Verify qualified profession route data")
    end
    return table.concat(parts,"\n")
end

local function ensureShoppingRows(card,count)
    local C=JLP.UIComponents
    while #card.rows<count do
        card.rows[#card.rows+1]=C:ShoppingRow(card.scroll.content,card.scroll.__contentWidth)
    end
    for i,row in ipairs(card.rows) do row:SetShown(i<=count) end
end

local function layoutShopping(card,rows)
    rows=rows or {}
    local width=tonumber(card.scroll.__contentWidth) or 450
    local compact=width<480
    local y=compact and 42 or 70
    for i,w in ipairs(card.rows) do
        if rows[i] then
            if w.SetCompactLayout then w:SetCompactLayout(compact,width) end
            w:SetWidth(width)
            w:ClearAllPoints(); w:SetPoint("TOPLEFT",0,-y)
            w:SetShopping(i,rows[i],money); w:Show()
            y=y+(compact and 86 or 42)
        else w:Hide() end
    end
    for _,header in ipairs(card.headers or {}) do header:SetShown(not compact) end
    card.scroll:SetContentHeight(y+12,true)
end

local function layoutSummary(card)
    local y=0
    local minimums={78,90,86,54}
    for i,block in ipairs(card.blocks) do
        local bodyHeight=math.max(18,stringHeight(block.body,36))
        local h=math.max(minimums[i] or 54,bodyHeight+32)
        block:SetHeight(h); block:ClearAllPoints(); block:SetPoint("TOPLEFT",0,-y)
        if i<#card.blocks then
            local rule=card.rules[i]
            rule:ClearAllPoints(); rule:SetPoint("TOPLEFT",0,-(y+h+6)); rule:SetPoint("TOPRIGHT",0,-(y+h+6))
        end
        y=y+h+14
    end
    local buttonTop=y+2
    -- The five buttons require 454 units; wrap in narrow plan cards.
    local available=tonumber(card.scroll.__contentWidth) or 454
    local x,row=0,0
    for _,button in ipairs({card.prevButton,card.mapButton,card.skipButton,
        card.nextButton,card.optimizeButton}) do
        local w=tonumber(button.GetWidth and button:GetWidth()) or 100
        if x>0 and x+w>available then x=0;row=row+1 end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT",card.scroll.content,"TOPLEFT",x,-buttonTop-row*34)
        x=x+w+6
    end
    card.scroll:SetContentHeight(buttonTop+38+row*34,true)
end

function Page:Create(parent)
    if self.frame then return self.frame end
    local W,C,Layout=JLP.UIWidgets,JLP.UIComponents,JLP.UILayout; local L=JLP.UITheme.layout; local f=CreateFrame("Frame",nil,parent); f:SetAllPoints()
    local viewport=CreateFrame("ScrollFrame",nil,f);viewport:SetAllPoints(f)
    local pageRoot=CreateFrame("Frame",nil,viewport)
    pageRoot:SetSize(1078,636)
    if viewport.SetScrollChild then viewport:SetScrollChild(pageRoot) end
    f.pageScroll=viewport;f.pageRoot=pageRoot
    local initial=Layout:PageGeometry(parent,1078,636)
    pageRoot:SetSize(initial.width,initial.height)
    function f:ScrollPage(delta)
        local maximum=math.max(0,(self.pageRoot:GetHeight() or 636)-(self:GetHeight() or 636))
        local offset=self.pageScroll.GetVerticalScroll and self.pageScroll:GetVerticalScroll() or 0
        self.pageScroll:SetVerticalScroll(math.max(0,math.min(maximum,(tonumber(offset) or 0)+(tonumber(delta) or 0))))
    end
    if viewport.EnableMouseWheel then viewport:EnableMouseWheel(true) end
    viewport:SetScript("OnMouseWheel",function(_,wheel) f:ScrollPage(-(tonumber(wheel) or 0)*120) end)

    local status=W:Card(pageRoot,"Auction House Snapshot","primary"); status:SetPoint("TOPLEFT",0,0); status:SetPoint("TOPRIGHT",0,0); status:SetHeight(260)
    status.badge=W:StatusPill(status,"NO SNAPSHOT","warn",118); status.badge:SetPoint("TOPRIGHT",-22,-16)
    status.scan=W:Button(status,"Scan Auction House",170); status.scan:SetHeight(30); status.scan:SetPoint("BOTTOMRIGHT",-22,16)
    status.advisoryBack=W:Button(status,"Return to material guide",192)
    status.advisoryBack:SetHeight(24);status.advisoryBack:SetPoint("TOPRIGHT",-22,-49)
    status.advisoryBack:SetScript("OnClick",function()
        local main=JLP.MainWindow
        if main and main.ReturnFromMaterialReference then main:ReturnFromMaterialReference() end
    end)
    status.advisoryBack:Hide()
    status.materialReference=W:Label(status,"", "GameFontHighlightSmall")
    status.materialReference:SetPoint("TOPLEFT",22,-39)
    local initialBounds=Layout:PageGeometry(parent,1078,636)
    status.materialReference:SetWidth(math.max(160,initialBounds.width-330))
    if status.materialReference.SetWordWrap then status.materialReference:SetWordWrap(true) end
    if status.materialReference.SetHeight then status.materialReference:SetHeight(38) end
    status.materialReference:Hide()
    status.materialManualHint=W:Label(status,"","GameFontHighlightSmall")
    status.materialManualHint:SetPoint("TOPLEFT",22,-104)
    status.materialManualHint:SetWidth(math.max(120,initialBounds.width-56))
    if status.materialManualHint.SetWordWrap then status.materialManualHint:SetWordWrap(true) end
    status.materialManualHint:SetHeight(30)
    status.materialManualHint:Hide()
    status.materialReview=W:Button(status,"Review item manually",174)
    status.materialReview:SetHeight(22)
    status.materialReview:SetPoint("TOPLEFT",200,-80) -- Re-anchored in ApplyLayout when reference is visible
    status.materialReview:SetScript("OnClick",function()
        local main=JLP.MainWindow
        local ref=main and main.GetMaterialReference and main:GetMaterialReference("Auction House")
        local W=JLP.UIWidgets
        if not ref or ref.readOnly~=true or ref.nativeDispatchAllowed~=false or
            not W or not W.ValidReadOnlyMaterialID or not W:ValidReadOnlyMaterialID(ref.materialID) then
            Page.materialBrowseMessage="Material reference unavailable; return to the Guide."
        else
            Page.materialBrowseReceipt=ref
            Page.materialBrowseMessage="Item #"..tostring(ref.materialID)..
                ": use the item name to search manually in the game's Auction House. "..
                "No item-level quote or current price is qualified by this addon snapshot."
        end
        Page:Refresh()
    end)
    status.materialReview:Hide()
    status.ownerServiceNavigate=W:Button(status,"Nearest AH · UNKNOWN",174)
    status.ownerServiceNavigate:SetHeight(22)
    status.ownerServiceNavigate:SetPoint("TOPLEFT",22,-76)
    status.ownerServiceNavigate:SetScript("OnClick",function()
        local actions=JLP:GetModule("IntegratedNavigationActions")
        local source=actions and actions.NearestOwnerService and
           actions:NearestOwnerService("AUCTION_HOUSE") or nil
        if actions then actions:Request("AUCTION_HOUSE",source,
           {explicit=true,owner="AH_USER_CLICK"}) end
    end)
    status.navigateTo=W:Button(status,"Navigate To · UNKNOWN",174)
    status.navigateTo:SetHeight(22);status.navigateTo:SetPoint("TOPRIGHT",-22,-76)
    local navActions=JLP:GetModule("IntegratedNavigationActions")
    if navActions then navActions:Bind(status.navigateTo,function(source)return navActions:CategoryForSource(source)end,function()
        local stop=Page.currentStop
        return Page.currentStopNavigable==true and stop and stop.sourceInfo or nil
    end,function()return {explicit=true,owner="AH_USER_CLICK"} end) end
    status.scan:SetScript("OnClick",function()
        local guard=JLP:GetModule("AuctionScanGuard")
        local ok,reason=false,"Auction scan guard unavailable."
        if type(guard)=="table" and type(guard.BeginManualScan)=="function" then
            local accepted,result,message=pcall(function() return guard:BeginManualScan() end)
            if accepted then ok,reason=result==true,message
            else reason="Auction scan could not be started; verify manually." end
        end
        JLP:Print(reason or (ok and "Scan requested." or "Scan unavailable."))
        Page:Refresh()
    end)

    status.metricPanel=CreateFrame("Frame",nil,status); status.metricPanel:SetPoint("TOPLEFT",22,-92); status.metricPanel:SetPoint("TOPRIGHT",-22,-92); status.metricPanel:SetHeight(104)
    W:Fill(status.metricPanel,"panelAlt","BACKGROUND"); W:Border(status.metricPanel,"border",1)
    local bounds=Layout:PageGeometry(parent,1078,636)
    local contentWidth=bounds.width;f.pageGeometry=bounds
    local metricWidth=(contentWidth-44)/4
    status.metrics={};status.metricSeparators={}
    for i=1,4 do
        local m=C:MetricTile(status.metricPanel,metricWidth,102); status.metrics[i]=m
        if i==1 then m:SetPoint("TOPLEFT",0,0) else m:SetPoint("LEFT",status.metrics[i-1],"RIGHT",0,0) end
        if i>1 then local sep=status.metricPanel:CreateTexture(nil,"ARTWORK"); sep:SetTexture("Interface\\Buttons\\WHITE8X8"); sep:SetVertexColor(0.35,0.52,0.65,0.55); sep:SetPoint("TOPLEFT",metricWidth*(i-1),-12); sep:SetPoint("BOTTOMLEFT",metricWidth*(i-1),12); sep:SetWidth(1); status.metricSeparators[i-1]=sep end
    end

    status.scopeButtons={}; local x=22
    for _,def in ipairs(SCOPE_BUTTONS) do
        local width=def.key=="next_trainer" and 145 or (def.key=="current" and 135 or 92)
        local b=W:Button(status,def.label,width); b:SetHeight(26); b:SetPoint("BOTTOMLEFT",x,10)
        b:SetScript("OnClick",function()
            local a=JLP:GetModule("AcquisitionPlanner")
            -- A failed scope update must not emit a misleading settings event.
            local committed=advisoryCall(a,"SetSelectedScope",def.key)
            local effective=advisoryCall(a,"GetSelectedScope")
            -- Setter acknowledgement alone does not imply persisted profile
            -- state. Only an exact readback may broadcast SETTINGS_CHANGED.
            if committed~=def.key or effective~=def.key then
                if type(JLP.Print)=="function" then JLP:Print("Acquisition scope could not be changed or saved; current selection retained.") end
                Page:Refresh()
                return
            end
            advisoryCall(JLP.EventBus,"Emit","SETTINGS_CHANGED")
            Page:Refresh()
        end)
        status.scopeButtons[#status.scopeButtons+1]={button=b,key=def.key,label=def.label}; x=x+width+8
    end

    local gap=L.cardGap or 14; local lowerWidth=Layout:EqualColumns(contentWidth,2,gap); local contentHeight=bounds.height; local lowerHeight=math.max(250,contentHeight-298-gap)

    local shopping=W:Card(pageRoot,"Material Acquisition","primary"); shopping:SetPoint("BOTTOMLEFT",0,0); shopping:SetSize(lowerWidth,lowerHeight)
    shopping.badge=W:StatusPill(shopping,"CURRENT","gold",112); shopping.badge:SetPoint("TOPRIGHT",-22,-16)
    shopping.scroll=Layout:CardScrollArea(shopping,{cardWidth=lowerWidth,cardHeight=lowerHeight})
    local shc=shopping.scroll.content
    shopping.session=W:Label(shc,"","GameFontHighlightSmall"); shopping.session:SetPoint("TOPLEFT",0,0); shopping.session:SetPoint("TOPRIGHT",0,0); shopping.session:SetTextColor(JLP.UITheme:Color("muted"))
    shopping.rule=W:SectionRule(shc); shopping.rule:SetPoint("TOPLEFT",0,-30); shopping.rule:SetPoint("TOPRIGHT",0,-30)
    shopping.headers={}
    local headers={{"#",0,20},{"Item",32,132},{"Cost (each)",170,76},{"Total Cost",250,80},{"Owned",334,42},{"Bags",378,42},{"Bank",422,42}}
    for i,h in ipairs(headers) do local fs=W:Label(shc,h[1],"GameFontHighlightSmall"); fs:SetPoint("TOPLEFT",h[2],-44); fs:SetWidth(h[3]); fs:SetJustifyH(i>4 and "CENTER" or "LEFT"); fs:SetTextColor(JLP.UITheme:Color("muted")); shopping.headers[i]=fs end
    shopping.rows={}
    shopping.scroll:SetContentHeight(118)

    local summary=W:Card(pageRoot,"Plan & Route","primary"); summary:SetPoint("BOTTOMRIGHT",0,0); summary:SetSize(lowerWidth,lowerHeight)
    summary.scroll=Layout:CardScrollArea(summary,{cardWidth=lowerWidth,cardHeight=lowerHeight})
    local suc=summary.scroll.content
    summary.blocks={}; summary.rules={}
    for i=1,4 do
        local b=C:TextBlock(suc,summary.scroll.__contentWidth,64); summary.blocks[i]=b
        if i<4 then local rule=W:SectionRule(suc); summary.rules[i]=rule end
    end
    summary.prevButton=W:Button(suc,"Previous",76); summary.prevButton:SetHeight(28); summary.prevButton:Hide(); summary.prevButton:SetScript("OnClick",function() routeAction("Previous") end)
    summary.mapButton=W:Button(suc,"Map Stop",92); summary.mapButton:SetHeight(28); summary.mapButton:Hide(); summary.mapButton:SetScript("OnClick",function() routeAction("ShowCurrent") end)
    summary.skipButton=W:Button(suc,"Skip Stop",92); summary.skipButton:SetHeight(28); summary.skipButton:Hide(); summary.skipButton:SetScript("OnClick",function() routeAction("SkipCurrent") end)
    summary.nextButton=W:Button(suc,"Next",68); summary.nextButton:SetHeight(28); summary.nextButton:Hide(); summary.nextButton:SetScript("OnClick",function() routeAction("Next") end)
    summary.optimizeButton=W:Button(suc,"Re-optimize",102); summary.optimizeButton:SetHeight(28); summary.optimizeButton:Hide(); summary.optimizeButton:SetScript("OnClick",function() routeAction("Reoptimize") end)
    summary.scroll:SetContentHeight(360)

    shopping.__layoutWidth=lowerWidth; summary.__layoutWidth=lowerWidth; shopping.__layoutHeight=lowerHeight; summary.__layoutHeight=lowerHeight; shopping.__equalSplit="ah-lower"; summary.__equalSplit="ah-lower"
    f.status=status; f.shopping=shopping; f.summary=summary; f.equalLowerSplit=true; f.boundedContainers=true; self.frame=f
    if f.SetScript then f:SetScript("OnSizeChanged",function()Page:ApplyLayout()end) end
    self:ApplyLayout()
    return f
end

function Page:ApplyLayout()
    local f=self.frame
    if not (f and f.pageRoot and f.status) then return false end
    local w=tonumber(f.GetWidth and f:GetWidth()) or 0
    local h=tonumber(f.GetHeight and f:GetHeight()) or 0
    if w<=0 then w=1078 end
    if h<=0 then h=636 end
    local stacked=w<1040
    local gap=JLP.UITheme.layout.cardGap or 14
    local status=f.status
    -- One measured snapshot layout transaction. Conditional reference material
    -- receives its own band; KPI and footer regions cannot occupy that band.
    local hasReturn=status.advisoryBack and status.advisoryBack.IsShown and status.advisoryBack:IsShown()
    local hasReference=status.materialReference and status.materialReference.IsShown and status.materialReference:IsShown()
    local hasManualHint=status.materialManualHint and status.materialManualHint.IsShown and status.materialManualHint:IsShown()
    local hasReview=status.materialReview and status.materialReview.IsShown and status.materialReview:IsShown()
    local referenceTop=hasReturn and 78 or 51
    local referenceHeight=hasReference and math.max(38,tonumber(status.materialReference.GetStringHeight and status.materialReference:GetStringHeight()) or 38) or 0
    referenceHeight=math.min(16000,referenceHeight)
    local referenceBottom=referenceTop+referenceHeight
    local reviewTop=nil
    if hasReview then
        reviewTop=referenceBottom+6
        referenceBottom=reviewTop+22+6
    end
    local manualHintTop=nil
    if hasManualHint then
        manualHintTop=referenceBottom
        referenceBottom=manualHintTop+math.max(34,tonumber(status.materialManualHint.GetStringHeight and status.materialManualHint:GetStringHeight()) or 34)+6
    end
    local metricTop=math.max(92,hasReference and referenceBottom+16 or 92)
    local metricCols=w>=740 and 4 or w>=450 and 2 or 1
    local metricRows=math.ceil(4/metricCols)
    local metricHeight=metricRows*104
    local normalScopeWidths={135,145,92}
    local sideBySide=w>=620
    local scopeAvail=math.max(1,w-44-(sideBySide and 188 or 0))
    local scopeRows={};local x=0;local row=1
    for i,entry in ipairs(f.status.scopeButtons or {}) do
        local bw=math.max(1,tonumber(entry.button:GetWidth()) or normalScopeWidths[i] or 92)
        if x>0 and x+bw>scopeAvail then row=row+1;x=0 end
        scopeRows[i]={x=x,row=row,width=bw}
        x=x+bw+8
    end
    local scopeCount=math.max(1,row)
    local footerHeight=sideBySide and (48+(scopeCount-1)*32) or (80+(scopeCount-1)*32)
    local statusHeight=math.max(260,metricTop+metricHeight+16+footerHeight)
    local lowerWidth=stacked and w or JLP.UILayout:EqualColumns(w,2,gap)
    local lowerHeight=stacked and 340 or math.max(250,h-statusHeight-gap)
    status:ClearAllPoints();status:SetPoint("TOPLEFT",f.pageRoot,"TOPLEFT",0,0)
    status:SetSize(w,statusHeight)
    if status.SetHeadingRightInset then status:SetHeadingRightInset(166) end
    status.badge:ClearAllPoints();status.badge:SetPoint("TOPRIGHT",status,"TOPRIGHT",-22,-16)
    status.advisoryBack:ClearAllPoints();status.advisoryBack:SetPoint("TOPRIGHT",status,"TOPRIGHT",-22,-49)
    status.materialReference:ClearAllPoints()
    status.materialReference:SetPoint("TOPLEFT",status,"TOPLEFT",22,-referenceTop)
    status.materialReference:SetWidth(math.max(120,w-44))
    if hasReference then status.materialReference:SetHeight(referenceHeight) end
    if hasReview then
        status.materialReview:ClearAllPoints()
        status.materialReview:SetPoint("TOPLEFT",status,"TOPLEFT",22,-reviewTop)
    end
    if hasManualHint then
        status.materialManualHint:ClearAllPoints()
        status.materialManualHint:SetPoint("TOPLEFT",status,"TOPLEFT",22,-manualHintTop)
        status.materialManualHint:SetHeight(math.max(34,tonumber(status.materialManualHint.GetStringHeight and status.materialManualHint:GetStringHeight()) or 34))
    end
    status.metricPanel:ClearAllPoints()
    status.metricPanel:SetPoint("TOPLEFT",status,"TOPLEFT",22,-metricTop)
    status.metricPanel:SetPoint("TOPRIGHT",status,"TOPRIGHT",-22,-metricTop)
    status.metricPanel:SetHeight(metricHeight)
    local metricWidth=math.max(1,(w-44)/metricCols)
    for i,metric in ipairs(status.metrics or {}) do
        metric:ClearAllPoints()
        local col=(i-1)%metricCols
        local mrow=math.floor((i-1)/metricCols)
        metric:SetPoint("TOPLEFT",status.metricPanel,"TOPLEFT",col*metricWidth,-mrow*104)
        metric:SetWidth(metricWidth)
    end
    for i,separator in ipairs(status.metricSeparators or {}) do
        separator:ClearAllPoints()
        if i<metricCols then
            separator:SetPoint("TOPLEFT",status.metricPanel,"TOPLEFT",metricWidth*i,-12)
            separator:SetPoint("BOTTOMLEFT",status.metricPanel,"BOTTOMLEFT",metricWidth*i,12)
            separator:Show()
        else
            separator:Hide()
        end
    end
    status.scan:ClearAllPoints()
    status.scan:SetPoint("BOTTOMRIGHT",status,"BOTTOMRIGHT",-22,16)
    for i,entry in ipairs(status.scopeButtons or {}) do
        local slot=scopeRows[i]
        local bottom=16+(sideBySide and 0 or 40)+(scopeCount-slot.row)*32
        entry.button:ClearAllPoints()
        entry.button:SetPoint("BOTTOMLEFT",status,"BOTTOMLEFT",22+slot.x,bottom)
    end
    f.shopping:ClearAllPoints();f.summary:ClearAllPoints()
    f.shopping:SetSize(lowerWidth,lowerHeight)
    f.summary:SetSize(lowerWidth,lowerHeight)
    if stacked then
        f.shopping:SetPoint("TOPLEFT",f.status,"BOTTOMLEFT",0,-gap)
        f.summary:SetPoint("TOPLEFT",f.shopping,"BOTTOMLEFT",0,-gap)
    else
        f.shopping:SetPoint("BOTTOMLEFT",f.pageRoot,"BOTTOMLEFT",0,0)
        f.summary:SetPoint("BOTTOMRIGHT",f.pageRoot,"BOTTOMRIGHT",0,0)
    end
    f.pageRoot:SetSize(w,stacked and math.max(h,statusHeight+2*gap+2*lowerHeight) or h)
    f.shopping.scroll:ApplyCardBounds(lowerWidth,lowerHeight)
    f.summary.scroll:ApplyCardBounds(lowerWidth,lowerHeight)
    f.status.materialManualHint:SetWidth(math.max(120,w-44))
    for _,row in ipairs(f.shopping.rows or {}) do
        row:SetWidth(f.shopping.scroll.__contentWidth)
        if row.SetCompactLayout then row:SetCompactLayout(f.shopping.scroll.__contentWidth<480,f.shopping.scroll.__contentWidth) end
    end
    for _,block in ipairs(f.summary.blocks or {}) do block:SetWidth(f.summary.scroll.__contentWidth) end
    f.shopping.__layoutWidth=lowerWidth;f.summary.__layoutWidth=lowerWidth
    f.shopping.__layoutHeight=lowerHeight;f.summary.__layoutHeight=lowerHeight
    if not f.outerScrollbar then
        f.outerScrollbar=JLP.UILayout:AttachNativeScrollbar(f.pageScroll,
            {owner=f,right=-2,top=-2,bottom=2})
    end
    if f.outerScrollbar then f.outerScrollbar:Refresh() end
    return true
end

function Page:Refresh()
    if self.frame and self.frame.status and self.frame.status.advisoryBack then
        local main=JLP.MainWindow
        self.frame.status.advisoryBack:SetShown(main and main.advisoryReturn~=nil and main.activePage=="Auction House")
    end
    if not self.frame then return end
    self:ApplyLayout()
    if self.frame.status and self.frame.status.ownerServiceNavigate then
        local actions=JLP:GetModule("IntegratedNavigationActions")
        local source=actions and actions.NearestOwnerService and
           actions:NearestOwnerService("AUCTION_HOUSE") or nil
        if actions then actions:Update(self.frame.status.ownerServiceNavigate,
            "AUCTION_HOUSE",source,{explicit=true}) end
        if source and self.frame.status.ownerServiceNavigate.SetText then
            self.frame.status.ownerServiceNavigate:SetText("Navigate · "..tostring(source.name or "Auction House")) end
    end
    if self.frame.status and self.frame.status.navigateTo then
        local actions=JLP:GetModule("IntegratedNavigationActions")
        local stop=self.currentStop
        local source=self.currentStopNavigable==true and stop and stop.sourceInfo or nil
        if actions then actions:Update(self.frame.status.navigateTo,function(item)return actions:CategoryForSource(item)end,source,{explicit=true}) end
    end
    local scanner=JLP:GetModule("AuctionScanner")
    local snapshot=advisoryCall(scanner,"GetSnapshot")
    local snap=type(snapshot)=="table" and snapshot or nil
    local main=JLP.MainWindow
    local ref=main and main.GetMaterialReference and main:GetMaterialReference("Auction House")
    local valid=ref and ref.readOnly==true and ref.nativeDispatchAllowed==false and
        JLP.UIWidgets and JLP.UIWidgets.ValidReadOnlyMaterialID and
        JLP.UIWidgets:ValidReadOnlyMaterialID(ref.materialID)
    if self.frame.status and self.frame.status.materialReview then
        self.frame.status.materialReview:SetShown(valid==true)
        if ref~=self.materialBrowseReceipt then
            self.materialBrowseReceipt=nil;self.materialBrowseMessage=nil
        end
    end
    local remaining=tonumber(advisoryCall(scanner,"GetCooldownRemaining")) or 0
    if remaining<0 then remaining=0 end
    local cooldown=remaining>0 and string.format("%d:%02d",math.floor(remaining/60),remaining%60) or "Ready"
    local status=self.frame.status
    if status.materialReference then
        local main=JLP.MainWindow
        local ref=main and main.GetMaterialReference and main:GetMaterialReference("Auction House")
        if ref then
            -- Aggregate auction metadata does not qualify a per-item quote.
            local age=snap and ageText(scanner) or "NO SNAPSHOT"
            local W=JLP.UIWidgets
            local summary=W and W.MaterialInspectionSummary and
                W:MaterialInspectionSummary(ref,"Auction House",nil,age) or
                "Material reference · item price UNKNOWN"
            -- Manual lookup changes ONLY the instructions, never the qualified
            -- UNKNOWN/STALE snapshot status or the item-level quote authority.
            status.materialReference:SetText(summary)
            if status.materialManualHint then
                local selected=self.materialBrowseReceipt==ref and
                    type(self.materialBrowseMessage)=="string" and self.materialBrowseMessage~=""
                local name=W and W.BoundedUTF8Label and
                    W:BoundedUTF8Label(ref.materialName,26) or "Material"
                status.materialManualHint:SetText(selected and
                    ("Manual AH lookup: '"..name.."' (#"..tostring(ref.materialID)..
                    "). Price UNKNOWN · No item-specific scan.") or "")
                status.materialManualHint:SetShown(selected==true)
            end
            -- The status line remains the qualified receipt regardless of action.
            -- Snapshot staleness belongs to the scanner, not this button.
            -- Avoid any change to live scanner/guard state here.
            -- (Do not overwrite summary with manual instructions.)
            -- The primary status label is intentionally set exactly once.
            status.materialReference:Show()
        else
            -- A character/recipe change can invalidate the read-only receipt
            -- while AH remains open. Keep the safe Return button, but explain
            -- why the manual item lookup is no longer qualified.
            local old=main and main.advisoryReturn
            if old and old.target=="Auction House" and old.contextInvalidated==true then
                status.materialReference:SetText("STALE REFERENCE · character/source changed. Manual item lookup disabled; Return to Guide and reopen the material.")
                status.materialReference:Show()
            else status.materialReference:Hide() end
            if status.materialManualHint then status.materialManualHint:Hide() end
        end
    end
    -- Refresh modified reference visibility and text heights after the first
    -- layout pass. Reflow once; ApplyLayout never calls Refresh recursively.
    self:ApplyLayout()
    local guard=JLP:GetModule("AuctionScanGuard")
    local diagnostics=advisoryCall(guard,"GetDiagnostics")
    local diag=type(diagnostics)=="table" and diagnostics or
        {state="NO_SNAPSHOT",snapshotComplete=false,apiAvailable=false,scanInProgress=false}
    local badge=diag.scanInProgress and "SCAN PENDING" or
        not diag.apiAvailable and "API UNAVAILABLE" or
        diag.state=="SCAN_TIMEOUT" and "SCAN TIMEOUT" or
        diag.state~="SNAPSHOT_AVAILABLE" and diag.state~="NO_SNAPSHOT" and "SCAN ISSUE" or
        snap and not diag.snapshotComplete and "PARTIAL DATA" or
        snap and diag.priceDepthLimited and "LIMITED PRICE DEPTH" or
        snap and "SNAPSHOT READY" or "NO SNAPSHOT"
    status.badge:SetStatus(badge,badge=="SNAPSHOT READY" and "good" or "warn")
    local scanLabel=diag.scanInProgress and diag.expectedRows and diag.expectedRows>0 and
        string.format("Processing %d/%d (older snapshot retained)",diag.processedRows or 0,diag.expectedRows) or
        ((snap or diag.state~="NO_SNAPSHOT") and ageText(scanner) or "Never")
    status.metrics[1]:SetMetric("scan","Last scan / issue",scanLabel,
        snap and diag.state=="SNAPSHOT_AVAILABLE" and "text" or "warn")
    status.metrics[2]:SetMetric("auction","Auctions",snap and tostring(snap.auctionCount or "unknown") or "—")
    status.metrics[3]:SetMetric("itemtypes","Item types",snap and tostring(snap.itemCount or "unknown") or "—")
    status.metrics[4]:SetMetric("cooldown","Full-scan cooldown",cooldown,remaining>0 and "warn" or "good")
    -- A disabled action reflects the scanner's actual authority/cooldown;
    -- opening AH and a manual click remain prerequisites.
    local canScan=type(guard)=="table" and type(guard.BeginManualScan)=="function" and
        advisoryCall(guard,"CanStartScan")==true and
        type(scanner)=="table" and type(scanner.GetSnapshot)=="function"
    if status.scan.SetEnabled then status.scan:SetEnabled(canScan==true) end
    status.scan:SetAlpha(canScan and 1 or 0.55)
    -- Downstream services are advisory. An exception or malformed response must
    -- clear the previous plan, never leak stale quantities into this page.
    local acquisition=JLP:GetModule("AcquisitionPlanner")
    local selectedScope=advisoryCall(acquisition,"GetSelectedScope")
    if type(selectedScope)~="string" then selectedScope="current" end
    for _,entry in ipairs(status.scopeButtons or {}) do entry.button.label:SetTextColor(JLP.UITheme:Color(entry.key==selectedScope and "gold" or "text")) end
    local plan=advisoryCall(acquisition,"BuildSelected")
    if type(plan)~="table" then plan=nil end
    local route=JLP:GetModule("SourceRoute")
    local sessions=JLP:GetModule("AcquisitionSession")
    if not plan then
        Page.currentPlan=nil; Page.currentSession=nil; Page.currentNavigationSource=nil; Page.currentStopNavigable=false
        Page.currentStop=nil; Page.currentStopIndex=nil; Page.currentStopCount=nil
        Page.currentRouteSignature=nil; Page.currentRouteRef=nil; Page.currentNavigationIdentity=nil; Page.currentSelectedScope=nil
        for _,r in ipairs(self.frame.shopping.rows) do r:Hide() end
        self.frame.shopping.badge:SetStatus("UNAVAILABLE","warn"); self.frame.shopping.session:SetText("Acquisition sessions unavailable."); self.frame.shopping.scroll:SetContentHeight(118,true)
        local unavailable=JLP.UIWidgets and JLP.UIWidgets.AdvisoryUnavailable and
            JLP.UIWidgets:AdvisoryUnavailable("acquisition")
        self.frame.summary.blocks[1]:SetBlock("plan","PLAN SUMMARY",
            unavailable and unavailable.text or "Acquisition planner unavailable.")
        self.frame.summary.blocks[2]:SetBlock("acquisition","ACQUISITION SESSION","Unavailable.")
        self.frame.summary.blocks[3]:SetBlock("route","SOURCE ROUTE","Unavailable.")
        self.frame.summary.blocks[4]:SetBlock("workspace","WORKSPACE","Unavailable.")
        self.frame.summary.prevButton:Hide(); self.frame.summary.mapButton:Hide(); self.frame.summary.skipButton:Hide(); self.frame.summary.nextButton:Hide(); self.frame.summary.optimizeButton:Hide(); layoutSummary(self.frame.summary)
        return
    end

    Page.currentPlan=plan
    local sessionModel=advisoryCall(sessions,"Build",plan)
    if type(sessionModel)~="table" then sessionModel=nil end
    Page.currentSession=sessionModel
    local badgeLabel,badgeTone="UNAVAILABLE","warn"
    if sessionModel and sessionModel.status=="complete" then badgeLabel,badgeTone="COMPLETE","good" end
    if sessionModel and sessionModel.status=="active" then badgeLabel=sessionModel.currentReason=="here-now" and "HERE NOW" or "NEXT"; badgeTone=sessionModel.currentReason=="here-now" and "good" or "gold" end
    if plan.routeCoverageIncomplete==true then
        badgeLabel,badgeTone=sessionModel and sessionModel.status=="profession-unavailable" and "NO PRIMARY" or "ROUTE GAP","warn"
    end
    self.frame.shopping.badge:SetStatus(badgeLabel,badgeTone)
    local compact=advisoryCall(sessions,"FormatCompact",sessionModel)
    self.frame.shopping.session:SetText(type(compact)=="string" and compact or "Acquisition sessions unavailable; verify manually.")
    local shoppingRows={}
    if type(plan.shopping)=="table" then
        for _,row in ipairs(plan.shopping) do
            if type(row)=="table" then shoppingRows[#shoppingRows+1]=row end
        end
    end
    ensureShoppingRows(self.frame.shopping,#shoppingRows); layoutShopping(self.frame.shopping,shoppingRows)
    local qualification=sessionModel and sessionModel.sourceQualification
    if type(qualification)~="table" then qualification=nil end
    local qualificationText=advisoryCall(sessions,"FormatSources",qualification)
    if type(qualificationText)~="string" or qualificationText=="" then
        qualificationText="Source qualification unavailable; verify manually"
    end
    self.frame.summary.blocks[1]:SetBlock("plan","PLAN SUMMARY",
        planSummaryText(plan,scanner).."\n"..qualificationText)
    local currentSession=sessionModel and sessionModel.current
    if type(currentSession)~="table" then currentSession=nil end
    local sessionText
    if sessionModel and sessionModel.status=="complete" and not plan.routeCoverageIncomplete then sessionText="All material acquisition sessions are complete."
    elseif plan.routeCoverageIncomplete and not currentSession then
        sessionText="ROUTE INCOMPLETE: "..tostring(advisoryCall(sessions,"FormatRouteCoverage",sessionModel) or
            "Verify profession route data and refresh this scope.")
    elseif currentSession then
        sessionText=table.concat({"Current session: "..tostring(currentSession.label or "Material stop"),"Remaining sessions: "..tostring(tonumber(sessionModel.remainingSessions) or (type(sessionModel.sessions)=="table" and #sessionModel.sessions or 0)),sessionModel.currentReason=="here-now" and "You are at the correct workspace for this session." or "This is the next material stop. Progress is recalculated from live inventory and interface state."},"\n")
    else sessionText="Acquisition session unavailable." end
    if plan.routeCoverageIncomplete and currentSession then
        sessionText=sessionText.."\nROUTE INCOMPLETE: "..
            tostring(advisoryCall(sessions,"FormatRouteCoverage",sessionModel) or "Verify route data")
    end
    self.frame.summary.blocks[2]:SetBlock("acquisition","ACQUISITION SESSION",sessionText)

    local currentStop,index,count=nil,0,0; local routeText="No verified trainer or recipe-source stops; review manually."; local counts={pending=0,completed=0,skipped=0}
    if type(route)=="table" then
        local routeModel=advisoryCall(route,"Sync",plan)
        -- Only consume a route receipt if Sync completed with a valid model.
        -- A previous session's GetCurrent must not leak into a failed rebuild.
        local routeCurrent=type(routeModel)=="table" and type(route.GetCurrent)=="function" and {pcall(route.GetCurrent,route)} or nil
        if routeCurrent and routeCurrent[1] then
            currentStop,index,count=routeCurrent[2],routeCurrent[3],routeCurrent[4]
        end
        if type(currentStop)~="table" then currentStop=nil end
        index=tonumber(index) or 0; count=tonumber(count) or 0
        if type(routeModel)=="table" and type(routeModel.progressCounts)=="table" then counts=routeModel.progressCounts end
        if currentStop then
            local hint=advisoryCall(route,"GetTravelHint")
            routeText=table.concat({string.format("Progress: %d pending | %d done | %d skipped",tonumber(counts.pending) or 0,tonumber(counts.completed) or 0,tonumber(counts.skipped) or 0),string.format("Current stop: %d / %d | %s",index,count,sourceInline(currentStop.sourceInfo)),hint and ("Travel: "..tostring(hint)) or "Travel: route is not fully audited for this transition."},"\n")
        end
    end
    self.frame.summary.blocks[3]:SetBlock("route","SOURCE ROUTE",routeText)

    local executionFlow=JLP:GetModule("ExecutionFlow")
    local flow=advisoryCall(executionFlow,"Build")
    if type(flow)~="table" then flow=nil end
    local workspaceText="Execution flow unavailable; verify manually."
    if flow then
        local available=tonumber(flow.availableHereCount) or 0
        if available>0 then
            local context=type(flow.currentContext)=="table" and flow.currentContext or nil
            workspaceText=string.format("Current: %s | %d action%s available here",tostring(context and context.label or "Current"),available,available==1 and "" or "s")
        else workspaceText=string.format("Next: %s    Planned switches: %d",tostring(flow.nextStationLabel or "Other"),tonumber(flow.switchCount) or 0) end
    end
    self.frame.summary.blocks[4]:SetBlock("workspace","WORKSPACE",workspaceText)

    local hasRoute=count>0
    Page.currentNavigationIdentity=navigationIdentity(currentStop)
    Page.currentStopNavigable=Page.currentNavigationIdentity~=nil
    Page.currentStop=Page.currentStopNavigable and currentStop or nil
    Page.currentStopIndex=Page.currentStopNavigable and index or nil
    Page.currentStopCount=Page.currentStopNavigable and count or nil
    Page.currentRouteSignature=route and route.signature or nil
    Page.currentRouteRef=route and route.route or nil
    Page.currentSelectedScope=selectedScope
    self.frame.summary.prevButton:SetShown(currentStop~=nil); self.frame.summary.nextButton:SetShown(currentStop~=nil)
    self.frame.summary.mapButton:SetShown(Page.currentStopNavigable)
    self.frame.summary.skipButton:SetShown(currentStop~=nil); self.frame.summary.optimizeButton:SetShown(hasRoute)
    Page.currentNavigationSource=Page.currentStopNavigable and currentStop.sourceInfo or nil
    layoutSummary(self.frame.summary)
end

JLP.UIPages=JLP.UIPages or {}
JLP.UIPages[Page.name]=Page
