local _, JLP = ...
-- Both map surfaces share this picker and GatheringSharedMapState.  Selecting
-- a documented species is a view filter, never proof of a live fish spawn.
local Picker={contract="jlp-fishing-picker-70450-v1",nativeDispatchAllowed=false,pageSize=7}
local function button(parent,label)
    local b=JLP.UIWidgets:Button(parent,label,240)
    b:SetHeight(25)
    return b
end
function Picker:Attach(anchor,mapProvider,onChanged)
    if not anchor or type(mapProvider)~="function" then return nil,"OWNER_INVALID" end
    local p=CreateFrame("Frame",nil,anchor)
    p:SetSize(250,252)
    p:SetPoint("BOTTOMRIGHT",anchor,"TOPRIGHT",0,5)
    if p.SetClampedToScreen then p:SetClampedToScreen(true) end
    if p.SetFrameStrata then p:SetFrameStrata("DIALOG") end
    if p.SetFrameLevel and anchor.GetFrameLevel then p:SetFrameLevel(anchor:GetFrameLevel()+15) end
    local bg=p:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints();bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.04,0.08,0.12,0.98)
    local rows={}
    for i=1,self.pageSize do
        local row=button(p,"")
        row:SetWidth(234)
        row:SetPoint("TOPLEFT",p,"TOPLEFT",8,-7-(i-1)*27)
        -- Reuse the existing source-qualified Fish artwork. Icons belong to
        -- the picker button, not the map/route layer, and are never pool pins.
        row.fishIcon=row:CreateTexture(nil,"ARTWORK",nil,2)
        row.fishIcon:SetSize(17,17)
        row.fishIcon:SetPoint("LEFT",row,"LEFT",9,0)
        row.fishIcon:Hide()
        if row.label and row.label.ClearAllPoints then
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT",row,"LEFT",31,0)
            row.label:SetPoint("RIGHT",row,"RIGHT",-7,0)
            row.label:SetHeight(24)
        end
        rows[i]=row
    end
    local prev=button(p,"< Previous")
    prev:SetWidth(112);prev:SetPoint("BOTTOMLEFT",p,"BOTTOMLEFT",8,7)
    local nextButton=button(p,"Next >")
    nextButton:SetWidth(112);nextButton:SetPoint("BOTTOMRIGHT",p,"BOTTOMRIGHT",-8,7)
    local offset,entries,mapID=0,{},nil
    local function display()
        local catalogue=JLP:GetModule("FishingResourceCatalogue70450")
        local state=JLP:GetModule("GatheringSharedMapState")
        local selected=state and state:GetSnapshot()
        for i,row in ipairs(rows) do
            local entry=entries[offset+i]
            row._fishEntry=entry
            if entry then
                local active=selected and selected.fishingAreaFilter==entry.mode and
                    (entry.mode~="SINGLE_FISH" or entry.itemID==selected.fishingSelectedItemID)
                local caption=(active and "[x] " or "[ ] ")..entry.label
                if #caption>34 then caption=caption:sub(1,33).."…" end
                row:SetText(caption);row:Show()
                -- Rebind every recycled page row by ItemID. Missing or
                -- unqualified art stays hidden; never retain a previous fish.
                local path=entry.mode=="SINGLE_FISH" and catalogue and
                    catalogue:ResolveIcon(mapID,entry.itemID) or nil
                if type(path)=="string" and path~="" then
                    row.fishIcon:SetTexture(path)
                    row.fishIcon:Show()
                else
                    row.fishIcon:Hide()
                end
                if row.SetEnabled then row:SetEnabled(true) end
            else row.fishIcon:Hide();row:Hide() end
        end
        prev:SetEnabled(offset>0)
        nextButton:SetEnabled(offset+self.pageSize<#entries)
    end
    local function prepare()
        local selectedMap=mapProvider()
        local catalogue=JLP:GetModule("FishingResourceCatalogue70450")
        if type(selectedMap)~="number" or not catalogue then return false,"MAP_UNAVAILABLE" end
        local choices,reason=catalogue:GetChoices(selectedMap)
        if not choices then return false,reason end
        mapID=selectedMap
        entries={{mode="ALL",label="All documented fish"},
            {mode="COOKING_NEEDS",label="Cooking needs (estimated)"}}
        for _,fish in ipairs(choices) do
            entries[#entries+1]={mode="SINGLE_FISH",itemID=fish.itemID,
                label=fish.name..(fish.hasSpatialReference and "" or " (zone only)")}
        end
        offset=0;display()
        return true
    end
    for _,row in ipairs(rows) do
        row:SetScript("OnClick",function(self)
            local entry=self._fishEntry
            if not entry then return end
            local current=mapProvider()
            if current~=mapID then p:Hide();return end
            local state=JLP:GetModule("GatheringSharedMapState")
            local ok=state and state:SetFishingAreaFilter(entry.mode,entry.itemID,mapID)
            p:Hide()
            if ok and type(onChanged)=="function" then onChanged() end
        end)
    end
    prev:SetScript("OnClick",function() offset=math.max(0,offset-self.pageSize);display() end)
    nextButton:SetScript("OnClick",function()
        offset=math.min(math.max(0,#entries-self.pageSize),offset+self.pageSize);display()
    end)
    p:Hide()
    return {
        frame=p,
        Toggle=function()
            if p:IsShown() then p:Hide();return true end
            local ok,why=prepare()
            if not ok then return false,why end
            p:Show();return true
        end,
        Close=function() p:Hide() end,
    }
end
JLP:RegisterModule("FishingResourcePicker70450",Picker)
