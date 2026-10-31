local _, JLP = ...
-- Alpha171: one owner for temporary main -> standalone map presentation handoff.
-- Selection, routes and SavedVariables retain their pre-existing owners.
local Coordinator={contract="jlp-gathering-window-handoff-v1",nativeDispatchAllowed=false,
    origin=nil,restoring=false}
function Coordinator:Open(kind,mode)
    if kind~="GUIDE" and kind~="SECONDARIES" then return false,"ORIGIN_INVALID" end
    local map=JLP.StandaloneGatheringMap
    if not map then return false,"MAP_UNAVAILABLE" end
    -- Create the hidden frame BEFORE installing the handoff. Its initial Hide
    -- must not accidentally restore an origin window.
    local frame=map:Create()
    if not frame then return false,"MAP_FRAME_UNAVAILABLE" end
    local main=JLP.MainWindow
    local mainFrame=main and main.frame
    local shown=mainFrame and mainFrame:IsShown() or false
    local actualKind=main and main.activePage=="Secondaries" and "SECONDARIES" or kind
    local actualMode=actualKind=="SECONDARIES" and
        (JLP.UIPages and JLP.UIPages.Secondaries and JLP.UIPages.Secondaries:GetMode() or mode) or
        (JLP.UIPages and JLP.UIPages.Guide and JLP.UIPages.Guide:GetMode() or mode)
    self.origin=shown and {kind=actualKind,mode=actualMode} or nil
    if shown then
        mainFrame.__jlpGatheringHandoff=true
        mainFrame:Hide()
        mainFrame.__jlpGatheringHandoff=nil
        -- A reload while the map is active must NOT restore both centered
        -- windows. This is a temporary launch flag; normal close restores it.
        if JLP.DB and JLP.DB.profile then JLP.DB.profile.showWindow=false end
    end
    if map.SetContentContext then
        map:SetContentContext(actualKind=="SECONDARIES" and actualMode=="FISHING" and "FISHING" or "GATHERING")
    end
    local ok=map:Show()
    if not ok then self:OnStandaloneHidden();return false,"MAP_SHOW_FAILED" end
    return true,"STANDALONE_ACTIVE"
end
function Coordinator:OnStandaloneHidden()
    if self.restoring then return false end
    local previous=self.origin
    self.origin=nil
    if not previous then return false end -- independent map or reload: no surprise main window
    local main=JLP.MainWindow
    if not main then return false end
    self.restoring=true
    local frame=main:Create()
    if previous.kind=="SECONDARIES" then main:ShowSecondaryMode(previous.mode or "FISHING")
    else main:ShowGuideMode(previous.mode or "onboarding") end
    if frame then frame:Show() end
    if JLP.DB and JLP.DB.profile then JLP.DB.profile.showWindow=true end
    self.restoring=false
    return true
end
function Coordinator:GetStatus()
    return self.origin and "STANDALONE_FROM_MAIN" or "INDEPENDENT_MAP"
end
JLP:RegisterModule("GatheringWindowCoordinator",Coordinator)
