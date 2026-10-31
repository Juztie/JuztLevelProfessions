local _, JLP = ...
-- One visual interaction policy, stable-key identity, native-resource textures.
-- Never drives a route/job or a native gameplay action by itself.
local Row={contract="jlp-gathering-resource-row-v1",nativeDispatchAllowed=false}
-- WoW Lua 5.1 has no guaranteed utf8 library; never cut a multibyte glyph.
local function truncate(s,length)
    s=tostring(s or "Resource")
    length=math.max(2,math.floor(tonumber(length) or 22))
    local cursor,count=1,0
    while cursor<=#s and count<length do
        local lead=s:byte(cursor)
        local width=lead<128 and 1 or lead>=240 and 4 or lead>=224 and 3 or lead>=192 and 2 or 1
        if cursor+width-1>#s then break end
        cursor=cursor+width;count=count+1
    end
    if cursor<=#s then
        local prefixEnd=1;local prefixCount=0
        while prefixEnd<=#s and prefixCount<length-1 do
            local lead=s:byte(prefixEnd)
            local width=lead<128 and 1 or lead>=240 and 4 or lead>=224 and 3 or lead>=192 and 2 or 1
            if prefixEnd+width-1>#s then break end
            prefixEnd=prefixEnd+width;prefixCount=prefixCount+1
        end
        return s:sub(1,prefixEnd-1).."…"
    end
    return s
end

function Row:Present(item,learned,smart,maxNameLength)
    if not item then return nil end
    local record=item.record or {}
    local qualified=item.sourceQualified==true and (tonumber(record.referenceCount) or 0)>0
    local enabled=learned==true and smart~=true and qualified
    return {resourceKey=item.resourceKey,selected=item.selected==true,
        text=(item.selected and "[x] " or "[ ] ")..truncate(item.name,maxNameLength or 22)..
            "  ("..tostring(record.requiredSkill or record.skill or "?")..")"..
            (qualified and "" or " · no qualified points"),
        enabled=enabled,alpha=not qualified and 0.4 or smart and 0.6 or item.selected and 1 or 0.78,
        active=item.selected==true,profession=item.profession}
end
function Row:Apply(button,item,profession,learned,smart,maxNameLength)
    if not button then return end
    local value=self:Present(item,learned,smart,maxNameLength)
    button.resourceKey=value and value.resourceKey or nil
    if not value then
        if button.SetEnabled then button:SetEnabled(false) end
        if button.SetActiveState then button:SetActiveState(false) end
        if button.SetText then button:SetText("") end
        if button.resourceIcon and button.resourceIcon.Hide then button.resourceIcon:Hide() end
        button:Hide();return
    end
    if button.resourceIcon and button.resourceIcon.Show then button.resourceIcon:Show() end
    button:SetText(value.text)
    local icons=JLP:GetModule("GatheringResourceIcons")
    local texture=icons and icons:Resolve(profession,value.resourceKey)
    if button.resourceIcon then
        button.resourceIcon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    if button.SetEnabled then button:SetEnabled(value.enabled) end
    if button.SetActiveState then button:SetActiveState(value.active) end
    if button.SetAlpha then button:SetAlpha(value.alpha) end
    button:Show()
end
JLP:RegisterModule("GatheringResourceRow",Row)
