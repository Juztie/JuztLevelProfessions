local _, JLP = ...
local Page={name="Settings"}

function Page:Create(parent)
    if self.frame then return self.viewport or self.frame end
    local W=JLP.UIWidgets
    local width=parent.GetWidth and parent:GetWidth() or 1078
    local height=parent.GetHeight and parent:GetHeight() or 636
    if not width or width<=0 then width=1078 end
    if not height or height<=0 then height=636 end
    local viewport=JLP.UILayout:ScrollArea(parent,{width=width,height=height,
        contentWidth=width-12,scrollbarGutter=12,wheelStep=42})
    viewport:SetPoint("TOPLEFT",parent,"TOPLEFT",0,0)
    viewport:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",0,0)
    local f=viewport.content
    self.viewport=viewport
    local card=W:Card(f,"Planner Strategy")
    card:SetPoint("TOPLEFT",0,0); card:SetPoint("TOPRIGHT",0,0); card:SetHeight(435)
    card.body=W:Body(card); card.body:SetPoint("TOPLEFT",20,-62); card.body:SetPoint("TOPRIGHT",-20,-62); card.body:SetHeight(75)
    local labels={{"Fastest","fastest"},{"Economical","economical"},{"Self-found","self_found"}}
    card.buttons={}
    for i,row in ipairs(labels) do
        local b=W:Button(card,row[1],150); b:SetPoint("TOPLEFT",20+(i-1)*170,-132)
        b:SetScript("OnClick",function()
            if JLP.DB and JLP.DB.profile then JLP.DB.profile.strategy=row[2] end
            JLP.EventBus:Emit("SETTINGS_CHANGED")
            Page:Refresh()
        end)
        card.buttons[i]={button=b,key=row[2]}
    end
    card.trackerToggles={}
    card.trackerPlacement=W:Button(card,"Objective position: AUTO",235)
    card.trackerPlacement:SetScript("OnClick",function()
        local tracker=JLP.ObjectiveStepTracker
        if tracker then
            local current=tracker:GetPlacement()
            local nextMode=current=="AUTO" and "ABOVE" or current=="ABOVE" and "LEFT" or "AUTO"
            tracker:SetPlacement(nextMode)
            Page:Refresh()
        end
    end)
    local registry=JLP:GetModule("ProfessionRegistry")
    local professions=registry and registry:GetKeys() or {}
    local title=W:Body(card)
    title:SetPoint("TOPLEFT",20,-193);title:SetWidth(650)
    title:SetText("Current Step overlay · read-only panel above or left of Blizzard Objective Tracker (native tracker unchanged)")
    card.trackerTitle=title
    for i,key in ipairs(professions) do
        local button=W:Button(card,key..": OFF",205)
        button:SetPoint("TOPLEFT",20+((i-1)%3)*224,-225-math.floor((i-1)/3)*43)
        button:SetScript("OnClick",function()
            local tracker=JLP.ObjectiveStepTracker
            if tracker then tracker:SetEnabled(key,not tracker:IsEnabled(key)) end
            Page:Refresh()
        end)
        card.trackerToggles[#card.trackerToggles+1]={button=button,key=key}
    end
    -- The standalone JuztTom design is embedded as a complete internal
    -- modal window. No duplicate HUD setting is kept in JuztLevel Settings.
    local navigation=W:Card(f,"JuztTom Navigation")
    navigation:SetPoint("TOPLEFT",card,"BOTTOMLEFT",0,-12)
    navigation:SetPoint("TOPRIGHT",card,"BOTTOMRIGHT",0,-12)
    navigation:SetHeight(150)
    navigation.note=W:Body(navigation)
    navigation.note:SetText("JuztTom and JuztTravel are integrated JuztLevel modules. Open the complete JuztTom window to adjust navigation, appearance, behaviour and advanced settings.")
    navigation.note:SetHeight(50)
    navigation.button=W:Button(navigation,"JuztTom Settings",228)
    navigation.button:SetHeight(33)
    navigation.button:SetScript("OnClick",function()
        local tom=JLP:GetModule("IntegratedJuztTom")
        if tom and tom.OpenSettings then
            local ok,reason=tom:OpenSettings()
            if not ok and JLP.Print then JLP:Print("JuztTom UI: "..tostring(reason)) end
        elseif JLP.Print then JLP:Print("JuztTom module unavailable") end
    end)
    f.navigation=navigation
    f.card=card; self.frame=f
    if viewport.SetScript then viewport:SetScript("OnSizeChanged",function() Page:ApplyLayout() end) end
    self:ApplyLayout()
    return viewport
end
function Page:ApplyLayout()
    if self.__applyingLayout then return false end
    local f=self.frame
    if not (f and f.card) then return false end
    local viewport=self.viewport
    local outerWidth=tonumber(viewport and viewport.GetWidth and viewport:GetWidth()) or 1078
    local outerHeight=tonumber(viewport and viewport.GetHeight and viewport:GetHeight()) or 636
    if outerWidth<=0 then outerWidth=1078 end
    if outerHeight<=0 then outerHeight=636 end
    local w=math.max(1,outerWidth-12)
    local strategyCols=math.max(1,math.min(3,math.floor((w-40+10)/170)))
    local toggleCols=math.max(1,math.min(3,math.floor((w-40+19)/224)))
    local cols=strategyCols
    -- Compact strategy prose may wrap onto five or more lines. The strategy
    -- controls, tracker heading and tracker toggles form sequential bands.
    local compact=w<465
    if f.card.body and f.card.body.SetHeight then
        f.card.body:SetHeight(compact and 116 or 62)
    end
    local strategyTop=compact and 182 or 132
    local buttons=f.card.buttons
    for i,entry in ipairs(buttons) do
        local b=entry.button
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT",f.card,"TOPLEFT",20+((i-1)%cols)*170,
            -strategyTop-math.floor((i-1)/cols)*43)
    end
    local titleTop=strategyTop+math.ceil(#buttons/cols)*43+18
    local placementTop=titleTop+(compact and 53 or 38)
    local toggleTop=placementTop+40
    if f.card.trackerPlacement then
        f.card.trackerPlacement:SetWidth(math.max(1,math.min(235,w-40)))
        f.card.trackerPlacement:ClearAllPoints()
        f.card.trackerPlacement:SetPoint("TOPLEFT",f.card,"TOPLEFT",20,-placementTop)
    end
    if f.card.trackerTitle then
        f.card.trackerTitle:ClearAllPoints()
        f.card.trackerTitle:SetPoint("TOPLEFT",f.card,"TOPLEFT",20,-titleTop)
        f.card.trackerTitle:SetWidth(math.max(150,w-40))
        if f.card.trackerTitle.SetHeight then
            f.card.trackerTitle:SetHeight(compact and 48 or 32)
        end
    end
    for i,entry in ipairs(f.card.trackerToggles) do
        local b=entry.button
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT",f.card,"TOPLEFT",20+((i-1)%toggleCols)*224,
            -toggleTop-math.floor((i-1)/toggleCols)*43)
    end
    local required=toggleTop+math.ceil(#f.card.trackerToggles/toggleCols)*43+10
    local desiredHeight=math.max(340,required)
    f.card:SetHeight(desiredHeight)
    if f.navigation then
        f.navigation:SetHeight(w<350 and 190 or 150)
        f.navigation.note:ClearAllPoints()
        f.navigation.note:SetPoint("TOPLEFT",f.navigation,"TOPLEFT",20,-55)
        f.navigation.note:SetWidth(math.max(150,w-40))
        f.navigation.note:SetHeight(w<450 and 78 or 45)
        f.navigation.button:ClearAllPoints()
        f.navigation.button:SetPoint("BOTTOMLEFT",f.navigation,"BOTTOMLEFT",20,15)
        f.navigation.button:SetWidth(math.max(1,math.min(228,w-40)))
    end
    if viewport and viewport.Resize then
        self.__applyingLayout=true
        viewport:Resize(outerWidth,outerHeight,w)
        viewport:SetContentHeight(desiredHeight+12+(f.navigation and f.navigation:GetHeight()+12 or 0),true)
        self.__applyingLayout=false
    end
    return true
end

function Page:Refresh()
    if not self.frame then return end
    self:ApplyLayout()
    local strategy=(JLP.DB and JLP.DB.profile and JLP.DB.profile.strategy) or "economical"
    self.frame.card.body:SetText("Current strategy: "..strategy.."\nNormal guide → Economical; Aggressive guide → Fastest. Source labels are preserved. Fastest is a strategy name, NOT verified shortest playtime. Craft estimates and AH data are advisory; Self-found prefers manual gathering.")
    local tracker=JLP.ObjectiveStepTracker
    if tracker and self.frame.card.trackerPlacement then
        self.frame.card.trackerPlacement:SetText("Objective position: "..tracker:GetPlacement())
    end
    for _,entry in ipairs(self.frame.card.trackerToggles or {}) do
        local enabled=tracker and tracker:IsEnabled(entry.key)
        entry.button:SetText(entry.key..": "..(enabled and "ON" or "OFF"))
        if entry.button.SetActiveState then entry.button:SetActiveState(enabled,"good") end
    end
    for _,entry in ipairs(self.frame.card.buttons) do
        local active=entry.key==strategy
        entry.button:SetText(entry.key=="fastest" and "Fastest" or entry.key=="economical" and "Economical" or "Self-found")
        if entry.button.SetActiveState then entry.button:SetActiveState(active,"good") end
    end
end

JLP.UIPages=JLP.UIPages or {}; JLP.UIPages[Page.name]=Page
