local _, JLP = ...
-- Transient UI lifecycle registry. WoW parentage remains unchanged for
-- popups requiring UIParent to avoid ScrollFrame clipping.
local Registry={entries={},owners={}}
function Registry:Register(id,frame,owner)
    if type(id)~="string" or not frame then return false end
    local prior=self.entries[id]
    if prior and prior.frame~=frame then self:Close(id) end
    if prior and prior.owner and self.owners[prior.owner] then
        self.owners[prior.owner][id]=nil
    end
    self.entries[id]={frame=frame,owner=owner}
    if owner then
        self.owners[owner]=self.owners[owner] or {}
        self.owners[owner][id]=true
    end
    return true
end
function Registry:RegisterSpecial(frameName)
    if type(frameName)~="string" or not _G[frameName] then return false end
    _G.UISpecialFrames=_G.UISpecialFrames or {}
    for _,name in ipairs(_G.UISpecialFrames) do if name==frameName then return true end end
    table.insert(_G.UISpecialFrames,frameName)
    return true
end
function Registry:Close(id)
    local entry=self.entries[id]
    if not entry then return false end
    if entry.frame and entry.frame.Hide then entry.frame:Hide() end
    if JLP.UIInteraction and JLP.UIInteraction.HideTooltipTree then
        JLP.UIInteraction:HideTooltipTree(entry.frame)
    end
    return true
end
function Registry:CloseOwner(owner)
    local entries=self.owners[owner]
    if not entries then return false end
    for id in pairs(entries) do self:Close(id) end
    return true
end
-- UIParent-backed page modals are visually exclusive for their logical owner.
-- This is display-only: no protected actions or saved state are modified.
function Registry:OpenModal(owner,id)
    local entry=self.entries[id]
    if not entry or entry.owner~=owner then return false end
    for otherId in pairs(self.owners[owner] or {}) do
        if otherId~=id then self:Close(otherId) end
    end
    local frame=entry.frame
    if not frame then return false end
    if frame.Show then frame:Show() end
    if JLP.UILayout and JLP.UILayout.OverlayFrameLevel then
        frame:SetFrameLevel(JLP.UILayout:OverlayFrameLevel(JLP.MainWindow and JLP.MainWindow.frame,"modal"))
    end
    return true
end
function Registry:CloseAllOverlays()
    for id,entry in pairs(self.entries) do
        if entry.owner then self:Close(id) end
    end
end
JLP.UIWindowRegistry=Registry
