local _,JLP=...
-- Read-only material research popup. Uses native client item textures, never altered/copied icons.
-- No routes, no coordinates, no target casts, no native dispatch.
local M={contract="jlp-skinning-materials-browser-v2",nativeDispatchAllowed=false,category="LEATHER",offset=0}
local function iconFor(id)
 local image
 if type(GetItemIcon)=="function" then
  local ok,value=pcall(GetItemIcon,id)
  if ok and value and value~=0 then image=value end
 end
 if not image and type(C_Item)=="table" and type(C_Item.GetItemIconByID)=="function" then
  local ok,value=pcall(C_Item.GetItemIconByID,id)
  if ok and value and value~=0 then image=value end
 end
 return image or "Interface\\Icons\\INV_Misc_QuestionMark",image~=nil
end
function M:GetSnapshot(category,offset)
 local read=JLP:GetModule("SkinningMaterialIntelligence")
 return read and read:ListMaterials(category or self.category,offset or 0,6) or nil
end
local function decorate(parent,text,width)
 local b=JLP.UIWidgets:Button(parent,text,width)
 b:SetHeight(27)
 return b
end
function M:Create()
 if self.frame then return self.frame end
 local W=JLP.UIWidgets
 local f=CreateFrame("Frame","JuztLevelProfessionsSkinningMaterialsBrowser",UIParent)
 -- Keep authored proportions, reducing scale only when the screen is small.
 local pw=UIParent and UIParent.GetWidth and UIParent:GetWidth() or 900
 local ph=UIParent and UIParent.GetHeight and UIParent:GetHeight() or 700
 f:SetSize(720,485)
 local fit=math.min(1,math.max(0.55,math.min((pw-30)/720,(ph-30)/485)))
 if f.SetScale then f:SetScale(fit) end
 f:SetPoint("CENTER",UIParent,"CENTER",0,0)
 if f.SetFrameStrata then f:SetFrameStrata("DIALOG") end
 if f.SetClampedToScreen then f:SetClampedToScreen(true) end
 if JLP.UIWindowRegistry then JLP.UIWindowRegistry:RegisterSpecial("JuztLevelProfessionsSkinningMaterialsBrowser") end
 -- Popup is callable from both Guide and Gathering Map. Bind the
 -- owner when opening, not when the frame is first constructed.
 W:Fill(f,"window","BACKGROUND")
 W:Border(f,"border",1)
 local title=W:Label(f,"SKINNING MATERIALS · SOURCE RESEARCH","GameFontNormalLarge")
 title:SetPoint("TOPLEFT",20,-18)
 local close=decorate(f,"X",36);close:SetPoint("TOPRIGHT",-15,-12)
 close:SetScript("OnClick",function()f:Hide()end)
 f.categoryButtons={}
 local read=JLP:GetModule("SkinningMaterialIntelligence")
 local cats={{"LEATHER","Leather"},{"HIDE","Hides"},{"SCALE","Scales"}}
 local categories={}
 for _,entry in ipairs(cats) do
  local snap=read and read:ListMaterials(entry[1],0,6)
  categories[#categories+1]={entry[1],entry[2].." ("..tostring(snap and snap.total or 0)..")"}
 end
 for i,e in ipairs(categories) do
  local b=decorate(f,e[2],130)
  b:SetPoint("TOPLEFT",20+(i-1)*140,-52)
  b:SetScript("OnClick",function()self.category=e[1];self.offset=0;self.selectedItemID=nil;self:Refresh()end)
  f.categoryButtons[e[1]]=b
 end
 f.status=W:Label(f,"","GameFontHighlightSmall")
 f.status:SetPoint("TOPLEFT",20,-87)
 f.rows={}
 for i=1,6 do
  local row=CreateFrame("Button",nil,f)
  row:SetSize(675,42);row:SetPoint("TOPLEFT",20,-111-(i-1)*44)
  W:Fill(row,"panel","BACKGROUND")
  W:Border(row,"border",1)
  row.icon=row:CreateTexture(nil,"ARTWORK")
  row.icon:SetSize(31,31);row.icon:SetPoint("LEFT",8,0)
  row.text=W:Label(row,"","GameFontHighlight")
  row.text:SetPoint("LEFT",row.icon,"RIGHT",13,0)
  if row.text.SetWidth then row.text:SetWidth(610) end
  if row.text.SetJustifyH then row.text:SetJustifyH("LEFT") end
  row:SetScript("OnEnter",function(self)
   if not self.record or not GameTooltip or not GameTooltip.SetOwner then return end
   GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
   if GameTooltip.AddLine then
    GameTooltip:AddLine(self.record.name.." · item "..self.record.itemID)
    GameTooltip:AddLine("Static Skinning sources, when listed, are external references; not live/client-verified",1,0.8,0.25,true)
    GameTooltip:AddLine("Historical mob/zone leads: "..tostring(self.record.historicalLeadCount or 0),0.7,0.8,0.9)
    if self.record.scope=="RESTRICTED_EPHEMERAL" then
     GameTooltip:AddLine("Temporary/quest material; NOT a regular farming recommendation",1,0.65,0.3,true)
    end
    if self.record.alternativeSource=="FISHING_ALTERNATIVE_DOCUMENTED" then
     GameTooltip:AddLine("Alternative Fishing source documented; not exclusively skinned",0.5,0.8,1,true)
    end
    GameTooltip:AddLine("Source: "..tostring(self.record.sourceURL),0.7,0.8,0.9,true)
    GameTooltip:AddLine("Not a live spawn or farming route.",1,0.5,0.3,true)
   end
   if GameTooltip.Show then GameTooltip:Show() end
  end)
  row:SetScript("OnLeave",function(self)
   if JLP.UIInteraction then JLP.UIInteraction:HideTooltip(self)
   elseif GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==self then GameTooltip:Hide() end
  end)
  row:SetScript("OnClick",function(self)if self.record then M:SelectMaterial(self.record.itemID,{explicit=true}) end end)
  f.rows[i]=row
 end
 f.detail=W:Label(f,"Select an item to see source-qualified historical leads.","GameFontHighlightSmall")
 f.detail:SetPoint("BOTTOMLEFT",20,70)
 if f.detail.SetWidth then f.detail:SetWidth(675) end
 f.previous=decorate(f,"Previous",110);f.previous:SetPoint("BOTTOMLEFT",20,20)
 f.next=decorate(f,"Next",110);f.next:SetPoint("LEFT",f.previous,"RIGHT",10,0)
 f.rejectSupply=decorate(f,"Source unavailable",155);f.rejectSupply:SetPoint("LEFT",f.next,"RIGHT",10,0)
 f.retrySupply=decorate(f,"Retry supply sources",155);f.retrySupply:SetPoint("LEFT",f.rejectSupply,"RIGHT",10,0)
 f.rejectSupply:SetScript("OnClick",function()
  self:RejectSelectedSupply()
  if JLP.MainWindow and JLP.MainWindow.RefreshActiveData then JLP.MainWindow:RefreshActiveData() end
  self:Refresh()
 end)
 f.retrySupply:SetScript("OnClick",function()
  local bridge=JLP:GetModule("GatheringMaterialBridge")
  if bridge then bridge.unavailable=nil end -- explicit retry of history, not an availability receipt
  if JLP.MainWindow and JLP.MainWindow.RefreshActiveData then JLP.MainWindow:RefreshActiveData() end
  self:Refresh()
 end)
 f.previous:SetScript("OnClick",function()local page=self:GetSnapshot(self.category,self.offset);if page and page.previousOffset then self.offset=page.previousOffset;self:Refresh()end end)
 f.next:SetScript("OnClick",function()local page=self:GetSnapshot(self.category,self.offset);if page and page.nextOffset then self.offset=page.nextOffset;self:Refresh()end end)
 f.footer=W:Label(f,"Static Forever references / personal history · verify current target and loot","GameFontHighlightSmall")
 f.footer:SetPoint("BOTTOMRIGHT",-22,24)
 self.frame=f
 f:Hide()
 return f
end
function M:RejectSelectedSupply()
 local shared=JLP:GetModule("GatheringSharedMapState")
 local snapshot=shared and shared:GetSnapshot()
 local goal=snapshot and snapshot.supplyGoal
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 local resolver=JLP:GetModule("SourceResolver")
 local station=goal and goal.sourceKind=="craft_station"and resolver and resolver:GetQualifiedServiceWaypoint("CRAFT_STATION",goal.sourceID,"MINING")
 local qualified=station or goal and bridge and goal.sourceID and (goal.professionKey=="MINING"and
    bridge:GetMiningWaypoint(goal.gatherItemID or goal.itemID,goal.sourceID)or goal.professionKey=="HERBALISM"and bridge:GetHerbalismWaypoint(goal.gatherItemID or goal.itemID,goal.sourceID)or (goal.professionKey~="MINING"and goal.professionKey~="HERBALISM")and bridge:GetSkinningWaypoint(goal.itemID,goal.sourceID))
 if not qualified then return false,"NO_SELECTED_QUALIFIED_STOP"end
 return bridge:SetSupplyUnavailable(goal.sourceID,true)
end
function M:SelectMaterial(itemID,context)
 local read=JLP:GetModule("SkinningMaterialIntelligence")
 local result=read and read:ListMaterialResearch(itemID)
 if not result or not self.frame then return end
 local lead=result.leads and result.leads[1]
 local detail=lead and ("Historical: "..tostring(lead.mobLabel).." · "..tostring(lead.zone or "unknown zone").." · research only") or "Item page identity only; no verified mob output."
 local store=JLP:GetModule("GatheringObservationStore")
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 local stops=bridge and bridge:GetEligibleSkinningSources(itemID) or {}
 local state=JLP:GetModule("GatheringSharedMapState")
 local snapshot=state and state:GetSnapshot()
 local goal=snapshot and snapshot.supplyGoal
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 local stop
 for _,r in ipairs(stops) do
  if not (bridge and bridge.unavailable and bridge.unavailable[r.id]) and
     (context and context.explicit==true or not goal or not goal.sourceID or goal.itemID~=itemID or goal.sourceID==r.id) then stop=r;break end
 end
 if stop then
  if context and context.explicit==true and state and state.SelectSupplyGoal then state:SelectSupplyGoal({itemID=itemID,mapID=stop.mapID,
   sourceID=stop.id,scope=stop.scope,status="SKINNING",quantity=goal and goal.itemID==itemID and goal.quantity or nil}) end
  detail=(stop.scope=="STATIC_FOREVER_SKINNING_REFERENCE" and "Static Forever Skinning reference · "..stop.name or "Personal Skinning history")..
   " · UIMap "..stop.mapID.." · NOT a live spawn or guaranteed loot. Skinning Current Step owns navigation."
 end
 local qualified=read and read:GetOutputQualification(itemID)
 if qualified and qualified.scope=="RESTRICTED_EPHEMERAL" then detail=detail.." · temporary item" end
 if qualified and qualified.alternativeSource=="FISHING_ALTERNATIVE_DOCUMENTED" then detail=detail.." · also fished" end
 self.frame.detail:SetText(detail)
 self.selectedItemID=itemID
end
function M:Refresh()
 local f=self:Create()
 local page=self:GetSnapshot(self.category,self.offset)
 if not page then return nil,"RESEARCH_NOT_AVAILABLE" end
 f.status:SetText(self.category.." · "..page.total.." materials · research and separately qualified personal history")
 for i,row in ipairs(f.rows) do
  local rec=page.items[i]
  row.record=rec
  row:SetShown(rec~=nil)
  if rec then
   local tex,found=iconFor(rec.itemID)
   row.icon:SetTexture(tex)
   row.iconVerified=found
   row.text:SetText(rec.name.."  ["..rec.itemID.."] · "..rec.historicalLeadCount.." research leads"..(rec.scope=="RESTRICTED_EPHEMERAL" and " · TEMP" or ""))
  end
 end
 if self.selectedItemID then self:SelectMaterial(self.selectedItemID) else f.detail:SetText("Choose an item for its historical source lead; no live spawn guarantee.") end
 return page
end
-- The browser may already exist when UIParent resolution/UI scale changes.
-- Recompute its screen fit on every Open, never only during Create.
function M:FitToViewport()
 local f=self.frame
 if not f then return false end
 local pw=UIParent and UIParent.GetWidth and UIParent:GetWidth() or 900
 local ph=UIParent and UIParent.GetHeight and UIParent:GetHeight() or 700
 local fit=math.min(1,math.max(0.55,math.min((pw-30)/720,(ph-30)/485)))
 if f.SetScale then f:SetScale(fit) end
 if f.SetClampedToScreen then f:SetClampedToScreen(true) end
 return true
end
function M:Open(category)
 if category then self.category=category end
 self.offset=0
 self.selectedItemID=nil
 local f=self:Create()
 self:FitToViewport()
 if JLP.UIWindowRegistry then
  local page=JLP.MainWindow and JLP.MainWindow.activePage
  local owner=(page=="Guide" and JLP.MainWindow.frame and
    JLP.MainWindow.frame.IsShown and JLP.MainWindow.frame:IsShown()) and "Guide" or "StandaloneMap"
  JLP.UIWindowRegistry:Register("SkinningMaterialsBrowser",f,owner)
 end
 self:Refresh()
 f:Show()
 return true
end
function M:Close()if self.frame then self.frame:Hide()end end
JLP:RegisterModule("SkinningMaterialsBrowser",M)
JLP.SkinningMaterialsBrowser=M
