local _,JLP=...
local Page={name="History",offset=0,pageSize=9}
local function label(row)
    local tm=type(date)=="function" and date("%Y-%m-%d %H:%M",tonumber(row.finishedAt) or 0) or "Time UNKNOWN"
    local strategy=row.strategy=="normal" and "Economical" or
        row.strategy=="aggressive" and "Fastest" or "Strategy unknown"
    if row.status=="observed_result" then
        return string.format("%s | %s | %s | Observed client craft result: item %s x%s | Not a verified craft count or skill-up",
            tm,tostring(row.key or "?"),tostring(row.recipeName or "Unknown recipe"),
            tostring(row.outputItemID or "?"),tostring(row.outputQuantity or "?"))
    end
    local output=""
    if tonumber(row.observedOutputEvents or 0)>0 then
        output=" | "..tostring(row.observedOutputEvents).." associated item-result event(s), yield not ordinal-qualified"
    end
    return string.format("%s | %s | %s | %s | %s | %d/%d · View recipe%s",
        tm,tostring(row.key or "?"),tostring(row.recipeName or "Unknown recipe"),
        strategy,tostring(row.status or "UNVERIFIED"),row.confirmedCount or 0,row.requestedCount or 0,output)
end
function Page:OpenRecipe(row)
    if type(row)~="table" then return false,"HISTORY_ROW_UNAVAILABLE" end
    if row.status=="observed_result" then
        self.selectedHistory=row
        if self.frame and self.frame.card and self.frame.card.selection then
            self.frame.card.selection:SetText("Observed result: "..tostring(row.recipeName or "Unknown")..
                " · item "..tostring(row.outputItemID or "?").." x"..tostring(row.outputQuantity or "?")..
                ". Client events correlated; craft count/skill-up unverified. Read-only.")
        end
        return true,"OBSERVED_RESULT_READONLY"
    end
    local planner=JLP:GetModule("Planner")
    local key=row.key
    local inventory=JLP:GetModule("Inventory")
    local owner=inventory and inventory.GetCharacterKey and inventory:GetCharacterKey() or nil
    if type(owner)~="string" or owner=="" or owner=="OWNER_UNKNOWN" then
        return false,"OWNER_UNKNOWN" end
    local plan=planner and planner.GetProfessionPlan and planner:GetProfessionPlan(key) or nil
    if not plan or plan.actionKind~="craft" or not plan.step or plan.step.recipe~=row.recipeName or
        (row.recipeID and tonumber(plan.step.recipeID) and tonumber(row.recipeID)~=tonumber(plan.step.recipeID)) then
        -- Historical observation is real evidence of a past transaction, but
        -- cannot authorize a recipe from an outdated current plan. Show the
        -- selected historical receipt on this page without switching recipes.
        self.selectedHistory=row
        if self.frame and self.frame.card and self.frame.card.selection then
            self.frame.card.selection:SetText("Historical receipt · "..tostring(row.recipeName or "Unknown")..
                " · "..tostring(row.status or "UNKNOWN")..
                " · "..tostring(row.confirmedCount or 0).." confirmed. "..
                "Open Profession Guide to inspect current source qualification; no craft started.")
        end
        return true,"HISTORICAL_READONLY_ONLY"
    end
    local main=JLP.MainWindow
    if not main or not main.ShowGuideMode then return false,"GUIDE_UNAVAILABLE" end
    main:ShowGuideMode(key)
    return true,"READ_ONLY_CURRENT_RECIPE"
end
function Page:Create(parent)
    if self.frame then return self.frame end
    local W=JLP.UIWidgets
    local root=CreateFrame("Frame",nil,parent);root:SetAllPoints()
    local card=W:Card(root,"Crafting History (guarded + observed, 70450)")
    card:SetPoint("TOPLEFT",0,0);card:SetPoint("BOTTOMRIGHT",0,0)
    local header=W:Body(card)
    header:SetPoint("TOPLEFT",20,-64);header:SetPoint("TOPRIGHT",-20,-64)
    header:SetHeight(40);header:SetText("Read-only guarded transactions and build-labeled client results. Item quantities are not counts of confirmed crafts.")
    card.entries={}
    for i=1,self.pageSize do
        local row=W:Button(card,"",420);row:SetHeight(36)
        row:SetPoint("TOPLEFT",20,-110-(i-1)*43)
        row:SetPoint("RIGHT",card,"RIGHT",-20,0)
        row:SetScript("OnEnter",function(self)
            if not self.__historyRecord or not GameTooltip then return end
            GameTooltip:SetOwner(self,"ANCHOR_CURSOR")
            GameTooltip:SetText(label(self.__historyRecord))
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function(self)
            if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self) end
        end)
        row:SetScript("OnClick",function(self)
            local ok,why=Page:OpenRecipe(self.__historyRecord)
            if not ok and JLP.Print then JLP:Print(why) end
        end)
        card.entries[i]=row
    end
    card.selection=W:Body(card)
    card.selection:SetPoint("BOTTOMLEFT",20,62)
    card.selection:SetPoint("BOTTOMRIGHT",-20,62)
    card.selection:SetHeight(45)
    card.selection:SetText("Choose a historical transaction to inspect its receipt. Native replay is disabled.")
    card.previous=W:Button(card,"Previous",100);card.previous:SetPoint("BOTTOMLEFT",20,22)
    card.next=W:Button(card,"Next",100);card.next:SetPoint("LEFT",card.previous,"RIGHT",10,0)
    card.page=W:Body(card);card.page:SetPoint("LEFT",card.next,"RIGHT",15,0)
    card.previous:SetScript("OnClick",function() Page.offset=math.max(0,Page.offset-Page.pageSize);Page:Refresh() end)
    card.next:SetScript("OnClick",function() Page.offset=Page.offset+Page.pageSize;Page:Refresh() end)
    root.card=card;self.frame=root
    if root.SetScript then root:SetScript("OnSizeChanged",function() Page:ApplyLayout() end) end
    self:ApplyLayout()
    return root
end
function Page:ApplyLayout()
    local root=self.frame
    if not (root and root.card) then return false end
    local h=tonumber(root.GetHeight and root:GetHeight()) or 636
    local w=tonumber(root.GetWidth and root:GetWidth()) or 1078
    local rows=math.max(1,math.min(#root.card.entries,math.floor((h-270)/43)+1))
    self.pageSize=rows
    root.card.selection:SetWidth(math.max(180,w-40))
    for i,button in ipairs(root.card.entries) do
        if i>rows then button:Hide() end
    end
    return true
end
function Page:Refresh()
    if not self.frame then return end
    self:ApplyLayout()
    local history=JLP:GetModule("CraftHistoryIntegration70374")
    local rows=history and history.GetHistory and history:GetHistory(100) or {}
    self.offset=math.min(self.offset,math.max(0,math.ceil(#rows/self.pageSize-1)*self.pageSize))
    local c=self.frame.card
    for i,b in ipairs(c.entries) do
        local row=rows[i+self.offset];b.__historyRecord=row
        b:SetShown(i<=self.pageSize and row~=nil)
        if row then
            local recipe=tostring(row.recipeName or "Unknown recipe")
            local bounded=JLP.UIWidgets and JLP.UIWidgets.BoundedUTF8Label
            if type(bounded)=="function" then recipe=JLP.UIWidgets:BoundedUTF8Label(recipe,48) end
            if row.status=="observed_result" then
                b:SetText(tostring(row.key or "?").." · "..recipe.." · OBSERVED OUTPUT "..
                    tostring(row.outputItemID or "?").." x"..tostring(row.outputQuantity or "?"))
            else
                local output=tonumber(row.observedOutputEvents or 0)>0 and
                    (" · "..tostring(row.observedOutputEvents).." observed item result(s)") or ""
                b:SetText(tostring(row.key or "?").." · "..recipe.." · "..
                    tostring(row.status or "UNVERIFIED").." · "..
                    tostring(row.confirmedCount or 0).."/"..tostring(row.requestedCount or 0)..output)
            end
        end
    end
    if #rows==0 and c.selection and not self.selectedHistory then
        c.selection:SetText("No qualified crafting transactions for this character yet. History never starts native crafting.")
    end
    c.page:SetText(string.format("%d-%d / %d",#rows>0 and self.offset+1 or 0,
        math.min(#rows,self.offset+self.pageSize),#rows))
    if c.previous.SetEnabled then c.previous:SetEnabled(self.offset>0) end
    if c.next.SetEnabled then c.next:SetEnabled(self.offset+self.pageSize<#rows) end
end
JLP.UIPages=JLP.UIPages or {};JLP.UIPages[Page.name]=Page
