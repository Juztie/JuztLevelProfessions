local _, JLP = ...

-- Four view states: the group overview plus three independent profession
-- content containers. No map coordinates are invented and no craft API is called.
local Page={name="Secondaries",mode="overview",contract="secondary-guide-ui-v1"}
-- A Clear command never claims success if cancellation was rejected or only
-- partially completed. This is a pure advisory handler shared by the button.
function Page:CancelRouteForView(view)
    if not view or not view.includeGathering then return false,"FISHING_ONLY_CONTEXT" end
    local route=JLP:GetModule("GatheringRouteService")
    if not route or type(route.Cancel)~="function" then
        return false,"ROUTE_SERVICE_UNAVAILABLE"
    end
    local invoked,ok,reason=pcall(route.Cancel,route,"CLEARED_BY_USER")
    if not invoked then ok=false;reason="ROUTE_CANCEL_EXCEPTION" end
    local confirmed=ok==true
    if not confirmed and type(route.QuarantineUnconfirmedCancellation)=="function" then
        pcall(route.QuarantineUnconfirmedCancellation,route,reason or "ROUTE_CANCEL_UNCONFIRMED")
    end
    -- An uncertain cancellation cannot entitle the embedded viewport to its old
    -- overlay receipt. The router remains the single authority for both views.
    view.routeResult=nil
    if not confirmed then view.routeFeedback="Stop not confirmed · "..tostring(reason or "UNKNOWN") end
    return confirmed,reason,confirmed and "CLEARED_BY_USER" or nil
end

local ORDER={"COOKING","FISHING","FIRST_AID"}
function Page:MaterialOwnerSignature()
    local inventory=type(JLP.GetModule)=="function" and JLP:GetModule("Inventory") or nil
    if not inventory or type(inventory.GetCharacterKey)~="function" then return "OWNER_UNKNOWN" end
    local ok,key=pcall(inventory.GetCharacterKey,inventory)
    return ok and type(key)=="string" and key~="" and key or "OWNER_UNKNOWN"
end
-- Receipt handling is independent of graphics and can be verified with
-- isolated route/state mocks. It changes only transient advisory feedback.
function Page:RecordRouteReceipt(view,ok,reason,status)
    local resultModule=JLP:GetModule("GatheringRouteResult")
    local route=JLP:GetModule("GatheringRouteService")
    local shared=JLP:GetModule("GatheringSharedMapState")
    local current=shared and type(shared.GetSnapshot)=="function" and shared:GetSnapshot()
    view.routeResult=resultModule and resultModule:FromAttempt(ok,reason,status)
    if view.routeResult then
        if type(resultModule.Bind)=="function" then
            resultModule:Bind(view.routeResult,view.lastMapID,route)
        else view.routeResult.mapID=view.lastMapID end
        view.routeResult.mode=type(current)=="table" and current.mode or nil
    end
    local labelText=JLP.UIWidgets and type(JLP.UIWidgets.GatheringFeedback)=="function" and
        JLP.UIWidgets:GatheringFeedback(nil,view.routeResult)
    view.routeFeedback=labelText or (view.routeResult and view.routeResult.message) or
        (ok and "Generating route..." or "Route unavailable: "..tostring(reason or "ROUTE_UNAVAILABLE"))
    -- Without a validated context identity a receipt cannot persist. Publish
    -- immediate text feedback, then let the next Refresh discard it.
    if view.routeResult and view.routeResult.identityPolicy=="transient-unverified" and
        type(JLP.Print)=="function" then JLP:Print(view.routeFeedback) end
    return view.routeResult
end
function Page:InvalidateRouteReceipt(view,mapID,options)
    if not view or not view.routeResult then return false end
    local resultModule=JLP:GetModule("GatheringRouteResult")
    local router=JLP:GetModule("GatheringRouteService")
    if (resultModule and type(resultModule.IsCurrent)=="function" and
        not resultModule:IsCurrent(view.routeResult,mapID,router)) or
        (type(options)=="table" and view.routeResult.mode and view.routeResult.mode~=options.mode) then
        view.routeResult=nil;view.routeFeedback=nil
        return true
    end
    return false
end

local WIDTH,HEIGHT,GAP=1078,636,14

local function model() return JLP:GetModule("SecondaryWorkspace") end
local function label(parent,text,x,y,width,template,tone)
    local L=JLP.UIWidgets:Label(parent,text,template or "GameFontHighlight")
    L:SetPoint("TOPLEFT",x,y)
    if width then L:SetWidth(width) end
    if L.SetJustifyH then L:SetJustifyH("LEFT") end
    if tone then L:SetTextColor(JLP.UITheme:Color(tone)) end
    return L
end
local function row(parent,heading,y,width)
    local h=label(parent,heading,22,y,width,"GameFontHighlightSmall","muted")
    local value=label(parent,"-",22,y-22,width,"GameFontHighlight")
    return {heading=h,value=value}
end
local function setRow(row,text)
    if row and row.value then row.value:SetText(text or "Not documented") end
end
local function makeCard(parent,title,x,width,height)
    local c=JLP.UIWidgets:Card(parent,title,"primary")
    c:SetPoint("TOPLEFT",x,0)
    c:SetSize(width,height)
    return c
end
local function bandName(band)
    if not band then return "No verified current skill band" end
    return tostring(band.action or "Continue").." · skill "..tostring(band.skillMin).."-"..tostring(band.skillMax)
end
local function resources(band)
    if not band or #(band.resources or {})==0 then return "No exact resource list documented" end
    return table.concat(band.resources,", ")
end
local function zones(band)
    if not band or #(band.zones or {})==0 then return "No specific zone confirmed" end
    return table.concat(band.zones,", ")
end
local function skills(snapshot)
    if not snapshot or not snapshot.learned then return "Not learned · reference browsing only" end
    local suffix=snapshot.cached and " · cached observation" or ""
    return "Skill "..tostring(snapshot.skill or "?").." / "..tostring(snapshot.maxSkill or "?")..suffix
end

local function materialPreview(plan,limit)
    if not plan then return "Guide estimate unavailable until skill is observed" end
    local rows={}
    for _,r in ipairs(plan.materials or {}) do
        local outside=r.bankKnown==true and r.bagsKnown==true and
            ("external ~"..tostring(r.externalNeededIfGuideEstimateHolds or "UNKNOWN")) or
            ("external UNKNOWN"..(r.externalUpperBoundIfBankUnknown and
                (" · if bank zero ≤~"..tostring(r.externalUpperBoundIfBankUnknown)) or ""))
        rows[#rows+1]=tostring(r.name or "Material").." ~"..
            tostring(r.guideEstimate or "UNKNOWN").." ("..outside..")"
        if #rows>=(limit or 2) then break end
    end
    if #rows==0 then return "No remaining documented 1-225 bands" end
    return table.concat(rows,"; ")
end
local function gatePreview(plan)
    local gate=plan and plan.gates and plan.gates[1]
    if plan and plan.professionKey=="COOKING" and plan.accessReferenceState=="ACCESS_EVIDENCE_UNQUALIFIED" then
        return "Cooking access references UNKNOWN ("..tostring(plan.accessReferenceReason or "SOURCE_UNAVAILABLE").."); verified recipe bands remain available"
    end
    if not gate then
        if plan and plan.professionKey=="COOKING" and plan.accessReferences and plan.skill>=225 then
            return "No upcoming training gate; Artisan Cooking quest #6610 is a historical public access reference (completion UNKNOWN)"
        end
        return "No documented upcoming training gate"
    end
    local lvl=gate.characterLevel and " · character level "..gate.characterLevel or ""
    if plan.professionKey=="COOKING" then
        if gate.kind=="VENDOR_BOOK" and gate.itemID==16072 then
            -- Both factions are listed explicitly; no destination handoff.
            return "Expert Cookbook #16072 (use at Cooking 125) · Shandrina #3955 Alliance / Wulan #12033 Horde · stock UNKNOWN"
        elseif gate.kind=="ARTISAN_QUEST" and gate.questID==6610 then
            return "Clamlette Surprise quest #6610 · Dirge #8125 · level 35 / Cooking 225 · Eggs 12, Clam Meat 10, Swiss 20 · completion UNKNOWN"
        end
    end
    return gate.name.." · skill "..gate.skill..lvl.." (availability unconfirmed)"
end
local function bandPreview(plan)
    if not plan then return "No skill-backed route available" end
    local s=plan.currentStep
    if not s then
        if plan.professionKey=="COOKING" and (plan.skill or 0)>=225 and plan.advancedCurrentStep then
            local r=plan.advancedCurrentStep
            local mats={}
            for _,m in ipairs(r.materials or {}) do
                mats[#mats+1]="#"..m.itemID.." x"..m.perCraft..
                    (m.bagsKnown and (" (bags "..tostring(m.bags)..")") or " (bags UNKNOWN)")
            end
            local live=(r.learnedState=="LEARNED" and " · LIVE learned" or
                r.learnedState=="NOT_LEARNED" and " · LIVE NOT learned" or " · learned UNKNOWN")
            local output=(r.liveYieldState=="OBSERVED_FIXED" and
                (" · LIVE output x"..tostring(r.liveOutputMin)) or
                r.liveYieldState=="OBSERVED_VARIABLE" and
                (" · LIVE output "..tostring(r.liveOutputMin).."-"..tostring(r.liveOutputMax)) or
                r.liveYieldState=="LIVE_SOURCE_OUTPUT_ID_CONFLICT" and
                " · OUTPUT CONFLICT" or "")
            return "225–300 advisory: "..r.recipe.." (#"..r.recipeID..
                ", public minimum "..r.guideMinimumSkill..") · per craft "..
                (#mats>0 and table.concat(mats,", ") or "UNKNOWN")..
                live..output.." · "..tostring(r.nextAction or "VERIFY")..
                "; crafts UNKNOWN; no auto travel"
        end
        if plan.professionKey=="FIRST_AID" and (plan.skill or 0)>=225 then
            if plan.advancedCurrentStep then
                local r=plan.advancedCurrentStep
                local parts={}
                for _,m in ipairs(r.materials or {}) do
                    parts[#parts+1]="#"..m.itemID.." x"..m.perCraft..
                        (m.bagsKnown and (" (bags "..tostring(m.bags)..")") or " (bags UNKNOWN)")
                end
                local live=(r.learnedState=="LEARNED" and " · LIVE learned" or
                    r.learnedState=="NOT_LEARNED" and " · LIVE NOT learned" or " · learned UNKNOWN")
                local output=(r.liveYieldState=="OBSERVED_FIXED" and
                    (" · LIVE output x"..tostring(r.liveOutputMin)) or
                    r.liveYieldState=="OBSERVED_VARIABLE" and
                    (" · LIVE output "..tostring(r.liveOutputMin).."-"..tostring(r.liveOutputMax)) or
                    r.liveYieldState=="LIVE_SOURCE_OUTPUT_ID_CONFLICT" and
                    " · OUTPUT CONFLICT" or "")
                return "225-300 advisory: "..r.recipe.." (spell #"..r.recipeID..
                    ", reference skill "..r.suggestedAtSkill.."-"..r.skillTarget..
                    ") · per craft: "..(#parts>0 and table.concat(parts,", ") or "UNKNOWN")..
                    live..output.." · "..r.nextAction.." · crafts UNKNOWN / no auto travel"
            end
            -- These exact spell references are qualified by SecondaryLevelingPlanner,
            -- not a complete leveling route or a receipt of learned/available recipes.
            local options={}
            for _,r in ipairs(plan.advancedReferences or {}) do
                if type(r)=="table" and type(r.recipeID)=="number" and
                    type(r.suggestedAtSkill)=="number" and
                    r.suggestedAtSkill<=(plan.skill or 0) and r.readOnly==true and
                    r.nativeDispatchAllowed==false then
                    options[#options+1]=r
                end
            end
            table.sort(options,function(a,b)
                return a.suggestedAtSkill>b.suggestedAtSkill or
                    (a.suggestedAtSkill==b.suggestedAtSkill and a.recipeID<b.recipeID)
            end)
            if #options>0 then
                local r=options[1]
                return "225-300 reference: "..tostring(r.recipe).." (spell #"..r.recipeID..
                    ", source skill "..r.suggestedAtSkill..") · verify learned / Artisan / materials; crafts UNKNOWN"
            end
            return "225-300: no skill-eligible qualified recipe reference; VERIFY learning and Artisan access"
        end
        return "Public guide ends at skill "..tostring(plan.coverageEnd)
    end
    local proof=plan.steps and plan.steps[1]
    local id=proof and proof.recipeID and (" · spell "..proof.recipeID) or ""
    local learn=plan.currentLearningReference
    local actor=learn and learn.vendorIdentity
    local actorID=actor and (" · public NPC #"..actor.npcID) or ""
    local teaching=learn and (" · recipe item #"..learn.teachingItemID..
        " · "..learn.sellerNameLead..actorID.." (stock/waypoint UNKNOWN)") or ""
    return s.recipe..id.." · skill "..s.skillMin.."-"..s.skillMax..
        " · ~"..s.estimatedCrafts.." full-band crafts"..teaching
end
-- Skill-aware, read-only browsing across every qualified 225-300 recipe.
-- Highest eligible documented minimum first; paging keeps ALL older tiers
-- accessible without ever converting a reference to learned/native authority.
function Page:AdvancedCookingPreview(plan,page)
    if not plan or plan.professionKey~="COOKING" or (plan.skill or 0)<225 then return nil,0,0 end
    local eligible={}
    for _,r in ipairs(plan.advancedReferences or {}) do
        if type(r)=="table" and type(r.guideMinimumSkill)=="number" and
            (plan.skill or 0)>=r.guideMinimumSkill then
            eligible[#eligible+1]=r
        end
    end
    table.sort(eligible,function(a,b)
        return a.guideMinimumSkill>b.guideMinimumSkill or
            (a.guideMinimumSkill==b.guideMinimumSkill and a.spellID<b.spellID)
    end)
    local pages=math.max(1,math.ceil(#eligible/2))
    page=math.max(1,math.min(pages,math.floor(tonumber(page) or 1)))
    if #eligible==0 then
        return "225–300 recipes: "..tostring(plan.advancedReferenceState or "UNKNOWN")..
            "; no qualified craft-count route",0,pages
    end
    local rows={}
    for i=(page-1)*2+1,math.min(#eligible,page*2) do
        local r=eligible[i]
        local material=r.reagents and r.reagents[1]
        local req=material and (" · reagent #"..material.itemID.." x"..material.quantity) or ""
        local yield=r.publicOutputQuantityState=="WOWHEAD_FOREVER_VISIBLE_BASE_OUTPUT_NOT_LIVE" and
            r.publicBaseOutputQuantity and (" · public base output x"..r.publicBaseOutputQuantity) or ""
        rows[#rows+1]=r.name.." (spell #"..r.spellID..", guide skill "..r.guideMinimumSkill..")"..req..yield
    end
    return "225–300 references "..page.."/"..pages.." ("..#eligible.." eligible / "..
        #(plan.advancedReferences or {}).." qualified; no craft-count route): "..
        table.concat(rows,"; "),#eligible,pages
end
function Page:ShiftAdvancedCookingPage(delta)
    local view=self.frame and self.frame.views and self.frame.views.COOKING
    if not view then return false,"COOKING_VIEW_UNAVAILABLE" end
    view.advancedPage=math.max(1,(view.advancedPage or 1)+(tonumber(delta) or 0))
    self:Refresh()
    return true
end

local function sourceBand(m)
    if m and m.secondaryPlan then return bandPreview(m.secondaryPlan) end
    return bandName(m and m.band)
end
local function createOverview(parent)
    local f=CreateFrame("Frame",nil,parent); f:SetAllPoints()
    f.cards={}
    local colWidth=math.floor((WIDTH-2*GAP)/3)
    for i,key in ipairs(ORDER) do
        local card=makeCard(f,key=="FIRST_AID" and "First Aid" or key:sub(1,1)..key:sub(2):lower(),(i-1)*(colWidth+GAP),colWidth,HEIGHT)
        card.skill=row(card,"CURRENT STATUS",-70,colWidth-44)
        card.progress=row(card,"LEVELING METHOD",-142,colWidth-44)
        card.current=row(card,"CURRENT PLAN",-214,colWidth-44)
        card.sources=row(card,"SOURCES",-306,colWidth-44)
        card.note=label(card,"",22,-415,colWidth-44,"GameFontHighlight","muted")
        card.action=JLP.UIWidgets:Button(card,"Open Guide",colWidth-48)
        card.action:SetHeight(34); card.action:SetPoint("BOTTOMLEFT",24,22)
        card.action:SetScript("OnClick",function() JLP.MainWindow:ShowSecondaryMode(key) end)
        f.cards[key]=card
    end
    return f
end

local addMaterialPager
local function createCooking(parent)
    local f=CreateFrame("Frame",nil,parent); f:SetAllPoints()
    local left=makeCard(f,"Cooking Progress & Recipes",0,666,HEIGHT)
    local right=makeCard(f,"Ingredients & Sources",680,398,HEIGHT)
    f.primaryCard=left;f.secondaryCard=right
    f.skill=row(left,"CURRENT SKILL",-70,622)
    f.route=row(left,"CURRENT PLAN",-146,622)
    f.coverage=row(left,"RECIPE COVERAGE",-236,622)
    f.note=label(left,"",22,-334,620,"GameFontHighlight","muted")
    f.advancedPrevious=JLP.UIWidgets:Button(left,"Previous recipes")
    f.advancedPrevious:SetPoint("BOTTOMLEFT",22,25)
    f.advancedPrevious:SetSize(140,27)
    f.advancedPrevious:SetScript("OnClick",function() Page:ShiftAdvancedCookingPage(-1) end)
    f.advancedNext=JLP.UIWidgets:Button(left,"Next recipes")
    f.advancedNext:SetPoint("BOTTOMLEFT",172,25)
    f.advancedNext:SetSize(140,27)
    f.advancedNext:SetScript("OnClick",function() Page:ShiftAdvancedCookingPage(1) end)
    f.ingredients=row(right,"INGREDIENT REQUIREMENTS",-72,350)
    f.sources=row(right,"ACQUISITION",-166,350)
    f.reference=row(right,"PUBLIC REFERENCE",-310,350)
    f.disclaimer=label(right,"Reference preview only. No automatic cooking or purchasing.",22,-436,350,"GameFontHighlightSmall","muted")
    f.activateCurrent=JLP.UIWidgets:Button(left,"Use Cooking Current Step")
    f.activateCurrent:SetPoint("BOTTOMLEFT",322,25);f.activateCurrent:SetSize(210,27)
    f.activateCurrent:SetScript("OnClick",function()local svc=model();if svc then svc:ActivateCurrentStep("COOKING")end;Page:Refresh()end)
    f.prepareStation=JLP.UIWidgets:Button(left,"Prepare station kit")
    f.prepareStation:SetPoint("BOTTOMLEFT",22,60);f.prepareStation:SetSize(190,27)
    f.prepareStation:SetScript("OnClick",function()local svc=model();if svc then svc:SetCookingStationMode("KIT")end;Page:Refresh()end)
    f.existingStation=JLP.UIWidgets:Button(left,"Use existing station")
    f.existingStation:SetPoint("BOTTOMLEFT",222,60);f.existingStation:SetSize(190,27)
    f.existingStation:SetScript("OnClick",function()local svc=model();if svc then svc:SetCookingStationMode("EXISTING")end;Page:Refresh()end)
    addMaterialPager(f,right,"COOKING")
    return f
end

-- Standalone read-only material-navigation receipt used by BOTH secondaries.
-- A change in skill/source/recipe estimate resets the old page, never persisting
-- a stale page against a newly qualified candidate plan.
function Page:SecondaryMaterialPage(view,key,plan,delta)
    if type(view)~="table" then return nil end
    local identity="UNAVAILABLE"
    if type(plan)=="table" then
        local parts={tostring(key),tostring(plan.professionKey),tostring(plan.skill),
            tostring(plan.sourceURL),tostring(plan.status),tostring(plan.coverageEnd),
            tostring(plan.currentStep and plan.currentStep.recipe),
            tostring(plan.currentStep and plan.currentStep.skillMin),
            tostring(plan.stepIdentity),tostring(self:MaterialOwnerSignature())}
        for _,material in ipairs(plan.materials or {}) do
            parts[#parts+1]=tostring(material.itemID)..":"..
                tostring(material.guideEstimate)..":"..
                tostring(material.externalNeededIfGuideEstimateHolds)..":"..
                tostring(material.sourceURL)..":"..tostring(material.bankKnown)..":"..
                tostring(material.bagsKnown)..":"..tostring(material.materialDecisionStatus)..":"..
                tostring(material.externalUpperBoundIfBankUnknown)..":"..
                tostring(material.bags)..":"..tostring(material.bank)..":"..
                tostring(material.bankStale)..":"..tostring(material.snapshotStale)..":"..
                tostring(material.source)
            for _,band in ipairs(material.recipeBands or {}) do
                parts[#parts+1]="recipe:"..tostring(band.recipe)..":"..
                    tostring(band.recipeID)..":"..tostring(band.skillMin)..":"..
                    tostring(band.skillMax)..":"..tostring(band.sourceURL)
            end
        end
        identity=table.concat(parts,"|")
    end
    if view.materialIdentity~=identity then
        view.materialIdentity=identity;view.materialPage=1
        view.materialDetailsOpen=false -- never show a detail sheet from a prior recipe
        if view.materialSourceSheet and view.materialSourceSheet.Reset then
            view.materialSourceSheet:Reset()
        end
    end
    view.materialPage=math.max(1,(view.materialPage or 1)+(tonumber(delta) or 0))
    local planner=JLP:GetModule("SecondaryLevelingPlanner")
    local receipt=planner and planner.MaterialPage and
        planner:MaterialPage(plan,view.materialPage,1) or nil
    view.materialPage=receipt and receipt.page or 1
    view.materialReceipt=receipt -- view-local advisory receipt; never persisted
    return receipt
end
function Page:CaptureMaterialReference(reference,view)
    local receipt=view and view.materialReceipt
    local sheet=view and view.materialSourceSheet
    local row=receipt and receipt.rows and receipt.rows[1]
    if not (view and receipt and row and sheet and sheet.currentRow==row and
        sheet.frame and sheet.frame.IsShown and sheet.frame:IsShown() and
        self.frame and self.frame.views and self.frame.views[self:GetMode()]==view) then
        return nil,"REFERENCE_NOT_VISIBLE"
    end
    local qualified=JLP.UIWidgets:QualifiedMaterialReference(row)
    if not qualified or qualified.itemID~=reference.itemID or
        qualified.required~=reference.required or qualified.source~=reference.source or
        qualified.bankKnown~=reference.bankKnown then return nil,"SOURCE_CHANGED" end
    local layout=JLP.UILayout
    return {page="Secondaries",mode=self:GetMode(),materialID=qualified.itemID,
        identity=view.materialIdentity,materialPage=receipt.page,view=view,
        required=qualified.required,source=qualified.source,bankKnown=qualified.bankKnown,
        ownerSignature=self:MaterialOwnerSignature(),stepIdentity=view.selectedStepIdentity,
        sheetScroll=layout and layout.CaptureScrollPosition and
            layout:CaptureScrollPosition(sheet.viewport) or 0,
        readOnly=true,nativeDispatchAllowed=false}
end
function Page:ClearMaterialReference()
    if not self.frame or not self.frame.views then return end
    for _,key in ipairs({"COOKING","FIRST_AID"}) do
        local view=self.frame.views[key]
        if view then
            view.materialDetailsOpen=false
            view.materialPage=1
            view.materialReceipt=nil
            if view.materialSourceSheet and view.materialSourceSheet.Reset then
                view.materialSourceSheet:Reset() end
        end
    end
end
function Page:RestoreMaterialReference(capture)
    if type(capture)~="table" or capture.mode~=self:GetMode() or
        capture.readOnly~=true or capture.nativeDispatchAllowed~=false or
        capture.ownerSignature~=self:MaterialOwnerSignature() or
        capture.ownerSignature=="OWNER_UNKNOWN" then return false,"OWNER_UNKNOWN" end
    local view=self.frame and self.frame.views and self.frame.views[capture.mode]
    if not view or view~=capture.view then return false,"ORIGIN_VIEW_CHANGED" end
    self:Refresh() -- compute fresh source identity and qualified rows
    if view.materialIdentity~=capture.identity or
        view.selectedStepIdentity~=capture.stepIdentity then return false,"RECIPE_OR_STOCK_CHANGED" end
    view.materialPage=capture.materialPage
    self:Refresh()
    local receipt=view.materialReceipt
    local row=receipt and receipt.page==capture.materialPage and
        receipt.rows and receipt.rows[1]
    local qualified=row and JLP.UIWidgets:QualifiedMaterialReference(row)
    if not qualified or qualified.itemID~=capture.materialID or
        qualified.required~=capture.required or qualified.source~=capture.source or
        qualified.bankKnown~=capture.bankKnown then return false,"MATERIAL_EVIDENCE_CHANGED" end
    local sheet=view.materialSourceSheet
    if not sheet then return false,"SOURCE_SHEET_UNAVAILABLE" end
    view.materialDetailsOpen=true
    if sheet.PositionOutside then sheet.PositionOutside() end
    sheet:SetRow(row,view.selectedStepMaterials,capture.materialPage);sheet.frame:Show()
    if JLP.UILayout and JLP.UILayout.RestoreScrollPosition then
        JLP.UILayout:RestoreScrollPosition(sheet.viewport,capture.sheetScroll) end
    return true
end
function Page:TurnSecondaryMaterial(key,delta)
    local v=self.frame and self.frame.views and self.frame.views[key]
    if not v then return false,"VIEW_UNAVAILABLE" end
    -- Fail closed if the button is disabled, evidence is absent, or an
    -- unexpected caller requests a non-adjacent page. The owner refresh will
    -- still validate the plan identity on the new page.
    if delta~=1 and delta~=-1 then return false,"PAGE_DIRECTION_INVALID" end
    local receipt=v.materialReceipt
    if type(receipt)~="table" or receipt.nativeDispatchAllowed~=false or
        receipt.total==0 then return false,"MATERIALS_UNAVAILABLE" end
    if (delta==1 and receipt.canNext~=true) or
        (delta==-1 and receipt.canPrevious~=true) then return false,"PAGE_BOUNDARY" end
    v.materialPage=math.max(1,(receipt.page or 1)+delta)
    self:Refresh()
    return true
end
-- Explicit step choice is transient view state; a newly-qualified plan is
-- always regenerated by SecondaryWorkspace before the next receipt is opened.
function Page:SelectSecondaryStep(key,delta)
    if (key~="COOKING" and key~="FIRST_AID") or
       (delta~=1 and delta~=-1) then return false,"STEP_REQUEST_INVALID" end
    local view=self.frame and self.frame.views and self.frame.views[key]
    if not view or self:GetMode()~=key or not view.selectedStepCount then
        return false,"STEP_UNAVAILABLE" end
    local nextIndex=(view.stepOrdinal or 1)+delta
    if nextIndex<1 or nextIndex>view.selectedStepCount then return false,"STEP_BOUNDARY" end
    view.stepOrdinal=nextIndex;view.materialPage=1;view.materialDetailsOpen=false
    view.materialReceipt=nil
    view.materialIdentity=nil -- requalify the step and its material positions
    if view.materialSourceSheet and view.materialSourceSheet.Reset then
        view.materialSourceSheet:Reset() end
    self:Refresh()
    return true
end
addMaterialPager=function(view,card,key)
    local metrics=JLP.UITheme and JLP.UITheme.secondaryMaterial or {}
    local inset=metrics.pagerInset or 22
    local top=metrics.pagerTop or 532
    local width=metrics.pagerButtonWidth or 90
    local height=metrics.pagerButtonHeight or 28
    -- Reuse the existing left card's unused lower area for step selection.
    -- Separate from the right card's per-material pager and SourceSheet.
    local stepHost=view.primaryCard or card
    view.stepPrevious=JLP.UIWidgets:Button(stepHost,"Previous step",126)
    view.stepNext=JLP.UIWidgets:Button(stepHost,"Next step",126)
    view.stepPrevious:SetSize(126,26);view.stepNext:SetSize(126,26)
    view.stepPrevious:SetPoint("TOPLEFT",stepHost,"TOPLEFT",22,-490)
    view.stepNext:SetPoint("TOPLEFT",stepHost,"TOPLEFT",157,-490)
    view.stepStatus=label(stepHost,"Choose a sourced recipe step",22,-528,580,
        "GameFontHighlightSmall","muted")
    view.stepPrevious:SetScript("OnClick",function()Page:SelectSecondaryStep(key,-1)end)
    view.stepNext:SetScript("OnClick",function()Page:SelectSecondaryStep(key,1)end)
    view.materialPrevious=JLP.UIWidgets:Button(card,"Previous",width)
    view.materialPrevious:SetSize(width,height)
    view.materialPrevious:SetPoint("TOPLEFT",inset,-top)
    view.materialNext=JLP.UIWidgets:Button(card,"Next",width)
    view.materialNext:SetSize(width,height)
    view.materialNext:SetPoint("TOPRIGHT",-inset,-top)
    view.materialPosition=label(card,"No qualified materials",inset,
        -(metrics.pagerLabelTop or 570),metrics.cardValueWidth or 350,"GameFontHighlightSmall","muted")
    -- Dedicated owner/status decision: never infer bank zero from nil stock.
    view.materialDecision=label(card,"No qualified stock decision",inset,
        -(metrics.pagerLabelTop or 570)-31,metrics.cardValueWidth or 350,
        "GameFontHighlightSmall","muted")
    -- Read-only list for the selected step, above the existing detail-sheet
    -- and per-reagent pager. It does not capture focus or create new buttons.
    view.materialDecisionList=label(stepHost,"",22,-555,580,
        "GameFontHighlightSmall","muted")
    if view.materialDecisionList.SetWordWrap then view.materialDecisionList:SetWordWrap(true) end
    if view.materialDecisionList.SetHeight then view.materialDecisionList:SetHeight(42) end
    view.materialDetails=JLP.UIWidgets:Button(card,"Source / recipe details",205)
    view.materialDetails:SetSize(205,26)
    view.materialDetails:SetPoint("TOPLEFT",inset,-(metrics.pagerTop or 532)+50)
    -- Standalone, sidecar read-only source sheet. It is UIParent-backed so
    -- no Secondaries card clips it or paints text through it. Logical ownership
    -- remains with this material view and its qualified source receipt.
    view.materialSourceSheet=type(JLP.UIWidgets.AdvisorySourceSheet)=="function" and
        JLP.UIWidgets:AdvisorySourceSheet(UIParent,404,490) or nil
    if view.materialSourceSheet then
        local sheet=view.materialSourceSheet.frame
        sheet:SetFrameStrata("DIALOG")
        local mainFrame=JLP.MainWindow and JLP.MainWindow.frame
        sheet:SetFrameLevel(math.max(1,(mainFrame and mainFrame.GetFrameLevel and mainFrame:GetFrameLevel() or 100)+24))
        if sheet.SetClampedToScreen then sheet:SetClampedToScreen(true) end
        view.materialSourceSheet.outsideHost=true
        view.materialSourceSheet.ownerKey=key
        -- The owner toolbar's Source / recipe details button is the toggle.
        -- Keep closure via that button, navigation, page changes and Escape;
        -- remove only the redundant Close button in the external sidecar.
        if view.materialSourceSheet.SetCloseButtonVisible then
            view.materialSourceSheet:SetCloseButtonVisible(false)
        end
        local function positionSideSheet()
            local main=JLP.MainWindow and JLP.MainWindow.frame
            if not main then return end
            -- Keep the exterior panel aligned with the main addon UI scale.
            if UIParent and UIParent.GetEffectiveScale and main.GetEffectiveScale then
                local parentScale=tonumber(UIParent:GetEffectiveScale()) or 1
                local mainScale=tonumber(main:GetEffectiveScale()) or 1
                if parentScale>0 and mainScale>0 then
                    sheet:SetScale(mainScale/parentScale)
                end
            end
            local screenLeft=UIParent and UIParent.GetLeft and UIParent:GetLeft() or 0
            local screenRight=UIParent and UIParent.GetRight and UIParent:GetRight() or 0
            local mainLeft=main.GetLeft and main:GetLeft() or 0
            local mainRight=main.GetRight and main:GetRight() or 0
            local parentScale=UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
            local sheetScale=sheet.GetEffectiveScale and sheet:GetEffectiveScale() or 1
            local effectiveWidth=(sheet.GetWidth and sheet:GetWidth() or 404)*sheetScale/math.max(0.01,parentScale)
            sheet:ClearAllPoints()
            if screenRight-mainRight>=effectiveWidth+20 then
                sheet:SetPoint("TOPLEFT",main,"TOPRIGHT",12,-105)
                sheet.__jlpPlacement="EXTERIOR_RIGHT"
            elseif mainLeft-screenLeft>=effectiveWidth+20 then
                sheet:SetPoint("TOPRIGHT",main,"TOPLEFT",-12,-105)
                sheet.__jlpPlacement="EXTERIOR_LEFT"
            else
                sheet:SetPoint("CENTER",UIParent,"CENTER",0,0)
                sheet.__jlpPlacement="MODAL_FALLBACK"
            end
            sheet:SetFrameLevel(math.max(1,(main.GetFrameLevel and main:GetFrameLevel() or 100)+24))
        end
        view.materialSourceSheet.PositionOutside=positionSideSheet
        positionSideSheet()
        if JLP.UIWindowRegistry then
            JLP.UIWindowRegistry:Register("SecondariesSource_"..tostring(key),sheet,"Secondaries")
        end
        if view.materialSourceSheet.SetNavigation then
            view.materialSourceSheet:SetNavigation(function(target,reference)
                if not view.materialReceipt or not view.materialIdentity then return false end
                local main=JLP.MainWindow
                if not main or not main.BeginMaterialReference then
                    return false,"NAVIGATION_UNAVAILABLE"
                end
                return main:BeginMaterialReference(target,"Secondaries",reference,view)
            end)
        end
        view.materialSourceSheet.close:SetScript("OnClick",function()
            view.materialDetailsOpen=false
            if view.materialSourceSheet.Reset then view.materialSourceSheet:Reset()
            else view.materialSourceSheet.frame:Hide() end
        end)
    end
    view.materialDetails:SetScript("OnClick",function()
        local receipt=view.materialReceipt
        local row=receipt and receipt.rows and receipt.rows[1]
        if not row or not view.materialSourceSheet then return end
        view.materialDetailsOpen=not view.materialDetailsOpen
        if view.materialDetailsOpen then
            for _,other in ipairs({"COOKING","FIRST_AID"}) do
                local otherView=Page.frame and Page.frame.views and Page.frame.views[other]
                if otherView and otherView~=view and otherView.materialSourceSheet then
                    otherView.materialDetailsOpen=false
                    otherView.materialSourceSheet:Reset()
                end
            end
            if view.materialSourceSheet.PositionOutside then view.materialSourceSheet.PositionOutside() end
            view.materialSourceSheet:SetRow(row,view.selectedStepMaterials,receipt and receipt.page)
            view.materialSourceSheet.frame:Show()
        else
            view.materialSourceSheet.frame:Hide()
        end
    end)
    view.materialPrevious:SetScript("OnClick",function() Page:TurnSecondaryMaterial(key,-1) end)
    view.materialNext:SetScript("OnClick",function() Page:TurnSecondaryMaterial(key,1) end)
end
local function applyMaterialPage(view,key,plan)
    local planner=JLP:GetModule("SecondaryLevelingPlanner")
    local stepPlan
    if (key=="FIRST_AID"or key=="COOKING")and planner and planner.BuildOperationalStepPlan and plan and plan.recommendedCurrentStep then
        stepPlan=planner:BuildOperationalStepPlan(plan)
    elseif planner and planner.BuildStepPlan and plan and # (plan.steps or {})>0 then
        if view.stepPlanOrigin~=plan.sourceURL or view.stepPlanSkill~=plan.skill or
           view.stepPlanProfession~=key then view.stepOrdinal=1 end
        view.stepOrdinal=math.max(1,math.min(view.stepOrdinal or 1,#plan.steps))
        stepPlan=planner:BuildStepPlan(plan,view.stepOrdinal)
        view.stepPlanOrigin=plan.sourceURL;view.stepPlanSkill=plan.skill
        view.stepPlanProfession=key
    end
    view.selectedStepIdentity=stepPlan and stepPlan.stepIdentity or nil
    view.selectedStepMaterials=stepPlan and stepPlan.materials or nil
    view.selectedStepCount=stepPlan and stepPlan.stepCount or 0
    if view.stepStatus then
        if stepPlan then
            view.stepStatus:SetText("Step "..stepPlan.stepOrdinal.."/"..stepPlan.stepCount..
                " · spell "..stepPlan.recipeID.." · yield "..tostring(stepPlan.outputQuantity or "UNKNOWN")..
                " per craft · ~"..stepPlan.expectedCrafts.." estimated crafts")
        else view.stepStatus:SetText("No qualified recipe step · advisory only") end
    end
    for _,entry in ipairs({{view.stepPrevious,stepPlan and stepPlan.stepOrdinal>1},
        {view.stepNext,stepPlan and stepPlan.stepOrdinal<stepPlan.stepCount}}) do
        if entry[1] then
            if entry[1].SetEnabled then entry[1]:SetEnabled(entry[2]==true) end
            if entry[1].SetAlpha then entry[1]:SetAlpha(entry[2] and 1 or 0.45) end
        end
    end
    local receipt=Page:SecondaryMaterialPage(view,key,stepPlan or nil,0)
    local widgets=JLP.UIWidgets
    local row=receipt and receipt.rows and receipt.rows[1]
    if view.materialDecisionList and view.materialDecisionList.SetText then
        view.materialDecisionList:SetText(stepPlan and
            ("Reagents "..tostring(receipt and receipt.page or 1).."/"..
             tostring(#(stepPlan.materials or {}))..
             " · use pager for manual Bank/AH decision") or "SOURCE_UNAVAILABLE")
    end
    if view.materialDecision and view.materialDecision.SetText then
        local status=row and row.materialDecisionStatus or "SOURCE_UNAVAILABLE"
        local decision=row and widgets and widgets.NormalizeMaterialDecision and
            widgets:NormalizeMaterialDecision(row)
        local bankState=not decision and "UNAVAILABLE" or decision.bank=="STALE" and "STALE" or
            decision.bank=="BANK_UNKNOWN" and "BANK_UNKNOWN" or
            decision.bank=="KNOWN_ZERO" and "KNOWN_ZERO" or "BANK_POSITIVE"
        local bagsState=decision and decision.bags or "BAGS_UNKNOWN"
        view.materialDecision:SetText(tostring(status).." · "..bankState.." · "..bagsState..
            " · manual Bank / AH only")
    end
    if row then
        local bags=tonumber(row.bags) or 0
        local bank=row.bankKnown and tostring(row.bank or 0) or "UNKNOWN"
        local external=tostring(row.externalNeededIfGuideEstimateHolds or "unknown")
        local value,source,recipes=widgets and widgets.MaterialAdvisoryLines and
            widgets:MaterialAdvisoryLines(row)
        setRow(key=="COOKING" and view.ingredients or view.resources,value or
            tostring(row.name or "Source unavailable"))
        setRow(view.sources,(Page.materialReferenceWarning and
            (Page.materialReferenceWarning.." ") or "")..(source or "Acquisition source unavailable · manual only")..
            "\n"..(recipes or "Recipe provenance unavailable").." · read-only")
        if stepPlan then
            local per=tostring(row.perCraft or "?")
            setRow(key=="COOKING" and view.ingredients or view.resources,
                tostring(row.name).." x"..per.." per craft (spell "..stepPlan.recipeID..
                ") · ~"..stepPlan.expectedCrafts.." crafts · gross "..
                tostring(row.guideEstimate).." · missing estimate "..
                tostring(row.externalNeededIfGuideEstimateHolds or "UNKNOWN")..
                " · bank "..(row.bankKnown and tostring(row.bank) or "UNKNOWN"))
        end
        if widgets and widgets.AdvisoryMaterialTooltip then
            widgets:AdvisoryMaterialTooltip((key=="COOKING" and view.ingredients or view.resources).value,row)
            widgets:AdvisoryMaterialTooltip(view.sources.value,row)
        end
    else
        setRow(key=="COOKING" and view.ingredients or view.resources,
            plan and "No remaining source-qualified 1-225 materials" or
                "Materials unavailable; learn the skill or review the public guide")
        setRow(view.sources,"Reference unavailable · inspect sources manually")
        if widgets and widgets.AdvisoryMaterialTooltip then
            widgets:AdvisoryMaterialTooltip((key=="COOKING" and view.ingredients or view.resources).value,nil)
            widgets:AdvisoryMaterialTooltip(view.sources.value,nil)
        end
    end
    if view.materialSourceSheet then
        -- Source evidence changes invalidate previously displayed details.
        if not row then
            view.materialDetailsOpen=false
            if view.materialSourceSheet.Reset then view.materialSourceSheet:Reset() end
        end
        view.materialSourceSheet.frame:SetShown(view.materialDetailsOpen==true and row~=nil)
        if row and view.materialDetailsOpen then
            local nextIdentity=widgets and widgets.MaterialReferenceIdentity and
                widgets:MaterialReferenceIdentity(row)
            if not nextIdentity or nextIdentity~=view.materialSourceSheet.currentIdentity then
                view.materialSourceSheet:SetRow(row,view.selectedStepMaterials,receipt and receipt.page)
            else
                -- Same qualified evidence, new ephemeral row allocation:
                -- keep the scroll position and rebind the current row owner.
                view.materialSourceSheet.currentRow=row
                view.materialSourceSheet.currentReference=widgets:QualifiedMaterialReference(row)
            end
        end
    end
    if view.materialDetails then
        local available=row~=nil
        if view.materialDetails.SetEnabled then view.materialDetails:SetEnabled(available) end
        if view.materialDetails.SetAlpha then view.materialDetails:SetAlpha(available and 1 or 0.45) end
        if widgets and widgets.AdvisoryMaterialTooltip then
            widgets:AdvisoryMaterialTooltip(view.materialDetails,row)
        end
    end
    if widgets and widgets.ApplyAdvisoryPager then
        widgets:ApplyAdvisoryPager(view.materialPrevious,view.materialNext,
            view.materialPosition,receipt,receipt and receipt.total>0 and
            ("Source-qualified material "..tostring(receipt.page).." / "..tostring(receipt.total)..
                " · advisory only") or "No qualified materials · read-only")
    end
    return receipt
end

local function suggestFishingZone()
    local api=JLP:GetModule("ProfessionAPI")
    local p=api and api:Get("FISHING")
    if not p or p.key~="FISHING" or p.cached or type(p.skill)~="number" then
        return nil,"FISHING_NOT_LEARNED"
    end
    local map=JLP:GetModule("ForeverFishingMapCanvas")
    local current=map and map:GetCurrentZone()
    local browser=JLP:GetModule("ForeverFishingZoneBrowser")
    local zones=browser and current and browser:Discover(current) or {}
    local available={}
    for _,entry in ipairs(zones) do available[entry.mapID]=true end
    local state=JLP:GetModule("GatheringSharedMapState")
    local shared=state and state:GetSnapshot()
    local intel=JLP:GetModule("FishingAreaIntelligence")
    if not shared or not intel then return nil,"FISHING_AREA_SERVICE_UNAVAILABLE" end
    local ranking,reason=intel:RecommendZones(shared.fishingAreaFilter or "ALL",
        shared.fishingSelectedItemID,nil,function(id) return available[id]==true end)
    local first=ranking and ranking[1]
    if not first then return nil,reason or "NO_CLIENT_BROWSABLE_FISHING_AREA" end
    local ok,why=state:SelectMap(first.mapID)
    if not ok then return nil,why end
    return first
end

local function createFishing(parent)
    local f=CreateFrame("Frame",nil,parent); f:SetAllPoints()
    -- Exact Bank Storage left/right geometry. Mini-zone map is an honest
    -- reserved surface, not a simulated or ungrounded map.
    local left=makeCard(f,"Fishing Areas & Gathering Layers",0,800,HEIGHT)
    local right=makeCard(f,"Current Plan / Sources",814,264,HEIGHT)
    f.primaryCard=left;f.secondaryCard=right
    f.mapContainer=CreateFrame("Frame",nil,left)
    f.mapContainer:SetPoint("TOPLEFT",22,-66)
    f.mapContainer:SetPoint("BOTTOMRIGHT",-22,22)
    local fill=f.mapContainer:CreateTexture(nil,"BACKGROUND")
    fill:SetAllPoints(); fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetVertexColor(0.01,0.035,0.055,0.65)
    JLP.UIWidgets:Border(f.mapContainer,"border",1)
    -- Zone metadata and actions are independent nested containers; the map
    -- canvas begins below both rows and cannot swallow their mouse hitboxes.
    f.mapHeaderInfo=CreateFrame("Frame",nil,f.mapContainer)
    f.mapHeaderInfo:SetPoint("TOPLEFT",f.mapContainer,"TOPLEFT",22,-24)
    f.mapHeaderInfo:SetPoint("TOPRIGHT",f.mapContainer,"TOPRIGHT",-22,-24)
    f.mapHeaderInfo:SetHeight(60)
    f.mapToolbar=CreateFrame("Frame",nil,f.mapContainer)
    f.mapToolbar:SetPoint("TOPLEFT",f.mapContainer,"TOPLEFT",22,-86)
    f.mapToolbar:SetPoint("TOPRIGHT",f.mapContainer,"TOPRIGHT",-22,-86)
    f.mapToolbar:SetHeight(64)
    local function positionMapHeaderLabel(widget,top,width)
        widget:SetParent(f.mapHeaderInfo)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT",f.mapHeaderInfo,"TOPLEFT",0,-top)
        widget:SetWidth(width or 690)
        if widget.SetWordWrap then widget:SetWordWrap(false) end
        if widget.SetMaxLines then widget:SetMaxLines(1) end
    end
    -- One column-flow for both button rows. Source handlers, enabled states
    -- and native routes are untouched; only owner-relative geometry changes.
    local function positionMapToolbarButton(widget,x,y,width)
        widget:SetParent(f.mapToolbar)
        widget:ClearAllPoints()
        widget:SetSize(width,28)
        widget:SetPoint("TOPLEFT",f.mapToolbar,"TOPLEFT",x,-y)
    end
    f.mapHeaderPlace=positionMapHeaderLabel
    f.mapActionPlace=positionMapToolbarButton
    f.mapStatus=label(f.mapContainer,"Mini zone map reserved for future verified map data",22,-32,690,"GameFontHighlightLarge","muted")
    -- The map container is 800-44=756 in native card UI units; reserve
    -- 22 units at both ends. Never use guessed browser/font coordinates.
    local feedbackW=800-44-44
    f.mapCaption=label(f.mapContainer,"No active route",22,-74,feedbackW,"GameFontHighlight","muted")
    f.routeHint=label(f.mapContainer,"Choose resources, then Generate Route",22,-57,feedbackW,"GameFontHighlightSmall","muted")
    if f.mapCaption.SetWordWrap then f.mapCaption:SetWordWrap(false) end
    if f.routeHint.SetWordWrap then f.routeHint:SetWordWrap(false) end
    positionMapHeaderLabel(f.mapStatus,0,feedbackW)
    positionMapHeaderLabel(f.routeHint,26,feedbackW)
    positionMapHeaderLabel(f.mapCaption,44,feedbackW)
    f.mapSkill=label(f.mapContainer,"",22,-104,502,"GameFontHighlight","cyan")
    f.fishingAreas=JLP.UIWidgets:Button(f.mapContainer,"Fishing areas: On",170)
    f.fishingAreas:SetHeight(26);f.fishingAreas:SetPoint("TOPLEFT",536,-91)
    f.fishingAreas:SetScript("OnClick",function()
        local state=JLP:GetModule("GatheringSharedMapState")
        local current=state and state:GetSnapshot()
        if current and state:SetFishingAreas(not current.showFishingAreas) then
            if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
            if JLP.StandaloneGatheringMap and JLP.StandaloneGatheringMap:IsShown() then JLP.StandaloneGatheringMap:Refresh() end
        end
    end)
    f.includeGathering=false -- display-only: shared Herbalism/Mining selections stay untouched
    f.gatheringOverlay=JLP.UIWidgets:Button(f.mapContainer,"Herb/Ore overlays: Hidden",207)
    f.gatheringOverlay:SetHeight(26)
    f.gatheringOverlay:SetPoint("TOPLEFT",493,-115)
    f.gatheringOverlay:SetScript("OnClick",function()
        f.includeGathering=not f.includeGathering
        f.gatheringOverlay:SetText(f.includeGathering and "Herb/Ore overlays: Visible" or "Herb/Ore overlays: Hidden")
        f.forceMapRefresh=true
        if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
    end)
    f.mapZone=label(f.mapContainer,"",22,-168,690,"GameFontHighlight","muted")
    f.mapZone:Hide();f.mapSkill:Hide() -- detailed requirement remains in Current Plan/Sources
    -- Source-backed zone browser. All zone IDs are discovered from the client.
    f.zonePrevious=JLP.UIWidgets:Button(f.mapContainer,"Previous Zone",144)
    positionMapToolbarButton(f.zonePrevious,0,0,144)
    f.zoneNext=JLP.UIWidgets:Button(f.mapContainer,"Next Zone",144)
    positionMapToolbarButton(f.zoneNext,155,0,144)
    f.zoneCurrent=JLP.UIWidgets:Button(f.mapContainer,"Current Zone",144)
    positionMapToolbarButton(f.zoneCurrent,310,0,144)
    f.openStandalone=JLP.UIWidgets:Button(f.mapContainer,"Open Full Map",207)
    positionMapToolbarButton(f.openStandalone,465,0,207)
    f.openStandalone:SetScript("OnClick",function()
        local coordinator=JLP:GetModule("GatheringWindowCoordinator")
        if coordinator then coordinator:Open("SECONDARIES","FISHING")
        elseif JLP.StandaloneGatheringMap then JLP.StandaloneGatheringMap:Show() end
    end)
    local function chooseZone(direction)
        local map=JLP:GetModule("ForeverFishingMapCanvas")
        local browser=JLP:GetModule("ForeverFishingZoneBrowser")
        local context=map and map:GetCurrentZone()
        local ok=context and browser and browser:Step(context,direction)
        if ok then
            f.suitabilityFeedback=nil
            f.forceMapRefresh=true
            if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
        end
    end
    f.zonePrevious:SetScript("OnClick",function() chooseZone(-1) end)
    f.zoneNext:SetScript("OnClick",function() chooseZone(1) end)
    f.zoneCurrent:SetScript("OnClick",function()
        local state=JLP:GetModule("GatheringSharedMapState")
        if state and state:SelectMap(nil) then
            f.suitabilityFeedback=nil
            f.forceMapRefresh=true
            if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
        end
    end)
    f.retryMap=JLP.UIWidgets:Button(f.mapContainer,"Reload Map",207)
    -- A separate second toolbar row; the two controls previously overlapped
    -- 12 logical units while Map Options started at -127.
    positionMapToolbarButton(f.retryMap,554,36,118)
    f.retryMap:SetScript("OnClick",function()
        -- A stale/disabled button or programmatic click without a rendered
        -- map cannot create an unscoped forced C_Map fetch.
        if type(f.lastMapID)~="number" then
            if f.mapCaption then f.mapCaption:SetText("Choose Zone · no map available to reload") end
            return
        end
        -- One scoped C_Map fetch on the next valid embedded refresh.
        -- Never mutates the shared zone or generates a gathering route.
        f.manualArtRetryMapID=f.lastMapID
        f.forceMapRefresh=true
        if JLP.UIPages and JLP.UIPages.Secondaries then
            JLP.UIPages.Secondaries:Refresh()
        end
    end)
    f.mapArt=CreateFrame("Frame",nil,f.mapContainer)
    f.mapArt:SetPoint("TOPLEFT",f.mapContainer,"TOPLEFT",18,-169)
    f.mapArt:SetPoint("BOTTOMRIGHT",f.mapContainer,"BOTTOMRIGHT",-18,18)
    -- Refit tile art when UI scale/layout changes, without re-reading the map API.
    f.mapArt:SetScript("OnSizeChanged",function(canvas)
        local map=JLP:GetModule("ForeverFishingMapCanvas")
        if map and f.lastArt then
            local presentation=JLP:GetModule("GatheringMapViewService")
            local ok,reason=true,nil
            if presentation then ok,reason=presentation:RenderArt(canvas,f.lastArt,true)
            else
                local passed,result=pcall(function() return map:Render(canvas,f.lastArt) end)
                ok=passed and result==true
            end
            if ok then
                local overlay=JLP:GetModule("GatheringMapOverlay")
                local painted=pcall(function()
                    if overlay and f.lastGatheringSnapshot then
                        local report=overlay:Render(canvas,f.lastArt,f.lastGatheringSnapshot,map,f.lastRouteSnapshot,f.lastSpatialSnapshot)
                        if type(report)=="table" and report.status=="MAP_MISMATCH" then error("MAP_MISMATCH") end
                    end
                    if f.lastPlayerPosition then map:PlacePlayerMarker(canvas,f.lastArt,f.lastPlayerPosition)
                    else map:HidePlayerMarker(canvas) end
                end)
                ok=painted
            end
            if not ok then
                f.mapReady=false;f.lastArt=nil
                canvas.__jlpTileArtKey=nil;canvas.__jlpTileViewportKey=nil
                pcall(map.Clear,map,canvas)
                local overlay=JLP:GetModule("GatheringMapOverlay")
                if overlay and type(overlay.Clear)=="function" then pcall(overlay.Clear,overlay,canvas) end
                if f.mapCaption then f.mapCaption:SetText("Map resize failed · Retry Map") end
                if f.routeHint then f.routeHint:SetText("Partial art was cleared; reload map tiles") end
                if f.mapFallback then f.mapFallback:Show() end
                if f.retryMap then f.retryMap:SetText("Retry Map") end
            end
        end
    end)
    -- Smart and Custom use one route selector, but independent strategies.
    f.routeMode=JLP.UIWidgets:Button(f.mapContainer,"Mode: Custom Loop",222)
    f.routeMode:SetHeight(26);f.routeMode:SetPoint("TOPLEFT",22,-215)
    f.smartFocus=JLP.UIWidgets:Button(f.mapContainer,"Focus: Balanced",208)
    f.smartFocus:SetHeight(26);f.smartFocus:SetPoint("TOPLEFT",257,-215)
    f.suggestZone=JLP.UIWidgets:Button(f.mapContainer,"Recommend Zone",216)
    f.suggestZone:SetHeight(26);f.suggestZone:SetPoint("TOPLEFT",480,-215)
    f.suggestZone:SetScript("OnClick",function()
        local shared=JLP:GetModule("GatheringSharedMapState")
        local state=shared and shared:GetSnapshot()
        local map=JLP:GetModule("ForeverFishingMapCanvas")
        local current=map and map:GetCurrentZone()
        local engine=JLP:GetModule("GatheringZoneSuitability")
        if not state or not current or not engine then return end
        if engine:GetRecommendationStatus()=="GENERATING" then
            engine:CancelRecommendation("CANCELLED_BY_PLAYER")
            f.suitabilityFeedback="Zone recommendation cancelled"
            f.suggestZone:SetText("Recommend Zone")
        elseif state.mode~="SMART_PROFESSION" then
            f.suitabilityFeedback="Enable Smart mode for a zone suggestion"
        else
            local ok,reason=engine:StartRecommendation(current,state.focus,function(proposed,why)
                if proposed then
                    f.suitabilityFeedback="Suggested: "..tostring(proposed.name).." ("..proposed.score.."/100, "..proposed.confidence.." confidence)"
                    shared:SelectMap(proposed.mapID)
                else
                    f.suitabilityFeedback="No zone suggestion: "..tostring(why)
                end
                if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
            end)
            f.suitabilityFeedback=ok and "Evaluating zones (cancellable)…" or "No zone suggestion: "..tostring(reason)
            if ok then f.suggestZone:SetText("Cancel Scan") end
        end
        if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
    end)
    f.routeMode:SetScript("OnClick",function()
        local state=JLP:GetModule("GatheringSharedMapState")
        local s=state and state:GetSnapshot()
        if s and state:SetMode(s.mode=="CUSTOM_LOOP" and "SMART_PROFESSION" or "CUSTOM_LOOP") then
            if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
        end
    end)
    f.smartFocus:SetScript("OnClick",function()
        local state=JLP:GetModule("GatheringSharedMapState")
        local s=state and state:GetSnapshot()
        local nextFocus=s and (s.focus=="MATERIALS" and "SKILL" or s.focus=="SKILL" and "BALANCED" or "MATERIALS")
        if nextFocus and state:SetMode("SMART_PROFESSION",nextFocus) then
            if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
        end
    end)
    -- Route actions are visible above the map without replacing Blizzard art.
    f.nodePickerButton=JLP.UIWidgets:Button(f.mapContainer,"Select Nodes",145)
    positionMapToolbarButton(f.nodePickerButton,0,36,124)
    f.generateLoop=JLP.UIWidgets:Button(f.mapContainer,"Generate Loop",156)
    positionMapToolbarButton(f.generateLoop,134,36,132)
    f.clearLoop=JLP.UIWidgets:Button(f.mapContainer,"Clear / Cancel",150)
    positionMapToolbarButton(f.clearLoop,276,36,122)
    f.loopShape=JLP.UIWidgets:Button(f.mapContainer,"Shape: Loop",205)
    f.loopShape:SetHeight(28);f.loopShape:SetPoint("TOPLEFT",509,-127)
    -- Selection popover is JLP-owned; no imported addon panel/runtime or scroll dependency.
    local pickerTokens=JLP.UITheme and JLP.UITheme.gathering or {}
    local function pickerToken(name,fallback) return pickerTokens[name] or fallback end
    local picker=JLP.UIWidgets:Card(f.mapContainer,"Gathering Node Selection","secondary")
    picker:SetPoint("TOPLEFT",f.mapContainer,"TOPLEFT",pickerToken("pickerPreferredLeft",358),-pickerToken("pickerTop",179))
    picker:SetSize(pickerToken("pickerPreferredWidth",365),pickerToken("pickerPreferredHeight",350))
    if picker.SetFrameLevel and f.mapArt.GetFrameLevel then
        local policy=JLP.UILayout
        picker:SetFrameLevel(policy and policy:OverlayFrameLevel(f.mapArt,"popover") or f.mapArt:GetFrameLevel()+9)
    end
    f.nodePicker=picker
    f.pickerProfession="HERBALISM";f.pickerOffset=0
    f.pickerRowCount=pickerToken("pickerMaxRows",6) -- recalculated from real map parent on each layout
    f.pickerContentFits=true -- fail closed after measuring actual parent bounds
    f.pickerSearch=CreateFrame("EditBox",nil,picker,"InputBoxTemplate")
    f.pickerSearch:SetSize(pickerToken("pickerSearchWidth",325),23);f.pickerSearch:SetPoint("TOPLEFT",19,-46)
    if f.pickerSearch.SetAutoFocus then f.pickerSearch:SetAutoFocus(false) end
    f.pickerSearch:SetText("")
    f.pickerInfo=label(picker,"Choose resources for the current zone",18,-75,331,"GameFontHighlightSmall","muted")
    f.pickerProfessionButton=JLP.UIWidgets:Button(picker,"Herbalism",145)
    f.pickerProfessionButton:SetHeight(24);f.pickerProfessionButton:SetPoint("TOPLEFT",18,-96)
    f.pickerAll=JLP.UIWidgets:Button(picker,"Select All",83)
    f.pickerAll:SetHeight(24);f.pickerAll:SetPoint("TOPLEFT",168,-96)
    f.pickerNone=JLP.UIWidgets:Button(picker,"None",78)
    f.pickerNone:SetHeight(24);f.pickerNone:SetPoint("TOPLEFT",258,-96)
    f.pickerRows={}
    for i=1,pickerToken("pickerMaxRows",6) do
        local b=JLP.UIWidgets:Button(picker,"",pickerToken("pickerResourceButtonWidth",326))
        b:SetHeight(pickerToken("pickerRowHeight",25));b:SetPoint("TOPLEFT",20,-pickerToken("pickerRowTop",128)-(i-1)*pickerToken("pickerRowStride",27))
        b.resourceIcon=b:CreateTexture(nil,"OVERLAY")
        b.resourceIcon:SetSize(16,16);b.resourceIcon:SetPoint("LEFT",b,"LEFT",5,0)
        f.pickerRows[i]=b
    end
    f.pickerPages=label(picker,"1-6 / ?",138,-302,94,"GameFontHighlightSmall","muted")
    f.pickerPages:ClearAllPoints()
    f.pickerPages:SetPoint("BOTTOM",picker,"BOTTOM",0,16)
    f.pickerMatchingCount=0
    f.pickerScrollbar=JLP.UILayout:AttachOffsetScrollbar(picker,{
        top=-124,bottom=47,right=-4,gutter=10,
        getState=function()
            local visible=math.max(1,tonumber(f.pickerRowCount) or 1)
            local total=math.max(visible,tonumber(f.pickerMatchingCount) or 0)
            return f.pickerOffset or 0,math.max(0,total-visible),visible,total
        end,
        setOffset=function(offset)
            f.pickerOffset=math.floor(math.max(0,offset)+0.5)
            if f.UpdatePicker then f:UpdatePicker() end
        end,
    })
    picker:Hide()
    local function updatePicker()
        if not picker:IsShown() then return end
        local function unavailable(reason)
            for _,button in ipairs(f.pickerRows) do
                button.resourceKey=nil;button:Hide()
                if button.SetEnabled then button:SetEnabled(false) end
            end
            f.pickerPages:SetText("0 / 0")
            f.pickerInfo:SetText(reason or "No resource layers available")
            f.pickerMatchingCount=0
            if f.pickerScrollbar then f.pickerScrollbar:Refresh() end
            for _,button in ipairs({f.pickerAll,f.pickerNone,
                f.pickerProfessionButton}) do
                if button.SetEnabled then button:SetEnabled(false) end
            end
        end
        if f.pickerContentFits==false then
            unavailable("Map too narrow; enlarge view to select")
            if f.pickerSearch.SetEnabled then f.pickerSearch:SetEnabled(false) end
            if f.pickerSearch.SetShown then f.pickerSearch:SetShown(false) end
            for _,control in ipairs({f.pickerProfessionButton,f.pickerAll,f.pickerNone,
                f.pickerPages}) do
                if control.SetShown then control:SetShown(false) end
            end
            return
        end
        if f.pickerSearch.SetEnabled then f.pickerSearch:SetEnabled(true) end
        if f.pickerSearch.SetShown then f.pickerSearch:SetShown(true) end
        for _,control in ipairs({f.pickerProfessionButton,f.pickerAll,f.pickerNone,
            f.pickerPages}) do
            if control.SetShown then control:SetShown(true) end
        end
        local ctrl=JLP:GetModule("GatheringMapLayerController")
        local ok,state=pcall(function() return f.lastMapID and ctrl and ctrl:GetLayerState(f.lastMapID) end)
        if not ok or type(state)~="table" or type(state.layers)~="table" then
            unavailable("Resource layers unavailable for this map");return
        end
        local layers=state.layers
        local layer=layers[f.pickerProfession]
        if type(layer)~="table" or not layer.learned then
            local alt=f.pickerProfession=="HERBALISM" and "MINING" or "HERBALISM"
            if type(layers[alt])=="table" and layers[alt].learned then
                f.pickerProfession=alt;layer=layers[alt]
            end
        end
        if type(layer)~="table" or not layer.learned then
            unavailable("Learn Herbalism or Mining to select resources");return
        end
        local browser=JLP:GetModule("GatheringResourceBrowser")
        if type(browser)~="table" or type(browser.Build)~="function" then
            unavailable("Resource browser unavailable");return
        end
        local capacity=math.max(0,math.min(pickerToken("pickerMaxRows",6),math.floor(tonumber(f.pickerRowCount) or 0)))
        if capacity==0 then
            unavailable("Not enough height for resource selection; enlarge the view")
            return
        end
        local built,listing=pcall(browser.Build,browser,layer,f.pickerSearch:GetText(),f.pickerOffset,capacity)
        if not built or type(listing)~="table" or type(listing.rows)~="table" then
            unavailable("Unable to load resources; retry map selection");return
        end
        f.pickerOffset=tonumber(listing.offset) or 0
        f.pickerMatchingCount=tonumber(listing.matchingCount) or 0
        if f.pickerScrollbar then f.pickerScrollbar:Refresh() end
        local viewport=JLP:GetModule("GatheringViewportLayout")
        local pageState=viewport and viewport.ResourcePageState and
            viewport:ResourcePageState(listing,capacity,layer)
        local shared=JLP:GetModule("GatheringSharedMapState")
        local opts=shared and shared:GetSnapshot()
        local smart=opts and opts.mode=="SMART_PROFESSION"
        local selection=JLP.UIWidgets and JLP.UIWidgets.GatheringResourceSelectionFeedback and
            JLP.UIWidgets:GatheringResourceSelectionFeedback(layer,listing.selectedCount,
                opts and opts.mode,listing.matchingCount,listing.totalCount)
        f.pickerInfo:SetText(selection and selection.text or "Resource evidence unavailable")
        f.pickerProfessionButton:SetText(f.pickerProfession=="HERBALISM" and "Herbalism" or "Mining")
        f.pickerPages:SetText(pageState and (pageState.page.." / "..pageState.pageCount) or
            (tostring(listing.first or 0).."-"..tostring(listing.last or 0).." / "..tostring(listing.matchingCount or 0)))
        if pageState and pageState.status~="READY" then f.pickerInfo:SetText(pageState.text or "No resources") end
        local rowRenderer=JLP:GetModule("GatheringResourceRow")
        for i,button in ipairs(f.pickerRows) do
            if i>capacity then
                button.resourceKey=nil;button:Hide()
                if button.SetEnabled then button:SetEnabled(false) end
            elseif rowRenderer and type(rowRenderer.Apply)=="function" then
                rowRenderer:Apply(button,(not pageState or pageState.status=="READY") and listing.rows[i] or nil,
                    f.pickerProfession,layer.learned,smart,pickerToken("pickerRowStride",27))
            else button.resourceKey=nil;button:Hide() end
        end
        if f.pickerProfessionButton.SetEnabled then
            local alt=f.pickerProfession=="HERBALISM" and "MINING" or "HERBALISM"
            f.pickerProfessionButton:SetEnabled(type(layers[alt])=="table" and layers[alt].learned==true)
        end
        if f.pickerAll.SetText then
            local q=f.pickerSearch and f.pickerSearch:GetText() or ""
            f.pickerAll:SetText(type(q)=="string" and q:match("%S") and "All matches" or "All")
        end
        if f.pickerAll.SetEnabled then f.pickerAll:SetEnabled(not smart and
            (not pageState or pageState.canSelect)) end
        if f.pickerNone.SetEnabled then f.pickerNone:SetEnabled(not smart and
            (not pageState or pageState.canSelect)) end
    end
    f.UpdatePicker=updatePicker
    if picker.EnableMouseWheel then picker:EnableMouseWheel(true) end
    picker:SetScript("OnMouseWheel",function(_,delta)
        if f.pickerContentFits==false then return end
        f.pickerOffset=math.max(0,(f.pickerOffset or 0)+(delta<0 and 2 or -2))
        updatePicker()
    end)
    f.pickerSearch:SetScript("OnTextChanged",function() f.pickerOffset=0;updatePicker() end)
    f.pickerSearch:SetScript("OnEscapePressed",function(self)
        if self.ClearFocus then self:ClearFocus() end
    end)
    local function refresh()
        if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
    end
    f.nodePickerButton:SetScript("OnClick",function()
        local state=JLP:GetModule("GatheringSharedMapState")
        local opts=state and state:GetSnapshot()
        if opts and opts.mode=="SMART_PROFESSION" then picker:Hide();return end
        if picker:IsShown() then picker:Hide()
        else
            if f.mapToolsPanel then f.mapToolsPanel:Hide() end
            if f.explanationPopup then f.explanationPopup:Hide() end
            f.toolsShown=false
            for _,button in ipairs(f.mapToolButtons or {}) do button:Hide() end
            picker:Show();updatePicker()
        end
    end)
    f.pickerProfessionButton:SetScript("OnClick",function()
        if f.pickerContentFits==false then return end
        local ctrl=JLP:GetModule("GatheringMapLayerController")
        local info=ctrl and f.lastMapID and ctrl:GetLayerState(f.lastMapID)
        local alt=f.pickerProfession=="HERBALISM" and "MINING" or "HERBALISM"
        if info and type(info.layers)=="table" and type(info.layers[alt])=="table" and info.layers[alt].learned then f.pickerProfession=alt;f.pickerOffset=0;updatePicker() end
    end)
    for _,button in ipairs(f.pickerRows) do
        button:SetScript("OnClick",function(self)
            if f.pickerContentFits==false then return end
            local state=JLP:GetModule("GatheringSharedMapState")
            local selected=state and f.lastMapID and state:GetResourceSelection(f.lastMapID,f.pickerProfession)
            local key=self.resourceKey
            local opts=state and state:GetSnapshot()
            if key and opts and opts.mode=="CUSTOM_LOOP" and
                type(state.SelectQualifiedZoneResource)=="function" then
                local adding=not (selected and selected[key])
                local ok,reason=state:SelectQualifiedZoneResource(f.lastMapID,f.pickerProfession,key,adding)
                if ok then
                    if adding then f.includeGathering=true end
                    refresh();updatePicker()
                elseif f.pickerInfo then
                    f.pickerInfo:SetText("Node unavailable · "..tostring(reason or "UNKNOWN"))
                end
            end
        end)
    end
    for _,setting in ipairs({{button=f.pickerAll,enabled=true},{button=f.pickerNone,enabled=false}}) do
        setting.button:SetScript("OnClick",function()
            if f.pickerContentFits==false then return end
            local state=JLP:GetModule("GatheringSharedMapState")
            local ok,reason=false,"MAP_UNAVAILABLE"
            if state and f.lastMapID then
                if setting.enabled and type(state.ActivateZoneResources)=="function" then
                    ok,reason=state:ActivateZoneResources(f.lastMapID,f.pickerProfession,
                        f.pickerSearch and f.pickerSearch:GetText() or "")
                else
                    ok,reason=state:SetResourceSelectionAll(f.lastMapID,f.pickerProfession,setting.enabled)
                end
            end
            if ok then
                -- Explicit resource setup opts the Fishing workspace into
                -- advisory gathering; no automatic route generation.
                if setting.enabled then f.includeGathering=true end
                refresh();updatePicker()
            elseif f.pickerInfo then
                f.pickerInfo:SetText("Cannot select zone resources · "..tostring(reason))
            end
        end)
    end
    f.loopShape:SetScript("OnClick",function()
        local state=JLP:GetModule("GatheringSharedMapState")
        local old=state and state:GetSnapshot()
        if old and state:SetRouteShape(old.routeShape=="LOOP" and "FROM_PLAYER" or "LOOP") then refresh() end
    end)
    local function routeReceipt(ok,reason,status)
        Page:RecordRouteReceipt(f,ok,reason,status)
        refresh()
        return ok,reason
    end
    f.generateLoop:SetScript("OnClick",function()
        if not f.includeGathering then
            -- A Fishing-only Generate creates an explicitly non-navigable
            -- historical SECTOR review, never a fictional pool-point route.
            local planner=JLP:GetModule("FishingSectorItinerary70450")
            local state=JLP:GetModule("GatheringSharedMapState")
            local options=state and state:GetSnapshot()
            -- Preserve the real Build() rejection reason; Lua `and`
            -- expressions collapse multiple return values to one.
            local plan,reason
            if planner and f.lastMapID then
                plan,reason=planner:Build(f.lastMapID,
                    options and options.routeShape or "LOOP",f.lastPlayerPosition)
            else
                reason=not f.lastMapID and "MAP_UNAVAILABLE" or "FISHING_SECTOR_PLANNER_UNAVAILABLE"
            end
            f.fishingAreaPlan=plan
            f.fishingAdvice=plan and planner:Describe(plan) or
                "Fishing sector review unavailable: "..tostring(reason or "DATA_UNAVAILABLE")
            refresh()
            return plan~=nil,plan and "HISTORICAL_SECTOR_REVIEW_ONLY" or reason
        end
        local route=JLP:GetModule("GatheringRouteService")
        local state=JLP:GetModule("GatheringSharedMapState")
        local err=not f.lastMapID and "MAP_UNAVAILABLE" or not state and "STATE_UNAVAILABLE" or
            not route and "ROUTE_SERVICE_UNAVAILABLE" or nil
        if err then return routeReceipt(false,err) end
        local snapshotOK,snapshot=false,nil
        if type(state.GetSnapshot)=="function" then
            snapshotOK,snapshot=pcall(state.GetSnapshot,state)
        end
        if not snapshotOK or type(snapshot)~="table" or
            (snapshot.routeShape~="LOOP" and snapshot.routeShape~="FROM_PLAYER") then
            return routeReceipt(false,"STATE_UNAVAILABLE")
        end
        local requestedMap=f.lastMapID
        f.routeRequestSerial=(f.routeRequestSerial or 0)+1
        local requestSerial=f.routeRequestSerial
        local callbackToken=nil
        local callbackDuringStart=false
        -- Publish truthful first feedback before potentially expensive work;
        -- do not pretend this is native FontString first paint.
        if f.routeHint and f.routeHint.SetText then
            f.routeHint:SetText("GENERATING · preparing advisory route…")
        end
        local invoked,ok,why=pcall(route.Start,route,requestedMap,snapshot.routeShape,
            f.lastPlayerPosition,function()
                if callbackToken==nil then callbackDuringStart=true;return end
                local tokenOK,token=pcall(route.GetContextToken,route,requestedMap)
                if tokenOK and f.routeRequestSerial==requestSerial and f.lastMapID==requestedMap and
                    callbackToken==token then refresh() end
            end)
        if not invoked then ok=false;why="ROUTE_START_EXCEPTION" end
        if ok==true then
            local tokenOK,token=false,nil
            if type(route.GetContextToken)=="function" then
                tokenOK,token=pcall(route.GetContextToken,route,requestedMap)
            end
            if tokenOK and type(token)=="string" and token~="" then callbackToken=token end
            if callbackToken==nil then ok=false;why="ROUTE_GENERATION_UNCONFIRMED" end
        end
        if ok~=true and (not invoked or why=="ROUTE_GENERATION_UNCONFIRMED") then
            -- A throwing Start or an unbound generation is uncertain: hide
            -- old artwork in both views and quarantine the shared owner.
            if type(route.QuarantineUnconfirmedCancellation)=="function" then
                pcall(route.QuarantineUnconfirmedCancellation,route,why)
            end
            f.lastRouteSnapshot=nil;f.lastGatheringSnapshot=nil
            f.forceMapRefresh=true
            if f.mapArt then
                local overlay=JLP:GetModule("GatheringMapOverlay")
                if overlay and type(overlay.Clear)=="function" then
                    pcall(overlay.Clear,overlay,f.mapArt)
                end
            end
        end
        -- Ordinary preflight rejection leaves the previous route generation
        -- committed by GatheringRouteService. Do not erase its map overlay;
        -- feedback still reports the rejected new request to the user.
        local status=nil
        if ok==true and type(route.GetStatusForMap)=="function" then
            local statusOK,result=pcall(route.GetStatusForMap,route,requestedMap)
            if statusOK then status=result end
        end
        if ok==true and type(route.MarkFeedbackStaged)=="function" then
            pcall(route.MarkFeedbackStaged,route,requestedMap)
        end
        -- If an engine completed synchronously in Start, refresh after the
        -- token has been bound; never accept an unbound callback receipt.
        if ok==true and callbackDuringStart and f.lastMapID==requestedMap then
            f.forceMapRefresh=true
        end
        return routeReceipt(ok==true,why,status)
    end)
    f.clearLoop:SetScript("OnClick",function()
        f.routeRequestSerial=(f.routeRequestSerial or 0)+1
        return routeReceipt(Page:CancelRouteForView(f))
    end)
    f.mapArt:SetScript("OnUpdate",function(_,elapsed)
        local dt=type(elapsed)=="number" and elapsed or 0.03
        local suitability=JLP:GetModule("GatheringZoneSuitability")
        if suitability and suitability:GetRecommendationStatus()=="GENERATING" then
            f.suitabilityElapsed=(f.suitabilityElapsed or 0)+dt
            if f.suitabilityElapsed>=0.02 then
                f.suitabilityElapsed=0
                suitability:TickRecommendation()
                local scanning=suitability:GetRecommendationProgress()
                if scanning then
                    f.suggestZone:SetText("Cancel Scan "..tostring(scanning.zonesProcessed).."/"..tostring(scanning.zonesTotal))
                else
                    f.suggestZone:SetText("Recommend Zone")
                end
            end
        end
        -- The shared GatheringRouteService owns the only route Tick driver.
        -- This viewport may refresh text, but cannot advance the job twice.
        -- Keep the client-provided player arrow current without regenerating
        -- routes/pin snapshots on every frame. Never use remote-zone coordinates.
        f.positionElapsed=(f.positionElapsed or 0)+dt
        if f.positionElapsed>=0.45 then
            f.positionElapsed=0
            local map=JLP:GetModule("ForeverFishingMapCanvas")
            local live=map and map:GetCurrentZone()
            if live and f.lastMapID and live.mapID~=f.lastCurrentMapID then
                f.lastCurrentMapID=live.mapID
                local shared=JLP:GetModule("GatheringSharedMapState")
                local selected=shared and shared:GetSnapshot()
                if selected and not selected.selectedMapID then
                    f.forceMapRefresh=true
                    if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
                end
            elseif map and live and f.mapReady and f.lastArt and f.lastMapID==live.mapID then
                if live.playerPosition then map:PlacePlayerMarker(f.mapArt,f.lastArt,live.playerPosition)
                else map:HidePlayerMarker(f.mapArt) end
            end
        end
    end)
    f.layerInfo=label(right,"GATHERING",22,-466,100,"GameFontHighlightSmall","muted")
    f.herbLayer=JLP.UIWidgets:Button(right,"Herbalism: Off",216)
    f.herbLayer:SetHeight(28); f.herbLayer:SetPoint("TOPLEFT",22,-487)
    f.oreLayer=JLP.UIWidgets:Button(right,"Mining: Off",216)
    f.oreLayer:SetHeight(28); f.oreLayer:SetPoint("TOPLEFT",22,-520)
    f.resourceFilter=JLP.UIWidgets:Button(right,"Resource: All",216)
    f.resourceFilter:SetHeight(28); f.resourceFilter:SetPoint("TOPLEFT",22,-553)
    local function changeLayer(key)
        local ctrl=JLP:GetModule("GatheringMapLayerController")
        if ctrl and f.lastMapID and ctrl:ToggleLayer(f.lastMapID,key) then
            f.includeGathering=true -- explicit click opts Fishing into extra gathering layers
            f.gatheringOverlay:SetText("Herb/Ore overlays: Visible")
            if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
        end
    end
    f.herbLayer:SetScript("OnClick",function() changeLayer("HERBALISM") end)
    f.oreLayer:SetScript("OnClick",function() changeLayer("MINING") end)
    f.resourceFilter:SetScript("OnClick",function()
        local ctrl=JLP:GetModule("GatheringMapLayerController")
        local state=ctrl and f.lastMapID and ctrl:GetLayerState(f.lastMapID)
        local key=state and state.layers.HERBALISM.enabled and "HERBALISM" or
            state and state.layers.MINING.enabled and "MINING" or nil
        if key and ctrl:CycleResource(f.lastMapID,key) then
            if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
        end
    end)
    f.sourceLayer=JLP.UIWidgets:Button(right,"Pins: All",112)
    f.sourceLayer:SetHeight(24);f.sourceLayer:SetPoint("TOPLEFT",127,-459)
    f.fishingFilter=JLP.UIWidgets:Button(right,"Fishing filter: All",216)
    f.fishingFilter:SetHeight(26);f.fishingFilter:SetPoint("TOPLEFT",22,-318)
    local fishPicker=JLP:GetModule("FishingResourcePicker70450")
    f.fishResourcePicker=fishPicker and fishPicker:Attach(f.fishingFilter,
        function() return f.lastMapID end,
        function()
            f.forceMapRefresh=true
            if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
            if JLP.StandaloneGatheringMap and JLP.StandaloneGatheringMap.IsShown and
                JLP.StandaloneGatheringMap:IsShown() then JLP.StandaloneGatheringMap:Refresh() end
        end)
    f.fishingFilter:SetScript("OnClick",function()
        if f.fishResourcePicker then f.fishResourcePicker.Toggle() end
    end)
    f.routeSources=JLP.UIWidgets:Button(right,"Route nodes: All",216)
    f.routeSources:SetHeight(24);f.routeSources:SetPoint("TOPLEFT",22,-350)
    f.routeSources:SetScript("OnClick",function()
        local state=JLP:GetModule("GatheringSharedMapState")
        if state and state:CycleRouteSource() and JLP.UIPages and JLP.UIPages.Secondaries then
            JLP.UIPages.Secondaries:Refresh() end
    end)
    f.sourceLayer:SetScript("OnClick",function()
        local state=JLP:GetModule("GatheringSharedMapState")
        local snapshot=state and state:GetSnapshot()
        if state and snapshot then
            state:SetSourceFilter(snapshot.sourceFilter=="ALL" and "OBSERVED_ONLY" or "ALL")
            if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
        end
    end)
    f.mapFallback=label(f.mapContainer,"Live zone art unavailable; source requirements shown above.",22,-224,680,"GameFontHighlight","muted")
    f.mapFallback:Hide()
    f.refreshMap=JLP.UIWidgets:Button(right,"Refresh Map",108)
    f.refreshMap:SetHeight(28)
    f.refreshMap:SetPoint("BOTTOMLEFT",right,"BOTTOMLEFT",24,26)
    f.fishingRecommend=JLP.UIWidgets:Button(right,"Suggest Zone",108)
    f.fishingRecommend:SetHeight(28)
    f.fishingRecommend:SetPoint("BOTTOMLEFT",right,"BOTTOMLEFT",138,26)
    f.fishingRecommend:SetScript("OnClick",function()
        local area,why=suggestFishingZone()
        f.fishingAdvice=area and ("Historical coverage: "..tostring(area.uniqueSectors).." sectors; not catch-rate") or
            ("Fishing suggestion unavailable: "..tostring(why))
        if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
    end)
    f.refreshMap:SetScript("OnClick",function()
        f.forceMapRefresh=true
        if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
    end)
    f.skill=row(right,"CURRENT SKILL",-65,214)
    f.plan=row(right,"CURRENT PLAN",-141,214)
    f.sources=row(right,"SOURCES",-219,214)
    f.access=row(right,"TRAINING / ACCESS",-297,214)
    f.catchInfo=row(right,"HISTORICAL FISH CATCHES",-374,214)
    f.mapTools=JLP.UIWidgets:Button(f.mapContainer,"Map Options",205)
    positionMapToolbarButton(f.mapTools,408,36,136)
    f.mapToolsPanel=JLP.UIWidgets:Card(f.mapContainer,"Gathering Options","secondary")
    f.mapToolsPanel:SetPoint("TOPRIGHT",f.mapContainer,"TOPRIGHT",-18,-170)
    f.mapToolsPanel:SetSize(463,324)
    if f.mapToolsPanel.SetFrameLevel and f.mapArt.GetFrameLevel then
        local policy=JLP.UILayout
        f.mapToolsPanel:SetFrameLevel(policy and policy:OverlayFrameLevel(f.mapArt,"popover") or f.mapArt:GetFrameLevel()+15)
    end
    local toolPositions={{f.routeMode,14,-44},{f.smartFocus,244,-44},
        {f.suggestZone,14,-79},{f.loopShape,244,-79},
        {f.herbLayer,14,-114},{f.oreLayer,244,-114},
        {f.resourceFilter,14,-149},{f.sourceLayer,244,-149},
        {f.fishingAreas,14,-184},{f.fishingFilter,244,-184},
        {f.routeSources,14,-219},{f.gatheringOverlay,244,-219}}
    f.mapToolButtons={}
    for _,entry in ipairs(toolPositions) do
        local b,x,y=entry[1],entry[2],entry[3]
        if b.ClearAllPoints then b:ClearAllPoints() end
        if b.SetParent then b:SetParent(f.mapToolsPanel) end
        b:SetPoint("TOPLEFT",f.mapToolsPanel,"TOPLEFT",x,y)
        if b.SetFrameLevel and f.mapToolsPanel.GetFrameLevel then b:SetFrameLevel(f.mapToolsPanel:GetFrameLevel()+2) end
        b:Hide()
        f.mapToolButtons[#f.mapToolButtons+1]=b
    end
    f.mapRationale=label(f.mapToolsPanel,"Historical sources are advisory. Full details are available below.",14,-251,430,"GameFontHighlightSmall","muted")
    if f.mapRationale.SetHeight then f.mapRationale:SetHeight(29) end
    if f.mapRationale.SetWordWrap then f.mapRationale:SetWordWrap(true) end
    -- Manual viewport navigation: the committed route remains service-owned.
    f.focusRoute=JLP.UIWidgets:Button(f.mapToolsPanel,"Show Route",205)
    f.focusRoute:SetHeight(24)
    f.focusRoute:SetPoint("TOPLEFT",f.mapToolsPanel,"TOPLEFT",14,-287)
    f.focusRoute:SetScript("OnClick",function()
        local service=JLP:GetModule("GatheringRouteService")
        local helper=JLP:GetModule("GatheringRouteViewport")
        if not (f.lastMapID and f.mapReady and f.lastArt and service and helper) then
            f.routeHint:SetText("Route not ready · choose a zone and generate first")
            return false,"ROUTE_VIEW_UNAVAILABLE"
        end
        local routes,status=service:GetRoutes(f.lastMapID)
        if status~="READY" then
            f.routeHint:SetText("Route not ready · generate an advisory route")
            return false,"ROUTE_NOT_READY"
        end
        local ok,reason=helper:Apply(f.mapArt,f.lastArt,
            {mapID=f.lastMapID,routes=routes},f.lastMapID)
        if not ok then
            f.routeHint:SetText("Cannot show route · "..tostring(reason))
            return false,reason
        end
        -- Remove the options overlay so the fitted route can actually be seen.
        f.toolsShown=false
        f.mapToolsPanel:Hide()
        f.forceMapRefresh=true
        if JLP.UIPages and JLP.UIPages.Secondaries then JLP.UIPages.Secondaries:Refresh() end
        return true,reason
    end)
    f.whyRoute=JLP.UIWidgets:Button(f.mapToolsPanel,"Why this route?",205)
    f.whyRoute:SetHeight(24)
    f.whyRoute:SetPoint("TOPLEFT",f.mapToolsPanel,"TOPLEFT",244,-287)
    local function showExplanation(button)
        if not GameTooltip or not GameTooltip.SetOwner then return end
        GameTooltip:SetOwner(button,"ANCHOR_RIGHT")
        if GameTooltip.ClearLines then GameTooltip:ClearLines() end
        if GameTooltip.AddLine then
            GameTooltip:AddLine("Gathering route · source explanation",0.45,0.85,1)
            local pages=JLP:GetModule("GatheringRouteExplanation")
            local readable=pages and pages:Pages(f.fullRouteRationale or "Historical locations only",48,4) or {f.fullRouteRationale or "Historical locations only"}
            if readable[1] then GameTooltip:AddLine(readable[1],1,1,1,true) end
            GameTooltip:AddLine("Click for the full, paginated explanation.",0.6,0.85,1,true)
        end
        if GameTooltip.Show then GameTooltip:Show() end
    end
    f.whyRoute:SetScript("OnEnter",showExplanation)
    f.whyRoute:SetScript("OnClick",showExplanation)
    f.whyRoute:SetScript("OnLeave",function(self)
        if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self)
        elseif GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==self then GameTooltip:Hide() end
    end)
    -- A separate bounded, paginated detail view uses the *same* map canvas
    -- safe area as Map Options. Only one is visible at once.
    f.explanationPopup=JLP.UIWidgets:Card(f.mapContainer,"Route source explanation","secondary")
    f.explanationPopup:SetSize(463,324)
    f.explanationPopup:SetPoint("TOPRIGHT",f.mapContainer,"TOPRIGHT",-18,-170)
    if f.explanationPopup.SetFrameLevel and f.mapArt.GetFrameLevel then
        local policy=JLP.UILayout
        f.explanationPopup:SetFrameLevel(policy and policy:OverlayFrameLevel(f.mapArt,"modal") or f.mapArt:GetFrameLevel()+16)
    end
    f.explanationText=label(f.explanationPopup,"No route explanation available",14,-46,434,"GameFontHighlight","muted")
    if f.explanationText.SetWidth then f.explanationText:SetWidth(434) end
    if f.explanationText.SetHeight then f.explanationText:SetHeight(181) end
    if f.explanationText.SetWordWrap then f.explanationText:SetWordWrap(true) end
    f.explanationPage=label(f.explanationPopup,"1 / 1",185,-251,96,"GameFontHighlightSmall","muted")
    local previous=JLP.UIWidgets:Button(f.explanationPopup,"Previous",118)
    previous:SetHeight(25);previous:SetPoint("TOPLEFT",f.explanationPopup,"TOPLEFT",14,-269)
    local following=JLP.UIWidgets:Button(f.explanationPopup,"Next",118)
    following:SetHeight(25);following:SetPoint("TOPLEFT",f.explanationPopup,"TOPLEFT",169,-269)
    local close=JLP.UIWidgets:Button(f.explanationPopup,"Close",118)
    close:SetHeight(25);close:SetPoint("TOPLEFT",f.explanationPopup,"TOPLEFT",325,-269)
    f.whyRoutePages={}
    f.whyRoutePage=1
    function f:RefreshExplanationPages()
        local explanation=JLP:GetModule("GatheringRouteExplanation")
        self.whyRoutePages=explanation and explanation:Pages(self.fullRouteRationale or "Historical locations only",42,4) or
            {self.fullRouteRationale or "Historical locations only"}
        self.whyRoutePage=math.min(math.max(1,self.whyRoutePage or 1),#self.whyRoutePages)
        self.explanationText:SetText(self.whyRoutePages[self.whyRoutePage] or "No details")
        self.explanationPage:SetText(tostring(self.whyRoutePage).." / "..tostring(#self.whyRoutePages))
        if previous.SetEnabled then previous:SetEnabled(self.whyRoutePage>1) end
        if following.SetEnabled then following:SetEnabled(self.whyRoutePage<#self.whyRoutePages) end
    end
    previous:SetScript("OnClick",function() f.whyRoutePage=math.max(1,f.whyRoutePage-1);f:RefreshExplanationPages() end)
    following:SetScript("OnClick",function()f.whyRoutePage=math.min(#f.whyRoutePages,f.whyRoutePage+1);f:RefreshExplanationPages() end)
    close:SetScript("OnClick",function()
        f.explanationPopup:Hide()
        f.mapToolsPanel:Show()
        for _,button in ipairs(f.mapToolButtons or {}) do button:Show() end
    end)
    f.whyRoute:SetScript("OnClick",function()
        if f.nodePicker then f.nodePicker:Hide() end
        f.whyRoutePage=1;f:RefreshExplanationPages()
        f.mapToolsPanel:Hide()
        for _,button in ipairs(f.mapToolButtons or {}) do button:Hide() end
        f.explanationPopup:Show()
    end)
    f.explanationPopup:Hide()
    f.mapToolsPanel:Hide()
    f.mapTools:SetScript("OnClick",function()
        if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(f.whyRoute) end
        f.toolsShown=not f.toolsShown
        if f.toolsShown and f.nodePicker then f.nodePicker:Hide() end
        f.mapToolsPanel:SetShown(f.toolsShown)
        if f.explanationPopup then f.explanationPopup:Hide() end
        for _,b in ipairs(f.mapToolButtons) do b:SetShown(f.toolsShown) end
    end)
    f.activateCurrent=JLP.UIWidgets:Button(right,"Use Fishing Current Step")
    f.activateCurrent:SetPoint("BOTTOMLEFT",22,12);f.activateCurrent:SetSize(218,27)
    f.activateCurrent:SetScript("OnClick",function()local svc=model();if svc then svc:ActivateCurrentStep("FISHING")end;Page:Refresh()end)
    f.mapReady=false
    return f
end

local function createFirstAid(parent)
    local f=CreateFrame("Frame",nil,parent); f:SetAllPoints()
    local left=makeCard(f,"First Aid Progress & Recipes",0,666,HEIGHT)
    local right=makeCard(f,"Cloth, Herbs & Sources",680,398,HEIGHT)
    f.primaryCard=left;f.secondaryCard=right
    f.activateCurrent=JLP.UIWidgets:Button(left,"Use First Aid Current Step")
    f.activateCurrent:SetPoint("BOTTOMLEFT",22,25);f.activateCurrent:SetSize(240,27)
    f.activateCurrent:SetScript("OnClick",function()
        local service=JLP:GetModule("SecondaryWorkspace")
        if service then service:ActivateCurrentStep("FIRST_AID")end
        Page:Refresh()
    end)
    f.skill=row(left,"CURRENT SKILL",-70,622)
    f.plan=row(left,"CURRENT PLAN",-150,622)
    f.progress=row(left,"SKILL COVERAGE",-245,622)
    f.rank=row(left,"RANK REQUIREMENTS",-346,622)
    f.resources=row(right,"REAGENTS",-75,350)
    f.sources=row(right,"ACQUISITION",-190,350)
    f.note=label(right,"",22,-320,350,"GameFontHighlight","muted")
    f.disclaimer=label(right,"Forever reference preview only. No automatic bandage or potion crafting.",22,-474,350,"GameFontHighlightSmall","muted")
    -- First Aid's right card has fixed section starts. Explicitly enable
    -- multi-line wrapping and bound each value to the space before the next
    -- section. Width remains controlled by ApplyViewportLayout() (right card).
    -- This is advisory text only: no recipe, skill or native craft state changes.
    Page:ConfigureFirstAidTextFlow(f)
    -- An independently scrolling information area ends BEFORE the fixed
    -- material/detail footer. No advisory label may cover the action button.
    f.firstAidScroll=CreateFrame("ScrollFrame",nil,right)
    f.firstAidScroll:SetPoint("TOPLEFT",right,"TOPLEFT",22,-58)
    f.firstAidScroll:SetPoint("BOTTOMRIGHT",right,"BOTTOMRIGHT",-37,172)
    f.firstAidContent=CreateFrame("Frame",nil,f.firstAidScroll)
    f.firstAidContent:SetSize(350,430)
    f.firstAidScroll:SetScrollChild(f.firstAidContent)
    if f.firstAidScroll.EnableMouseWheel then f.firstAidScroll:EnableMouseWheel(true) end
    f.firstAidScroll:SetScript("OnMouseWheel",function(self,delta)
        local total=f.firstAidContent:GetHeight() or 0
        local visible=self:GetHeight() or 1
        local at=self.GetVerticalScroll and self:GetVerticalScroll() or 0
        self:SetVerticalScroll(math.max(0,math.min(math.max(0,total-visible),at-delta*42)))
    end)
    for _,region in ipairs({f.resources.heading,f.resources.value,f.sources.heading,
        f.sources.value,f.note,f.disclaimer}) do region:SetParent(f.firstAidContent) end
    addMaterialPager(f,right,"FIRST_AID")
    f.firstAidScrollbar=JLP.UILayout:AttachNativeScrollbar(f.firstAidScroll,
        {owner=right,right=-22,top=-58,bottom=172})
    return f
end

-- One measured flow owns all First Aid labels; wrapping changes are reflected
-- after SetText as well as when the containing card becomes narrower.
function Page:LayoutFirstAidDetails(view)
    local host=view and view.firstAidContent
    local scroll=view and view.firstAidScroll
    if not host or not scroll then return false end
    local width=math.max(160,(view.secondaryCard:GetWidth() or 398)-44)
    host:SetWidth(width)
    local y=4
    local function block(region,fallback,pad)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT",host,"TOPLEFT",0,-y)
        region:SetWidth(width)
        if region.SetWordWrap then region:SetWordWrap(true) end
        if region.SetJustifyV then region:SetJustifyV("TOP") end
        local measured=region.GetStringHeight and tonumber(region:GetStringHeight()) or 0
        local height=math.max(fallback,measured or 0)
        region:SetHeight(height)
        y=y+height+(pad or 9)
    end
    for _,entry in ipairs({
        {view.resources.heading,16,5},{view.resources.value,30,18},
        {view.sources.heading,16,5},{view.sources.value,36,18},
        {view.note,30,20},{view.disclaimer,30,14},
    }) do block(entry[1],entry[2],entry[3]) end
    host:SetHeight(math.max(y,scroll:GetHeight() or 1))
    if view.firstAidScrollbar then view.firstAidScrollbar:Refresh() end
    local maxScroll=math.max(0,(host:GetHeight() or y)-(scroll:GetHeight() or 1))
    if scroll.GetVerticalScroll and scroll.SetVerticalScroll then
        scroll:SetVerticalScroll(math.min(maxScroll,scroll:GetVerticalScroll() or 0))
    end
    return true
end

-- Native FontStrings can wrap implicitly on some target clients and offline
-- shims may not expose SetWordWrap. SetHeight is the required geometry
-- contract; SetWordWrap is an optional explicit enhancement. A missing
-- SetHeight on any region aborts BEFORE any mutation. No client capability
-- or pixel result is inferred from this headless compatibility fallback.
function Page:ConfigureFirstAidTextFlow(view)
    if type(view)~="table" then return false,"VIEW_UNAVAILABLE" end
    local regions={
        {view.resources and view.resources.value,78,"reagents"},
        {view.sources and view.sources.value,86,"acquisition"},
        {view.note,128,"note"},
        {view.disclaimer,112,"disclaimer"},
    }
    for _,entry in ipairs(regions) do
        if not entry[1] or type(entry[1].SetHeight)~="function" then
            view.__firstAidTextFlow={status="UNAVAILABLE",reason="HEIGHT_API_UNAVAILABLE",field=entry[3],
                nativeWrapVerified=false}
            return false,"HEIGHT_API_UNAVAILABLE"
        end
    end
    local originals={}
    local allExplicit=true
    for index,entry in ipairs(regions) do
        local text,height=entry[1],entry[2]
        if type(text.GetHeight)=="function" then
            local success,value=pcall(text.GetHeight,text)
            originals[index]=success and type(value)=="number" and value or nil
        end
        local ok=pcall(text.SetHeight,text,height)
        if not ok then
            -- Restore each previous height where the client exposed a usable
            -- original dimension; never report success after a partial failure.
            for n=1,index do
                local previous=originals[n]
                if previous and type(regions[n][1].SetHeight)=="function" then
                    pcall(regions[n][1].SetHeight,regions[n][1],previous)
                end
            end
            view.__firstAidTextFlow={status="UNAVAILABLE",reason="HEIGHT_SET_FAILED",field=entry[3],
                nativeWrapVerified=false}
            return false,"HEIGHT_SET_FAILED"
        end
        if type(text.SetJustifyV)=="function" then pcall(text.SetJustifyV,text,"TOP") end
        if type(text.SetWordWrap)=="function" then
            local wrapped=pcall(text.SetWordWrap,text,true)
            if not wrapped then allExplicit=false end
        else
            allExplicit=false
        end
    end
    local status=allExplicit and "EXPLICIT_REQUESTED" or "IMPLICIT_WRAP_UNVERIFIED"
    view.__firstAidTextFlow={status=status,reason=allExplicit and nil or "WORD_WRAP_API_UNAVAILABLE_OR_FAILED",
        fieldCount=#regions,nativeWrapVerified=false}
    return true,status
end
function Page:GetFirstAidTextFlowStatus(view)
    return view and view.__firstAidTextFlow or
        {status="UNAVAILABLE",reason="NOT_CONFIGURED",nativeWrapVerified=false}
end

function Page:Create(parent)
    if self.frame then return self.frame end
    local f=CreateFrame("Frame",nil,parent); f:SetAllPoints()
    local viewport=CreateFrame("ScrollFrame",nil,f)
    viewport:SetPoint("TOPLEFT",f,"TOPLEFT",0,0)
    viewport:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",0,0)
    local root=CreateFrame("Frame",nil,viewport)
    root:SetSize(WIDTH,HEIGHT)
    if viewport.SetScrollChild then viewport:SetScrollChild(root) end
    f.pageScroll=viewport
    f.pageRoot=root
    f.scrollOffset=0
    f.scrollControls={}
    function f:ScrollPage(delta)
        local viewportHeight=self.GetHeight and self:GetHeight() or HEIGHT
        local endAt=math.max(0,(self.pageContentHeight or HEIGHT)-viewportHeight)
        local target=math.max(0,math.min(endAt,(self.scrollOffset or 0)+(tonumber(delta) or 0)))
        self.scrollOffset=target
        if self.pageScroll.SetVerticalScroll then self.pageScroll:SetVerticalScroll(target) end
        return target
    end
    if viewport.EnableMouseWheel then viewport:EnableMouseWheel(true) end
    viewport:SetScript("OnMouseWheel",function(_,wheel)f:ScrollPage(-(tonumber(wheel) or 0)*120) end)
    f.pageScrollbar=JLP.UILayout:AttachNativeScrollbar(viewport,
        {owner=f,right=-2,top=-2,bottom=2})
    f.views={overview=createOverview(root),COOKING=createCooking(root),FISHING=createFishing(root),FIRST_AID=createFirstAid(root)}
    local warning=label(f,"This content area is too small for the gathering controls. Enlarge the window or lower UI scale.",0,0,nil,"GameFontHighlight","muted")
    warning:ClearAllPoints()
    warning:SetPoint("CENTER",f,"CENTER",0,0)
    warning:SetWidth(400)
    f.layoutWarning=warning
    self.frame=f
    if f.SetScript then f:SetScript("OnSizeChanged",function() self:ApplyViewportLayout() end) end
    -- The floating source sheets are not descendants of f: hide when the
    -- owner page is hidden by MainWindow, without discarding Bank/AH receipts.
    if f.HookScript then f:HookScript("OnHide",function()
        for _,secondaryKey in ipairs({"COOKING","FIRST_AID"}) do
            local view=f.views and f.views[secondaryKey]
            if view and view.materialSourceSheet then
                view.materialDetailsOpen=false
                view.materialSourceSheet:Reset()
            end
        end
    end) end
    self:SetMode("overview")
    self:ApplyViewportLayout()
    return f
end

local function placeCard(card,owner,x,y,w,h,scale)
    if not card then return end
    card:ClearAllPoints()
    card:SetScale(scale or 1)
    card:SetSize(w,h)
    card:SetPoint("TOPLEFT",owner,"TOPLEFT",x,y)
end

local function setRowWidth(r,width)
    if r then
        if r.heading and r.heading.SetWidth then r.heading:SetWidth(width) end
        if r.value and r.value.SetWidth then r.value:SetWidth(width) end
    end
end

function Page:ApplyViewportLayout()
    local f=self.frame
    if not f or not f.pageRoot then return nil end
    local rawWidth=f.GetWidth and f:GetWidth() or WIDTH
    local rawHeight=f.GetHeight and f:GetHeight() or HEIGHT
    local layout=JLP.UILayout
    local bounds=layout and layout:SecondaryViewportFit(rawWidth,rawHeight)
    local plan=layout and layout:SecondaryResponsivePlan(rawWidth,rawHeight,self:GetMode())
    if not bounds or not plan then return nil end
    if plan.interactiveControlsFit and not bounds.interactiveControlsFit then
        bounds={contract="jlp-secondary-viewport-fit-v1",state="COMPACT",
            interactiveControlsFit=true,frameFitsScreen=true,projectionSafe=true,
            scale=plan.mapScale,scaledWidth=plan.contentWidth,
            scaledHeight=math.min(plan.contentHeight,rawHeight),persisted=false}
    end
    f.viewportFit=bounds
    f.responsivePlan=plan
    -- Alpha182 compatibility: keep the originally measured viewport policy.
    -- Actual card reflow takes priority for supported narrow viewports.
    local visible=plan.interactiveControlsFit
    local stacked=plan.stacked
    local contentW=stacked and plan.contentWidth or WIDTH
    local current=self:GetMode()
    local modeKey=current..":"..plan.state..":"..tostring(rawWidth)..":"..tostring(rawHeight)
    -- An unchanged layout is a pure no-op: map refreshes must not rebuild
    -- the entire card hierarchy every time the player position changes.
    -- Dynamic informational prose can gain lines without changing mode or
    -- viewport size; visible content-height changes must invalidate reflow.
    local dynamicSignature={}
    for _,view in pairs(f.views or {}) do
        for _,labelFrame in ipairs({view.materialPosition,view.materialDecision,view.materialDecisionList}) do
            if labelFrame and labelFrame.IsShown and labelFrame:IsShown() then
                local h=labelFrame.GetStringHeight and labelFrame:GetStringHeight() or 0
                dynamicSignature[#dynamicSignature+1]=tostring(math.floor(tonumber(h) or 0))
            end
        end
    end
    modeKey=modeKey..":"..table.concat(dynamicSignature,":")
    if f.layoutSignature==modeKey then return bounds end
    f.pageRoot:SetScale(1)
    f.pageRoot:SetSize(contentW,math.max(HEIGHT,plan.contentHeight))
    f.pageRoot:SetShown(visible)
    f.layoutWarning:SetShown(not visible)
    local main=f.views
    local all=main.overview.cards
    local wide=math.floor((WIDTH-2*GAP)/3)
    for i,key in ipairs(ORDER) do
        local card=all[key]
        local w=stacked and contentW or wide
        local x=stacked and 0 or (i-1)*(wide+GAP)
        local y=stacked and -(i-1)*(HEIGHT+GAP) or 0
        placeCard(card,main.overview,x,y,w,HEIGHT,1)
        for _,r in ipairs({card.skill,card.progress,card.current,card.sources}) do setRowWidth(r,w-44) end
        if card.note then card.note:SetWidth(w-44) end
        if card.action and card.action.SetWidth then card.action:SetWidth(math.min(w-48,340)) end
    end
    for _,key in ipairs({"COOKING","FIRST_AID","FISHING"}) do
        local view=main[key]
        local fishing=key=="FISHING"
        if stacked then
            local scale=fishing and plan.mapScale or 1
            local nativeW=fishing and 800 or contentW
            local step=HEIGHT*scale+GAP
            placeCard(view.primaryCard,view,0,0,nativeW,HEIGHT,scale)
            placeCard(view.secondaryCard,view,0,-step,nativeW,HEIGHT,scale)
            local usable=nativeW-44
            if fishing then
                for _,r in ipairs({view.skill,view.plan,view.sources,view.access,view.catchInfo}) do setRowWidth(r,usable) end
            else
                local leftRows=key=="COOKING" and {view.skill,view.route,view.coverage} or
                    {view.skill,view.plan,view.progress,view.rank}
                local rightRows=key=="COOKING" and {view.ingredients,view.sources,view.reference} or
                    {view.resources,view.sources}
                for _,r in ipairs(leftRows) do setRowWidth(r,usable) end
                for _,r in ipairs(rightRows) do setRowWidth(r,usable) end
                if view.note then view.note:SetWidth(usable) end
                if view.disclaimer then view.disclaimer:SetWidth(usable) end
            end
        else
            local leftW=fishing and 800 or 666
            local rightW=fishing and 264 or 398
            placeCard(view.primaryCard,view,0,0,leftW,HEIGHT,1)
            placeCard(view.secondaryCard,view,leftW+GAP,0,rightW,HEIGHT,1)
            if fishing then
                for _,r in ipairs({view.skill,view.plan,view.sources,view.access,view.catchInfo}) do setRowWidth(r,rightW-44) end
            else
                local leftRows=key=="COOKING" and {view.skill,view.route,view.coverage} or
                    {view.skill,view.plan,view.progress,view.rank}
                local rightRows=key=="COOKING" and {view.ingredients,view.sources,view.reference} or
                    {view.resources,view.sources}
                for _,r in ipairs(leftRows) do setRowWidth(r,leftW-44) end
                for _,r in ipairs(rightRows) do setRowWidth(r,rightW-44) end
                -- Cooking note belongs to the primary card; First Aid note
                -- belongs to the secondary card.  Width must be measured from
                -- the actual owning card, not the opposite column.
                if view.note then
                    view.note:SetWidth(key=="FIRST_AID" and rightW-48 or leftW-46)
                end
                if view.disclaimer then view.disclaimer:SetWidth(rightW-48) end
            end
        end
    end
    -- Resource picker remains parent-bound even when the Fishing card is
    -- scaled for a narrow secondary viewport. These are unscaled card units.
    local fishingView=main.FISHING
    local picker=fishingView and fishingView.nodePicker
    local host=fishingView and fishingView.mapContainer
    local geom=JLP:GetModule("GatheringViewportLayout")
    if picker and host and geom and type(geom.OverlayBudget)=="function" then
        local parentW=host.GetWidth and host:GetWidth() or 800
        local parentH=host.GetHeight and host:GetHeight() or HEIGHT
        local fit=geom:OverlayBudget(parentW,parentH,"EMBEDDED_PICKER")
        if picker.ClearAllPoints then picker:ClearAllPoints() end
        picker:SetPoint("TOPLEFT",host,"TOPLEFT",fit.left,-fit.top)
        picker:SetSize(fit.width,fit.height)
        if fishingView.pickerInfo and fishingView.pickerInfo.SetWidth then
            fishingView.pickerInfo:SetWidth(math.max(1,fit.width-36))
        end
        local previous=fishingView.pickerRowCount
        local previouslyFits=fishingView.pickerContentFits
        fishingView.pickerRowCount=fit.pickerRows or 0
        fishingView.pickerContentFits=fit.contentFits==true
        fishingView.pickerContentReason=fit.contentReason
        -- The visible resource slice and pager belong to the actual panel
        -- height. Refresh only if a shown picker changed row capacity.
        if (previous~=fishingView.pickerRowCount or previouslyFits~=fishingView.pickerContentFits) and picker.IsShown and
           picker:IsShown() and fishingView.UpdatePicker then
            fishingView:UpdatePicker()
        end
    end
    f.pageContentHeight=math.max(HEIGHT,plan.contentHeight)
    -- Reflow must not discard reading position when the mode is unchanged.
    if f.__scrollLayoutMode~=current then f.scrollOffset=0 end
    f.__scrollLayoutMode=current
    f.layoutSignature=modeKey
    f.scrollOffset=math.max(0,math.min(f.scrollOffset or 0, f.pageContentHeight-rawHeight))
    f:ScrollPage(0)
    local canScroll=visible and f.pageContentHeight>rawHeight+1
    if f.pageScrollbar then f.pageScrollbar:Refresh() end
    return bounds
end

-- Detached read-only sheets remain owned by Secondaries even though their
-- physical parent is UIParent. Page deactivation must clear visibility/state
-- before a new page's Refresh can run (including navigation to Bank/AH).
function Page:Deactivate()
    local views=self.frame and self.frame.views
    if not views then return end
    for _,key in ipairs({"COOKING","FIRST_AID"}) do
        local view=views[key]
        if view and view.materialSourceSheet then
            view.materialDetailsOpen=false
            view.materialSourceSheet:Reset()
        end
    end
end

function Page:SetMode(mode)
    -- Changing the active page closes tooltips owned by its old frame tree.
    -- This also applies when the route explanation tooltip was opened by click.
    if self.frame and JLP.UIInteraction and JLP.UIInteraction.HideTooltipTree then
        local previous=self.frame.views and self.frame.views[self.mode]
        if previous then JLP.UIInteraction:HideTooltipTree(previous) end
    end
    local nextMode=model() and model():ResolveMode(mode) or "overview"
    if self.frame and self.mode~=nextMode then
        for _,secondaryKey in ipairs({"COOKING","FIRST_AID"}) do
            local view=self.frame.views and self.frame.views[secondaryKey]
            if view and view.materialSourceSheet then
                view.materialDetailsOpen=false
                view.materialSourceSheet:Reset()
            end
        end
    end
    self.mode=nextMode
    if self.frame then
        for key,view in pairs(self.frame.views) do view:SetShown(key==self.mode) end
        self:ApplyViewportLayout()
    end
end
function Page:GetMode() return self.mode or "overview" end

function Page:Refresh()
    if not self.frame then return end
    self:ApplyViewportLayout()
    local svc=model()
    if not svc then return end
    local mode=self:GetMode()
    if mode=="overview" then
        for _,key in ipairs(ORDER) do
            local m=svc:GetSnapshot(key); local c=self.frame.views.overview.cards[key]
            if m and c then
                setRow(c.skill,skills(m))
                setRow(c.progress,m.levelingType)
                setRow(c.current,sourceBand(m))
                setRow(c.sources,m.secondaryPlan and materialPreview(m.secondaryPlan,1) or resources(m.band))
                c.note:SetText("Coverage: "..tostring(m.coverage)..". No native crafting enabled.")
            end
        end
        return
    end
    local m=svc:GetSnapshot(mode)
    if not m then return end
    local v=self.frame.views[mode]
    local active=m.band
    if mode=="COOKING" then
        setRow(v.skill,skills(m))
        setRow(v.route,sourceBand(m))
        setRow(v.coverage,"Wowhead Forever fish route 1-225 · estimated crafts")
        local plan=m.secondaryPlan
        local observedSkill=plan and plan.skill or 0
        if v.advancedSkill~=observedSkill then
            v.advancedPage=1
            v.advancedSkill=observedSkill
        end
        local preview,count,pages=self:AdvancedCookingPreview(plan,v.advancedPage)
        v.advancedPage=math.min(v.advancedPage or 1,math.max(1,pages))
        v.note:SetText((preview or gatePreview(plan))..". References only; no guaranteed skill-ups.")
        for _,item in ipairs({{v.advancedPrevious,v.advancedPage>1},
            {v.advancedNext,v.advancedPage<pages}}) do
            if item[1] then
                if item[1].SetShown then item[1]:SetShown(count>2) end
                if item[1].SetEnabled then item[1]:SetEnabled(item[2]) end
            end
        end
        applyMaterialPage(v,"COOKING",m.operationalPlan or plan)
        setRow(v.reference,(preview and (gatePreview(plan).." · ") or "")..
            "Wowhead Forever · Cooking 1–225 estimates, 225–300 references · read-only")
        if m.operationalPlan then
            local p=m.operationalPlan;local c=p.recommendedCurrentStep
            setRow(v.route,p.action or "Verify current Cooking state")
            setRow(v.coverage,"Cooking1–300 · qualified advisory casts; green boundary modeled")
            setRow(v.reference,c and c.secondaryAccess and c.secondaryAccess.status or "Current inputs/output/station require observation")
            v.note:SetText("Manual actions. Source geography is not current stock/access. Books, quests, rank, casts, outputs and skill-ups have separate receipts; Artisan guide remains untested in beta.")
        end
    elseif mode=="FISHING" then
        setRow(v.skill,skills(m))
        setRow(v.plan,bandName(active))
        setRow(v.sources,zones(active))
        local fishing=m.fishingGuide
        if fishing and #fishing.zones>0 then
            local bits={}
            for _,z in ipairs(fishing.zones) do
                bits[#bits+1]=z.name.." (min "..z.minSkill..", 100% "..z.guaranteedCatchSkill..")"
            end
            setRow(v.sources,table.concat(bits,"; "))
        end
        setRow(v.access,"Expert book125 (needed at150) · Artisan quest225 · current cap observed separately")
        if m.operationalPlan then
            local p=m.operationalPlan;local c=p.recommendedCurrentStep
            setRow(v.plan,p.action);setRow(v.access,c and c.secondaryAccess and c.secondaryAccess.status or c and c.materialSupply and (c.materialSupply.status.." · remaining "..tostring(c.materialSupply.quantity or "UNKNOWN"))or "Eligibility is not skill-up probability; no cast-count guarantee")
        end
        local fishingContext=JLP:GetModule("FishingSkillContext")
        local observedSkill=fishingContext and fishingContext:FromSnapshot(m)
        v.mapSkill:SetText(fishingContext and fishingContext:Describe(observedSkill) or ("Fishing progress: "..skills(m)))
        local map=JLP:GetModule("ForeverFishingMapCanvas")
        local current,reason=map and map:GetCurrentZone(m.skill,observedSkill and observedSkill.observedBonus)
        v.lastCurrentMapID=current and current.mapID or nil
        local browser=JLP:GetModule("ForeverFishingZoneBrowser")
        local choice=current and browser and browser:ResolveSelection(current,m.skill,observedSkill and observedSkill.observedBonus)
        local context=choice and choice.context or current
        -- Consume the one-shot manual intent BEFORE zone/mode work or a
        -- rendering exception can return early. Only the clicked map may be
        -- force-fetched; ordinary zone navigation is still an explicit refresh.
        local fetchIntent=JLP.UIWidgets and JLP.UIWidgets.GatheringMapFetchIntent and
            JLP.UIWidgets:GatheringMapFetchIntent(v.forceMapRefresh,v.manualArtRetryMapID,
                context and context.mapID)
        local forceArtForMap=fetchIntent and fetchIntent.forceArtFetch or
            (v.forceMapRefresh==true and v.manualArtRetryMapID==nil)
        v.manualArtRetryMapID=nil
        v.forceMapRefresh=false
        local retryDropped=fetchIntent and fetchIntent.dropped==true
        -- Position only applies to the actually occupied zone, never a remote map.
        local playerPosition=context and current and context.mapID==current.mapID and current.playerPosition or nil
        local zoneCount=fishing and fishing.zoneModel and #(fishing.zoneModel.tiers or {}) or 0
        if context then
            if v.lastMapID and v.lastMapID~=context.mapID then
                v.routeRequestSerial=(v.routeRequestSerial or 0)+1
                local route=JLP:GetModule("GatheringRouteService")
                if route and type(route.Cancel)=="function" then
                    local invoked,accepted,reason=pcall(route.Cancel,route,"CURRENT_ZONE_CHANGED")
                    if (not invoked or accepted~=true) and type(route.QuarantineUnconfirmedCancellation)=="function" then
                        pcall(route.QuarantineUnconfirmedCancellation,route,invoked and reason or "ROUTE_CANCEL_EXCEPTION")
                    end
                end
                v.routeFeedback=nil
                v.routeResult=nil
            end
            local count=choice and #choice.zones or 0
            local index=choice and choice.index
            v.mapStatus:SetText((choice and choice.browsing and "Selected zone: " or "Current zone: ")..context.name)
            if v.zonePrevious.SetEnabled then v.zonePrevious:SetEnabled(count>0) end
            if v.zoneNext.SetEnabled then v.zoneNext:SetEnabled(count>0) end
            v.zonePrevious:SetAlpha(count>0 and 1 or 0.45)
            v.zoneNext:SetAlpha(count>0 and 1 or 0.45)
            local requirement=context.fishingRequirement
            local retryZoneNotice=retryDropped and " · earlier map reload skipped (zone changed)" or ""
            if requirement then
                v.mapZone:SetText("Fishing requires "..requirement.minSkill.." · 100% catch at "..requirement.guaranteedCatchSkill..
                    " · "..(observedSkill and observedSkill.effectiveSkill==nil and "raw-only check (bonus unknown)" or
                    requirement.meetsMinimum and "accessible at observed skill" or "skill too low")..
                    (count>0 and (" · zone "..tostring(index or "-").."/"..count) or "")..retryZoneNotice)
            else
                v.mapZone:SetText(zoneCount.." sourced zone requirements · no exact rule for this map/subarea"..
                    (count>0 and (" · zone "..tostring(index or "-").."/"..count) or "")..retryZoneNotice)
            end
            if retryDropped and v.mapCaption then
                v.mapCaption:SetText("Previous Reload Map skipped · selected zone changed")
            end
            if v.retryMap then
                if v.retryMap.SetEnabled then v.retryMap:SetEnabled(true) end
                v.retryMap:SetAlpha(1)
            end
            local presentation=JLP:GetModule("GatheringMapViewService")
            if forceArtForMap or v.lastMapID~=context.mapID or not v.mapReady or
                (presentation and not presentation:IsTilePresentationCurrent(v.mapArt,context.mapID)) then
                local art,artReason=presentation and presentation:GetArt(context.mapID,forceArtForMap)
                local rendered,renderReason
                if art and presentation then
                    rendered,renderReason=presentation:RenderArt(v.mapArt,art,forceArtForMap)
                end
                v.mapReady=rendered==true
                v.lastArt=v.mapReady and art or nil
                if not v.mapReady then
                    -- Clearing a partially mutated native frame is best effort.
                    -- A broken Clear must not restore a READY presentation.
                    if map and type(map.Clear)=="function" then pcall(map.Clear,map,v.mapArt) end
                    local overlay=JLP:GetModule("GatheringMapOverlay")
                    if overlay and type(overlay.Clear)=="function" then pcall(overlay.Clear,overlay,v.mapArt) end
                end
                -- Consume the one-shot native art intent before later marker
                -- rendering can fail and return early from this Refresh.
                v.forceMapRefresh=false
                v.lastMapID=context.mapID
                local mapReason=renderReason or artReason or "ART_UNAVAILABLE"
                local failure=JLP.UIWidgets and JLP.UIWidgets.GatheringMapFailure and
                    JLP.UIWidgets:GatheringMapFailure(mapReason)
                v.mapCaption:SetText(v.mapReady and "Blizzard map art · Fishing: zone guidance only · gathering: historical pins" or
                    (failure and failure.title or "Map artwork unavailable"))
                if not v.mapReady and v.routeHint then
                    v.routeHint:SetText(failure and failure.detail or "Select another client-supported zone")
                end
                v.mapFallback:SetShown(not v.mapReady)
            end
            if v.retryMap then
                local action=JLP.UIWidgets and JLP.UIWidgets.GatheringMapRetryAction and
                    JLP.UIWidgets:GatheringMapRetryAction(true,v.mapReady)
                v.retryMap:SetText(action and action.label or (v.mapReady and "Reload Map" or "Retry Map"))
            end
            local controller=JLP:GetModule("GatheringMapLayerController")
            local overlay=JLP:GetModule("GatheringMapOverlay")
            local layerState=controller and controller:GetLayerState(context.mapID)
            local filterKey=nil
            if layerState then
                for _,entry in ipairs({{key="HERBALISM",button=v.herbLayer,name="Herbalism"},
                    {key="MINING",button=v.oreLayer,name="Mining"}}) do
                    local layer=layerState.layers[entry.key]
                    entry.button:SetText(entry.name..": "..(not layer.learned and "Not learned" or
                        layer.enabled and "On" or "Off"))
                    if entry.button.SetEnabled then entry.button:SetEnabled(layer.learned) end
                    entry.button:SetAlpha(layer.learned and 1 or 0.45)
                    if layer.enabled and not filterKey then filterKey=layer.resourceFilter end
                end
            end
            local selectedLayer=layerState and (layerState.layers.HERBALISM.enabled and layerState.layers.HERBALISM or
                layerState.layers.MINING.enabled and layerState.layers.MINING)
            if type(selectedLayer)~="table" then selectedLayer=nil end
            local state=JLP:GetModule("GatheringSharedMapState")
            local options=state and state:GetSnapshot()
            local smartMode=options and options.mode=="SMART_PROFESSION"
            local canFilter=not smartMode and selectedLayer~=nil and not selectedLayer.resourceSelection
            local selectedResource=selectedLayer and selectedLayer.resourceFilter
            local multi=selectedLayer and selectedLayer.resourceSelection
            local picks=0
            if multi then for _,value in pairs(multi) do if value then picks=picks+1 end end end
            v.resourceFilter:SetText(smartMode and "Resources: Smart" or
                multi and ("Nodes: "..picks.." selected") or
                ("Resource: "..(selectedResource and selectedResource:gsub("_"," ") or "All")))
            if v.resourceFilter.SetEnabled then v.resourceFilter:SetEnabled(canFilter) end
            v.resourceFilter:SetAlpha(canFilter and 1 or 0.45)
            local presentation=JLP:GetModule("GatheringMapViewService")
            local sharedView=presentation and presentation:Resolve(m.skill,0)
            local policy=JLP:GetModule("GatheringViewLayerPolicy")
            local fishingView=policy and policy:ForView(sharedView,"FISHING",v.includeGathering) or sharedView
            v.lastGatheringSnapshot=fishingView and fishingView.overlay or (controller and controller:BuildOverlay(context.mapID))
            local spatial=JLP:GetModule("GatheringSpatialAreaCatalog")
            v.lastSpatialSnapshot=spatial and spatial:GetMapSnapshot(context.mapID)
            -- Never carry a historical sector itinerary into a different
            -- map/filter/route shape or skill observation as a current plan.
            if v.fishingAreaPlan then
                local selected=state and state:GetSnapshot()
                local sector=v.fishingAreaPlan
                if sector.mapID~=context.mapID or
                    sector.filter~=(v.lastSpatialSnapshot and v.lastSpatialSnapshot.fishingAreaFilter) or
                    sector.selectedItemID~=(v.lastSpatialSnapshot and v.lastSpatialSnapshot.fishingSelectedItemID) or
                    sector.shape~=(selected and selected.routeShape) or
                    sector.rawFishingSkill~=(observedSkill and observedSkill.rawSkill) then
                    v.fishingAreaPlan=nil;v.fishingAdvice=nil
                end
            end
            if v.fishingFilter then
                local snap=v.lastSpatialSnapshot
                local focus=snap and snap.fishingAreaFilter or "ALL"
                local name="All"
                if focus=="COOKING_NEEDS" then name="Cooking needs"
                elseif focus=="SINGLE_FISH" then
                    name="Fish "..tostring(snap.fishingSelectedItemID or "?")
                    for _,fish in ipairs(JLP.data and JLP.data.fishingCatchAreaReference and
                        JLP.data.fishingCatchAreaReference.maps[context.mapID] or {}) do
                        if fish.itemID==snap.fishingSelectedItemID then name=fish.name;break end
                    end
                end
                v.fishingFilter:SetText("Fish: "..(#name>19 and name:sub(1,18).."…" or name).." ▾")
                if v.fishingFilter.SetEnabled then v.fishingFilter:SetEnabled(snap and snap.fishingLearned or false) end
            end
            if v.catchInfo then
                local snap=v.lastSpatialSnapshot
                local coverage=snap and snap.historicalCoverage
                local explanation=snap and snap.fishingExplanation
                local coverageNote=explanation and (" · "..tostring(explanation.sectors).." coarse sectors / "..tostring(explanation.historicalSamples).." past catches; not catch rate") or ""
                if v.fishingAdvice then
                    setRow(v.catchInfo,v.fishingAdvice)
                elseif snap and snap.fishingAreaFilter=="COOKING_NEEDS" then
                    setRow(v.catchInfo,"Cooking needs · "..tostring(snap.cookingNeedStatus)..
                        " · "..tostring(snap.eligibleFishCount).." matching fish"..coverageNote.." · guide estimates")
                elseif snap and snap.fishingAreaFilter=="SINGLE_FISH" then
                    setRow(v.catchInfo,table.concat(snap.selectedFishNames or {},", ")..coverageNote.." · historical only")
                elseif snap and snap.fishCount>0 then
                    local shown={}
                    for i=1,math.min(3,#snap.fishNames) do shown[#shown+1]=snap.fishNames[i] end
                    setRow(v.catchInfo,table.concat(shown,", ")..(snap.fishCount>3 and (" +"..(snap.fishCount-3).." others") or "").." · historical only")
                else
                    setRow(v.catchInfo,"No documented historical catches in this zone")
                end
            end
            if v.catchInfo and v.catchInfo.value and v.catchInfo.value.GetText then
                local info=v.catchInfo.value:GetText()
                if type(info)=="string" and #info>67 then v.catchInfo.value:SetText(info:sub(1,64).."…") end
            end
            local spatialLearned=v.lastSpatialSnapshot and v.lastSpatialSnapshot.fishingLearned
            v.fishingAreas:SetText("Fishing areas: "..(not spatialLearned and "Not learned" or
                (options and options.showFishingAreas) and "On" or "Off"))
            if v.fishingAreas.SetEnabled then v.fishingAreas:SetEnabled(spatialLearned or false) end
            v.fishingAreas:SetAlpha(spatialLearned and 1 or 0.45)
            v.lastPlayerPosition=sharedView and sharedView.playerPosition or playerPosition
            local service=JLP:GetModule("GatheringRouteService")
            local routes,routeStatus=service and service:GetRoutes(context.mapID)
            v.lastRouteSnapshot=fishingView and fishingView.routeSnapshot or
                (not fishingView and routes and {mapID=context.mapID,routes=routes} or nil)
            if v.focusRoute then
                local eligible=routeStatus=="READY" and v.mapReady and v.lastRouteSnapshot~=nil
                if v.focusRoute.SetEnabled then v.focusRoute:SetEnabled(eligible==true) end
                v.focusRoute:SetAlpha(eligible and 1 or 0.45)
            end
            v.loopShape:SetText("Shape: "..(options and options.routeShape=="FROM_PLAYER" and "From Player" or "Loop"))
            v.routeMode:SetText(options and options.mode=="SMART_PROFESSION" and "Mode: Smart Profession" or "Mode: Custom Loop")
            v.smartFocus:SetText("Focus: "..(options and options.focus or "BALANCED"))
            v.smartFocus:SetAlpha(options and options.mode=="SMART_PROFESSION" and 1 or 0.45)
            v.nodePickerButton:SetAlpha(smartMode and 0.45 or 1)
            if v.nodePickerButton.SetEnabled then v.nodePickerButton:SetEnabled(not smartMode) end
            local routeUI=JLP:GetModule("GatheringRoutePresentation")
            routeUI=routeUI and routeUI:Build(context.mapID)
            -- One embedded subscriber per route-owner/map. Re-registering on
            -- every UI Refresh invalidates an in-flight publication. An
            -- accepted READY event must repaint the CURRENT visible canvas;
            -- setting the caption alone leaves stale Route Information.
            if service and type(service.SetProgressObserver)=="function" and
                (v._observedRouter~=service or v._observedMapID~=context.mapID) then
                local mapID=context.mapID
                v._observedRouter=service
                v._observedMapID=mapID
                service:SetProgressObserver("EMBEDDED",function(receipt)
                    if not v or not v.mapCaption or v.lastMapID~=mapID or
                        receipt.mapID~=mapID or type(v._routeProgressToken)~="string" or
                        v._routeProgressToken=="" or
                        service:GetContextToken(mapID)~=v._routeProgressToken or
                        (v.IsShown and not v:IsShown()) then return end
                    if receipt.status=="GENERATING" then
                        local text=JLP.UIWidgets and JLP.UIWidgets.GatheringProgressLabel and
                            JLP.UIWidgets:GatheringProgressLabel(receipt) or "Planning route…"
                        v.mapCaption:SetText(text)
                    elseif receipt.committed then
                        local token=v._routeProgressToken
                        if v._lastReadyRenderToken~=token and not v._refreshingReadyRoute then
                            v._lastReadyRenderToken=token
                            v._refreshingReadyRoute=true
                            local ok=pcall(Page.Refresh,Page)
                            v._refreshingReadyRoute=false
                            if not ok then
                                v.lastOverlayReceipt=nil
                                v.mapCaption:SetText("Route ready · map presentation failed; Retry Map")
                            end
                        end
                    else
                        v.lastOverlayReceipt=nil
                        local W=JLP.UIWidgets
                        local label=W and W.GatheringLifecycleReceipt and
                            W:GatheringLifecycleReceipt(service,mapID,receipt.status)
                        v.mapCaption:SetText(label and label.text or "Route result unavailable")
                    end
                end)
            end
            v._routeProgressToken=service and service.GetContextToken and
                service:GetContextToken(context.mapID) or nil
            v.generateLoop:SetText(routeUI and routeUI.primaryLabel or
                (smartMode and "Generate Smart" or "Generate Loop"))
            local allowGenerate=v.includeGathering and routeUI and routeUI.canGenerate~=false
            if v.generateLoop.SetEnabled then v.generateLoop:SetEnabled(allowGenerate==true) end
            v.generateLoop:SetAlpha(allowGenerate and 1 or 0.45)
            if v.generateLoop.SetActiveState and v.generateLoop.__jlpActiveState~=allowGenerate then
                v.generateLoop:SetActiveState(allowGenerate==true)
            end
            local allowClear=v.includeGathering and routeUI and routeUI.canClear
            v.clearLoop:SetText(routeUI and routeUI.workflow=="GENERATING" and "Cancel Route" or "Clear Route")
            if v.clearLoop.SetEnabled then v.clearLoop:SetEnabled(allowClear==true) end
            v.clearLoop:SetAlpha(allowClear and 1 or 0.45)
            v.sourceLayer:SetText(options and options.sourceFilter=="OBSERVED_ONLY" and
                "Pins: Mine" or "Pins: All")
            v.routeSources:SetText("Route nodes: "..(options and options.routeSource=="OBSERVED_ONLY" and "Observed" or
                options and options.routeSource=="PREFER_OBSERVED" and "Prefer observed" or "All"))
            -- Pin visibility and route input are independent user decisions.
            -- Observed means historical personal evidence, never live spawns.
            if v.UpdatePicker then v:UpdatePicker() end
            if v.mapReady and v.lastArt then
                -- The embedded canvas has already laid out its map art.
                -- Preserve only a generations-bound PRESENTED receipt here;
                -- nil CPU is deliberate (this call measures neither full map
                -- art+overlay work nor native WoW frame time).
                local renderToken=service and service.GetContextToken and
                    service:GetContextToken(context.mapID) or nil
                local paintOK,stats=pcall(function()
                    return overlay and overlay:Render(v.mapArt,v.lastArt,v.lastGatheringSnapshot,map,v.lastRouteSnapshot,v.lastSpatialSnapshot)
                end)
                if not paintOK or type(stats)~="table" or stats.status=="MAP_MISMATCH" then
                    -- A partially painted or source-mismatched overlay may not be reused as READY.
                    v.mapReady=false
                    v.mapArt.__jlpTileArtKey=nil;v.mapArt.__jlpTileViewportKey=nil
                    if map and type(map.Clear)=="function" then pcall(map.Clear,map,v.mapArt) end
                    if overlay and type(overlay.Clear)=="function" then pcall(overlay.Clear,overlay,v.mapArt) end
                    v.mapFallback:SetShown(true)
                    v.mapCaption:SetText("Map overlay unavailable · retry when art is available")
                    v.routeHint:SetText("Historical pins and route preview cannot be displayed safely")
                    if v.retryMap then v.retryMap:SetText("Retry Map") end
                    v.forceMapRefresh=false
                    return
                end
                local submittedRoute=false
                if routeStatus=="READY" and type(v.lastRouteSnapshot)=="table" and
                    v.lastRouteSnapshot.mapID==context.mapID and
                    type(v.lastRouteSnapshot.routes)=="table" then
                    for _,candidate in pairs(v.lastRouteSnapshot.routes) do
                        if type(candidate)=="table" and type(candidate.points)=="table" and
                            #candidate.points>0 then submittedRoute=true;break end
                    end
                end
                local strokeCount=type(stats.routeStrokes)=="number" and stats.routeStrokes or 0
                v.lastRouteStrokesSubmitted=strokeCount
                local acceptedOverlayReceipt=false
                if service and type(service.MarkOverlayPresented)=="function" and
                    type(renderToken)=="string" and renderToken~="" and submittedRoute and
                    strokeCount>0 and stats.status~="MAP_MISMATCH" then
                    local receiptOK,accepted=pcall(service.MarkOverlayPresented,service,
                        context.mapID,renderToken,nil,true)
                    acceptedOverlayReceipt=receiptOK and accepted==true
                end
                v.lastOverlayReceipt=acceptedOverlayReceipt and
                    {mapID=context.mapID,token=renderToken,strokes=strokeCount} or nil
                local journey=JLP:GetModule("GatheringRouteJourney")
                v.lastRouteJourney=journey and journey:Inspect(context.mapID,{
                    visible=v.mapArt and v.mapArt.IsVisible and v.mapArt:IsVisible()==true,
                    routeSubmitted=submittedRoute,strokes=strokeCount,
                    receipt=v.lastOverlayReceipt}) or nil
                local layerText=stats and stats.total>0 and
                    (" · gathering refs/pins: "..stats.visible.." shown / "..stats.total.." locations"..
                        " · personal: "..tostring(stats.personallyObserved or 0)) or
                    " · no enabled gathering references"
                local lifecycle=JLP.UIWidgets and JLP.UIWidgets.GatheringLifecycleReceipt and
                    JLP.UIWidgets:GatheringLifecycleReceipt(service,context.mapID,routeStatus)
                local routeText=routeStatus=="READY" and
                    ((submittedRoute and strokeCount==0) and
                        " · no route lines in viewport; Map Options > Show Route" or
                    acceptedOverlayReceipt and (lifecycle and lifecycle.presentation=="MAP_RENDER_PRESENTED") and
                        " · advisory route presented (map art + overlay; CPU UNKNOWN)" or
                        " · route READY; map presentation pending") or
                    routeStatus=="GENERATING" and " · Planning route…" or
                    (v.routeFeedback and (" · "..v.routeFeedback)) or
                    (lifecycle and (" · "..lifecycle.text)) or ""
                local fishText=v.lastSpatialSnapshot and (" · Fishing historical areas "..tostring(stats and stats.fishingSectors or 0)..
                    "/"..tostring(v.lastSpatialSnapshot.areaCount or 0).." · Skinning: no verified areas"..
                    ((v.lastSpatialSnapshot.skinningLeadCount or 0)>0 and (" ("..tostring(v.lastSpatialSnapshot.skinningLeadCount).." research leads)") or "")..
                    ((v.lastSpatialSnapshot.skinningMobIdentityCount or 0)>0 and (" · "..tostring(v.lastSpatialSnapshot.skinningMobIdentityCount).." NPC Skinning tabs, no verified areas") or "")..
                    (JLP:GetModule("SkinningMaterialIntelligence") and
                     (" · "..tostring(JLP:GetModule("SkinningMaterialIntelligence"):GetCoverage().materialCount).." leather item research only") or "")) or ""
                local explanation=JLP:GetModule("GatheringOutputExplanation")
                local explained=smartMode and routeStatus=="READY" and
                    explanation and explanation:RouteHeadline(routes) or nil
                local rationale=routeUI and routeUI.action or (JLP.UIWidgets.GatheringLegend and
                    JLP.UIWidgets:GatheringLegend().short or "Historical positions only")
                if explained then rationale=rationale.."\n"..explained end
                local evidence=JLP.UIWidgets and JLP.UIWidgets.GatheringRouteEvidence and
                    JLP.UIWidgets:GatheringRouteEvidence(v.lastGatheringSnapshot,routeUI and routeUI.workflow,options,context.mapID)
                if evidence then rationale=rationale.."\n"..evidence.title.." · "..evidence.detail.."\n"..evidence.context end
                local changed=v.fullRouteRationale~=rationale
                v.fullRouteRationale=rationale
                if changed and v.explanationPopup and v.explanationPopup:IsShown() then
                    v.whyRoutePage=1;v:RefreshExplanationPages()
                end
                local pages=JLP:GetModule("GatheringRouteExplanation")
                local preview=pages and pages:Pages(rationale,42,2) or {rationale}
                local joined=journey and v.lastRouteJourney and
                    journey:Summary(v.lastRouteJourney) or nil
                v.mapRationale:SetText((joined and (joined.."\n") or "")..
                    (preview[1] or "Route source details unavailable"))
                local resultModule=JLP:GetModule("GatheringRouteResult")
                local routeService=JLP:GetModule("GatheringRouteService")
                Page:InvalidateRouteReceipt(v,context.mapID,options)
                if v.routeResult and routeUI and
                    (v.routeResult.phase=="GENERATING" or v.routeResult.phase=="READY") and
                    (routeUI.workflow=="READY" or routeUI.workflow=="GENERATING") then
                    local latest=resultModule and resultModule:FromStatus(routeUI.status)
                    if latest then
                        if resultModule.Bind then resultModule:Bind(latest,context.mapID,routeService) end
                        latest.mode=options and options.mode or nil
                        v.routeResult=latest;v.routeFeedback=latest.message
                    end
                end
                v.mapCaption:SetText(routeStatus=="GENERATING" and lifecycle and lifecycle.text or
                    v.routeFeedback or (not v.includeGathering and
                    "Fishing catch areas · no verified fishing pool positions" or
                    (tostring(stats and stats.visible or 0).." gathering refs · "..
                        (routeUI and routeUI.header or "No active gathering route"))))
                local phase=routeUI and routeUI.workflow=="GENERATING" and
                    JLP.UIWidgets and JLP.UIWidgets.GatheringPhaseLabel and
                    JLP.UIWidgets:GatheringPhaseLabel(routeService,context.mapID) or nil
                v.routeHint:SetText((routeStatus=="READY" and submittedRoute and strokeCount==0) and
                    "Route computed, but no route strokes submitted · Map Options > Show Route" or
                    (phase and phase.text or (v.routeResult and v.routeResult.detail or
                    (not v.includeGathering and "Select Herb/Ore overlays explicitly for gathering routes" or
                    (routeUI and routeUI.detail or "Choose Custom resources or a Smart goal")))))
            elseif overlay then
                overlay:Clear(v.mapArt)
            end
            if v.mapReady and v.lastArt then
                if playerPosition then map:PlacePlayerMarker(v.mapArt,v.lastArt,playerPosition)
                else map:HidePlayerMarker(v.mapArt) end
            end
        else
            if map then map:Clear(v.mapArt) end
            local overlay=JLP:GetModule("GatheringMapOverlay")
            if overlay then overlay:Clear(v.mapArt) end
            v.lastGatheringSnapshot=nil;v.lastRouteSnapshot=nil;v.lastSpatialSnapshot=nil
            if v.catchInfo then setRow(v.catchInfo,"Selected zone unavailable") end
            local route=JLP:GetModule("GatheringRouteService")
            if route and type(route.Cancel)=="function" then
                local invoked,accepted,reason=pcall(route.Cancel,route,"MAP_UNAVAILABLE")
                if (not invoked or accepted~=true) and type(route.QuarantineUnconfirmedCancellation)=="function" then
                    pcall(route.QuarantineUnconfirmedCancellation,route,invoked and reason or "ROUTE_CANCEL_EXCEPTION")
                end
            end
            v.routeFeedback=nil
            v.mapReady=false; v.lastMapID=nil; v.lastArt=nil;v.lastPlayerPosition=nil
            if v.retryMap then
                local action=JLP.UIWidgets and JLP.UIWidgets.GatheringMapRetryAction and
                    JLP.UIWidgets:GatheringMapRetryAction(false,false)
                v.retryMap:SetText(action and action.label or "Choose Zone")
                if v.retryMap.SetEnabled then v.retryMap:SetEnabled(false) end
                v.retryMap:SetAlpha(0.45)
            end
            if v.zonePrevious.SetEnabled then v.zonePrevious:SetEnabled(false) end
            if v.zoneNext.SetEnabled then v.zoneNext:SetEnabled(false) end
            v.zonePrevious:SetAlpha(0.45);v.zoneNext:SetAlpha(0.45)
            v.mapStatus:SetText("Mini-zone map · waiting for Blizzard map data")
            v.mapCaption:SetText("Blizzard map data unavailable")
            v.routeHint:SetText("Choose a client-supported zone and try again")
            v.mapZone:SetText("Guide area: "..zones(active).." · "..zoneCount.." sourced requirements")
            v.mapFallback:Show()
        end
        v.forceMapRefresh=false
        -- The standalone viewport does not own filters, selected map or routes.
        if JLP.StandaloneGatheringMap and JLP.StandaloneGatheringMap:IsShown() then
            JLP.StandaloneGatheringMap:Refresh()
        end
    elseif mode=="FIRST_AID" then
        setRow(v.skill,skills(m))
        setRow(v.plan,sourceBand(m))
        setRow(v.progress,"Wowhead Forever First Aid 1-225 · estimated crafts")
        setRow(v.rank,gatePreview(m.secondaryPlan))
        applyMaterialPage(v,"FIRST_AID",m.operationalPlan or m.secondaryPlan)
        -- Preserve the established acquisition context while showing the
        -- current, qualified material as the primary source. Generic items
        -- below are conditional, never an automatic purchase/withdrawal.
        if v.sources and v.sources.value then
            v.sources.value:SetText(v.sources.value:GetText()..
                " · herbs/cloth/vials/spices only where recipe-qualified; manual supply")
        end
        local faPlan=m.secondaryPlan
        if faPlan and (faPlan.skill or 0)>=225 then
            v.note:SetText("225-300 reference only: recipes, learning, quest and output must be verified; skill-ups/craft counts UNKNOWN. No auto-travel/craft.")
        else
            v.note:SetText("Forever 1-225 bandage route: material/craft totals are guide estimates, not guaranteed skill-ups. 225-300 unqualified.")
        end
        if m.operationalPlan then
            local p=m.operationalPlan;local c=p.recommendedCurrentStep
            setRow(v.plan,p.action or "Verify current First Aid state")
            setRow(v.progress,"First Aid1–300 · qualified advisory scenarios; casts are not observed skill-ups")
            setRow(v.rank,c and c.firstAidAccess and c.firstAidAccess.status or "Observed cap "..tostring(m.maxSkill))
            local materialText={}
            for _,r in ipairs(c and c.materials or {})do materialText[#materialText+1]=tostring(r.name or r.itemID)..": "..tostring(r.batchRequired or r.required or r.perCraft).." required; missing "..tostring(r.missing or "UNKNOWN")end
            setRow(v.sources,table.concat(materialText," · "))
            v.note:SetText("Manual actions only. Books, quest, cloth delivery, learning, rank, casts, outputs and skill-ups require separate observations; current offers/spawns remain unverified until observed.")
        end
        self:LayoutFirstAidDetails(v)
    end
end

JLP.UIPages=JLP.UIPages or {}
JLP.UIPages[Page.name]=Page
