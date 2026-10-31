local _, JLP = ...

local MinimapButton = {}

function MinimapButton:Create()
    if self.button then return self.button end
    if not Minimap then return nil end

    local button = CreateFrame("Button", "JuztLevelProfessionsMinimapButton", Minimap)
    button:SetSize(34,34)
    button:SetFrameStrata("MEDIUM")
    if button.SetFrameLevel and Minimap.GetFrameLevel then
        button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 5)
    end
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -5, -5)

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetAllPoints()

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(JLP.UITheme:Asset("icons\\professions.tga"))
    icon:SetSize(22,22)
    icon:SetPoint("CENTER",0,0)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(56,56)
    border:SetPoint("TOPLEFT",0,0)
    button.border = border

    -- A physical double-click used to toggle open and closed immediately;
    -- accept the first normal LeftButton release and ignore its duplicate.
    -- This is UI-only and does not change protected native action boundaries.
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" and mouseButton ~= nil then return end
        local t=type(GetTime)=="function" and GetTime() or nil
        if t and self.lastClickAt and t-self.lastClickAt>=0 and t-self.lastClickAt<0.26 then return end
        self.lastClickAt=t
        if JLP.MainWindow and JLP.MainWindow.Toggle then JLP.MainWindow:Toggle() end
    end)

    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("JuztLevel - Professions", 1, 0.82, 0.2)
        GameTooltip:AddLine("Click to open or close the professions window.", 0.85, 0.90, 1.0, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self)
        elseif GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==self then GameTooltip:Hide() end
    end)

    local hidden = JLP.DB and JLP.DB.profile and JLP.DB.profile.minimap and JLP.DB.profile.minimap.hidden
    button:SetShown(not hidden)
    self.button = button
    return button
end

function MinimapButton:SetShown(shown)
    local button = self:Create()
    if button then button:SetShown(shown and true or false) end
    if JLP.DB and JLP.DB.profile then
        JLP.DB.profile.minimap = JLP.DB.profile.minimap or {}
        JLP.DB.profile.minimap.hidden = not shown
    end
end

function MinimapButton:ToggleVisibility()
    local button = self:Create()
    if not button then return end
    self:SetShown(not button:IsShown())
end

JLP.MinimapButton = MinimapButton
