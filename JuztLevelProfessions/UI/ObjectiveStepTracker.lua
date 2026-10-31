local _, JLP = ...
-- A private, read-only profession overlay. Never parent to, hook, modify,
-- reposition, or set properties on Blizzard's ObjectiveTrackerFrame.
local Tracker = {
    contract = "jlp-objective-step-overlay-70450-v2",
    nativeDispatchAllowed = false,
    page = 1,
}
local BUILD = 70450
local MAX_REAGENTS = 64
local WIDTH, MAX_ROWS, BASE_HEIGHT, ROW_HEIGHT = 258, 6, 88, 17
local PLACEMENTS = {AUTO=true, ABOVE=true, LEFT=true}
local function finiteInt(n)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
        and n>=0 and n%1==0 and n<=100000000
end
local function registry() return JLP:GetModule("ProfessionRegistry") end
local function keys()
    local r=registry()
    return r and r:GetKeys() or {}
end
local function normalize(key)
    local r=registry()
    return r and r:NormalizeKey(key) or nil
end
local function profile() return JLP.DB and JLP.DB.profile end
-- The BUILD constant names the overlay's original source contract only.
-- Display readiness is determined by live profession/plan observations.
local function readableSkill(key)
    local api=JLP:GetModule("ProfessionAPI")
    local ok,detected=false,nil
    -- pcall's result is only usable when the native profession read succeeds.
    if api and type(api.GetDetected)=="function" then
        ok,detected=pcall(api.GetDetected,api)
    end
    local row=ok and type(detected)=="table" and detected[key] or nil
    if type(row)~="table" or row.cached==true then return nil,nil end
    local skill,maxSkill=tonumber(row.skill),tonumber(row.maxSkill)
    if not finiteInt(skill) or not finiteInt(maxSkill) or maxSkill==0 or skill>maxSkill then
        return nil,nil
    end
    return skill,maxSkill
end
function Tracker:IsEnabled(key)
    key=normalize(key)
    local p=profile()
    return key~=nil and p~=nil and type(p.stepTrackerEnabledByProfession)=="table"
        and p.stepTrackerEnabledByProfession[key]==true or false
end
function Tracker:SetEnabled(key, enabled)
    key=normalize(key)
    if not key then return false,"PROFESSION_UNAVAILABLE" end
    local p=profile()
    if not p then return false,"DB_UNAVAILABLE" end
    if type(p.stepTrackerEnabledByProfession)~="table" then p.stepTrackerEnabledByProfession={} end
    p.stepTrackerEnabledByProfession[key]=(enabled==true)
    self:Refresh()
    if JLP.EventBus then JLP.EventBus:Emit("SETTINGS_CHANGED") end
    return true
end
function Tracker:GetPlacement()
    local p=profile()
    local mode=p and p.objectiveTrackerPlacement or nil
    return PLACEMENTS[mode] and mode or "AUTO"
end
function Tracker:SetPlacement(mode)
    mode=type(mode)=="string" and string.upper(mode) or nil
    if not PLACEMENTS[mode] then return false,"INVALID_PLACEMENT" end
    local p=profile()
    if not p then return false,"DB_UNAVAILABLE" end
    p.objectiveTrackerPlacement=mode
    self:Refresh()
    if JLP.EventBus then JLP.EventBus:Emit("SETTINGS_CHANGED") end
    return true
end
function Tracker:BuildModel(key)
    key=normalize(key)
    if not key then return nil,"UNKNOWN_PROFESSION" end
    local capabilities=JLP:GetModule("RuntimeCompatibility")
    if not capabilities or not capabilities.Assess then return nil,"RUNTIME_CAPABILITY_LAYER_UNAVAILABLE" end
    -- No source-build match is required for a read-only overlay.
    local view=capabilities:Assess({},BUILD)
    if view.status~="AVAILABLE" then return nil,"TRACKER_CAPABILITY_UNAVAILABLE" end
    local r=registry()
    local def=r and r:Get(key)
    local skill,maxSkill=readableSkill(key)
    local skillText=skill and ("Skill "..skill.."/"..maxSkill) or "Live skill unknown"
    local planner=JLP:GetModule("Planner")
    -- The same queue head drives Guide and this overlay. A planned recipe is
    -- not necessarily the next action: its bank, source or trainer comes first.
    local plan=nil
    if planner and type(planner.GetProfessionPlan)=="function" then
        local ok,result=pcall(planner.GetProfessionPlan,planner,key)
        if ok then plan=result end
    end
    local queueModule=JLP:GetModule("ActionQueue")
    local queue,action
    if queueModule and type(queueModule.Build)=="function" then
        local ok,result=pcall(queueModule.Build,queueModule,key,plan)
        if ok and type(result)=="table" then
            queue=result
            local index=tonumber(queue.currentIndex)
            action=index and index>=1 and type(queue.actions)=="table" and queue.actions[index] or nil
        end
    end
    local title=action and action.text or (plan and plan.action)
    local kind=action and action.kind or (plan and plan.actionKind) or "unavailable"
    if plan and plan.actionKind=="complete" then title="Profession skill goal reached" end
    title=type(title)=="string" and title~="" and title or "Open Guide to review the next profession action"
    local actionDescription=action and action.detail
    if not (type(plan)=="table" and plan.actionKind=="craft" and type(plan.step)=="table") then
        return {
            key=key, recipe=title, actionID=action and action.actionID,
            actionKind=kind,planActionKind=plan and plan.actionKind,
            description=skillText..(actionDescription and (" · "..actionDescription) or ""),
            skill=skill,maxSkill=maxSkill, materials={}, omittedMaterials=0,
            progressionStatus=skill and "LIVE_SKILL_NONCRAFT" or "SKILL_UNVERIFIED",
            readOnly=true, estimateOnly=true, nativeDispatchAllowed=false,
        }
    end
    local step=plan.step
    local n=tonumber(step.remainingCrafts)
    if not finiteInt(n) then return nil,"ESTIMATE_UNAVAILABLE" end
    local lines, omitted={},0
    local inventory=JLP:GetModule("Inventory")
    for _, material in ipairs(type(plan.materials)=="table" and plan.materials or {}) do
        if type(material)~="table" then material={name="Unverified reagent"} end
        if #lines>=MAX_REAGENTS then
            omitted=omitted+1
        else
            local itemID=tonumber(material.itemID)
            local qty=tonumber(material.perCraft)
            local required=finiteInt(qty) and finiteInt(n*qty) and n*qty or nil
            local stock=nil
            if itemID and finiteInt(itemID) and itemID>0 and inventory and
                type(inventory.GetOwned)=="function" then
                local ok,result=pcall(inventory.GetOwned,inventory,itemID)
                if ok and type(result)=="table" then stock=result end
            end
            local bags=stock and stock.bagKnown==true and finiteInt(stock.bags) and stock.bags or nil
            local bank=stock and stock.bankKnown==true and finiteInt(stock.bank) and stock.bank or nil
            -- Persistent cached bank counts can guide the player, but are not
            -- a verified current-session stock observation for 'missing'.
            if not (inventory and inventory.bankOpen==true and stock and
                stock.bankOpenedAt and stock.bankCacheUpdatedAt and
                tonumber(stock.bankCacheUpdatedAt)>=tonumber(stock.bankOpenedAt)) then
                bank=nil
            end
            local total=bags and bank and (bags+bank) or nil
            local validTotal=total and finiteInt(total) and total or nil
            local missing=validTotal and required and math.max(0,required-validTotal) or nil
            local status=not required and "UNKNOWN_REQUIRED" or not bags and "BAGS_UNKNOWN" or
                not bank and "BANK_UNVERIFIED" or "KNOWN"
            lines[#lines+1]={
                name=tostring(material.name or "Unknown reagent"),itemID=itemID,
                perCraft=finiteInt(qty) and qty or nil,total=required,
                bags=bags,bank=bank,owned=validTotal,missing=missing,status=status,
            }
        end
    end
    return {
        key=key,recipe=title,recipeName=step.recipe,
        actionID=action and action.actionID,actionKind=kind,planActionKind=plan.actionKind,
        target=step.skillTarget,skill=skill,maxSkill=maxSkill,
        description=tostring(step.recipe or "Current recipe").." · "..skillText..
            " · target "..tostring(step.skillTarget or "?")..
            " · ~"..tostring(n).." crafts (estimate)"..
            (actionDescription and (" · "..actionDescription) or ""),
        remainingCrafts=n,materials=lines,omittedMaterials=omitted,
        progressionStatus="CRAFT_ESTIMATE",readOnly=true,estimateOnly=true,
        nativeDispatchAllowed=false,
    }
end

-- Geometry is derived exclusively from Blizzard's currently *visible* tracker.
-- The native frame is never modified. If no non-overlapping screen area exists,
-- hide the independent panel instead of covering quests/objectives.
function Tracker:ChooseDock(anchor)
    if not (anchor and anchor.IsShown and anchor:IsShown()) then return nil,"BLIZZARD_TRACKER_HIDDEN" end
    local collapsed=type(anchor.IsCollapsed)=="function" and anchor:IsCollapsed() or anchor.isCollapsed==true or anchor.collapsed==true
    if collapsed then return nil,"BLIZZARD_TRACKER_COLLAPSED" end
    local parent=UIParent
    local aLeft=anchor.GetLeft and anchor:GetLeft()
    local aRight=anchor.GetRight and anchor:GetRight()
    local aTop=anchor.GetTop and anchor:GetTop()
    local aScale=anchor.GetEffectiveScale and anchor:GetEffectiveScale()
    local pScale=parent and parent.GetEffectiveScale and parent:GetEffectiveScale()
    local pTop=parent and parent.GetTop and parent:GetTop()
    local pLeft=parent and parent.GetLeft and parent:GetLeft()
    local pRight=parent and parent.GetRight and parent:GetRight()
    local pBottom=parent and parent.GetBottom and parent:GetBottom()
    if type(aLeft)~="number" or type(aTop)~="number" or
        type(pTop)~="number" or type(pLeft)~="number" or type(pBottom)~="number" or
        type(aScale)~="number" or aScale<=0 or type(pScale)~="number" or pScale<=0 then
        return nil,"TRACKER_GEOMETRY_UNAVAILABLE"
    end
    local scale=math.max(0.65,math.min(1.3,aScale/pScale))
    if aTop>pTop or aTop<pBottom then return nil,"TRACKER_OUTSIDE_SCREEN" end
    local topSpace=(pTop-aTop-8)/scale
    local aboveWidthFits=type(aRight)=="number" and type(pRight)=="number" and
        aRight<=pRight and (aRight-pLeft)>=WIDTH*scale
    local leftSpace=(aLeft-pLeft-10)/scale
    local lowerSpace=(aTop-pBottom-8)/scale
    local wanted=self:GetPlacement()
    local function dock(kind, space)
        if space<BASE_HEIGHT+ROW_HEIGHT then return nil end
        local rows=math.max(1,math.min(MAX_ROWS,math.floor((space-BASE_HEIGHT)/ROW_HEIGHT)))
        return {side=kind,scale=scale,rows=rows,height=BASE_HEIGHT+rows*ROW_HEIGHT}
    end
    if wanted~="LEFT" and aboveWidthFits then
        local above=dock("ABOVE",topSpace)
        if above then return above end
    end
    if wanted~="ABOVE" and leftSpace>=WIDTH then
        local left=dock("LEFT",lowerSpace)
        if left then return left end
    end
    return nil,"NON_OVERLAPPING_SPACE_UNAVAILABLE"
end
local function materialText(row)
    if not row then return "" end
    if not row.total then return row.name.." · quantity unknown" end
    if row.owned~=nil and row.missing~=nil then
        return row.name.."  "..row.total.." needed · "..row.owned.." owned / "..row.missing.." missing"
    end
    local bags=row.bags and (" · bags "..row.bags) or ""
    return row.name.."  "..row.total.." needed"..bags.." · "..row.status
end
function Tracker:Create()
    if self.frame then return self.frame end
    local f=CreateFrame("Frame","JuztLevelObjectiveStepPanel",UIParent)
    f:SetSize(WIDTH,BASE_HEIGHT+MAX_ROWS*ROW_HEIGHT)
    f:SetFrameStrata("LOW")
    f:EnableMouse(false) -- Never intercept clicks intended for Blizzard objectives.
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    local bg=f:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints()
    if JLP.UITheme and JLP.UITheme.Asset then bg:SetTexture(JLP.UITheme:Asset("layout\\sidebar_background.tga")) end
    bg:SetAlpha(0.76)
    local title=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOPLEFT",11,-9);title:SetWidth(236)
    title:SetText("JuztLevel · Current Step")
    if JLP.UITheme and JLP.UITheme.Color then title:SetTextColor(JLP.UITheme:Color("gold")) end
    f.title=title
    f.recipe=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.recipe:SetPoint("TOPLEFT",11,-27);f.recipe:SetWidth(234);f.recipe:SetJustifyH("LEFT")
    f.target=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.target:SetPoint("TOPLEFT",11,-44);f.target:SetWidth(234);f.target:SetJustifyH("LEFT")
    f.rows={}
    for i=1,MAX_ROWS do
        local line=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        line:SetPoint("TOPLEFT",11,-65-(i-1)*ROW_HEIGHT)
        line:SetWidth(234);line:SetJustifyH("LEFT")
        f.rows[i]=line
    end
    local function nav(label,x,delta)
        local b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
        b:SetSize(54,19);b:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",x,3)
        b:SetText(label)
        b:SetScript("OnClick",function()
            Tracker.page=(Tracker.page or 1)+delta
            Tracker:Refresh()
        end)
        return b
    end
    f.previous=nav("Prev",10,-1)
    f.next=nav("Next",194,1)
    f.pageText=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.pageText:SetPoint("BOTTOM",f,"BOTTOM",0,7)
    f:Hide();self.frame=f
    local controller=CreateFrame("Frame")
    controller.elapsed=0
    controller:SetScript("OnUpdate",function(self,dt)
        -- Disabled overlays have nothing to poll; SetEnabled and SETTINGS_CHANGED
        -- already refresh immediately. Hidden docks probe periodically so a
        -- newly visible Blizzard tracker can still be re-acquired.
        if Tracker.hiddenReason=="PROFESSION_OVERLAY_DISABLED" then
            self.elapsed=0
            return
        end
        self.elapsed=self.elapsed+(tonumber(dt) or 0)
        local visible=Tracker.frame and Tracker.frame.IsShown and Tracker.frame:IsShown()
        if self.elapsed<(visible and 1.5 or 4.5) then return end
        self.elapsed=0
        Tracker:Refresh()
    end)
    self.controller=controller
    if JLP.EventBus then
        for _,event in ipairs({"PROFESSION_PROGRESS_UPDATED","PROFESSION_TRANSACTION_UPDATED",
            "PROFESSION_CRAFT_OBSERVED","CRAFT_OBSERVATION_JOURNAL_UPDATED",
            "PROFESSION_EXECUTION_UPDATED","SETTINGS_CHANGED",
            "PROFESSION_DATA_70450_INVALIDATED","AH_SNAPSHOT_UPDATED"}) do
            JLP.EventBus:On(event,function() Tracker:Refresh() end)
        end
    end
    local updates=CreateFrame("Frame")
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","SKILL_LINES_CHANGED",
        "TRADE_SKILL_LIST_UPDATE","BAG_UPDATE_DELAYED","BANKFRAME_OPENED","BANKFRAME_CLOSED"}) do
        pcall(updates.RegisterEvent,updates,event)
    end
    updates:SetScript("OnEvent",function() Tracker:Refresh() end)
    self.updates=updates
    return f
end
function Tracker:Refresh()
    local f=self.frame
    if not f then return end
    local anchor=_G.ObjectiveTrackerFrame or _G.ObjectiveTracker
    local chosen=profile()and (profile().activeSecondaryCurrentStep or profile().guideMode)
    local selected=self:IsEnabled(chosen) and normalize(chosen) or nil
    if not selected then
        for _,key in ipairs(keys()) do if self:IsEnabled(key) then selected=key;break end end
    end
    if not selected then f:Hide();self.hiddenReason="PROFESSION_OVERLAY_DISABLED";return end
    local dock,reason=self:ChooseDock(anchor)
    if not dock then f:Hide();self.hiddenReason=reason;return end
    local model,why=self:BuildModel(selected)
    if not model then f:Hide();self.hiddenReason=why;return end
    self.hiddenReason=nil
    if self.lastKey~=model.key or self.lastRecipe~=model.recipe then
        self.page=1;self.lastKey=model.key;self.lastRecipe=model.recipe
    end
    local slots=dock.rows
    local total=#model.materials+(model.omittedMaterials>0 and 1 or 0)
    local pages=math.max(1,math.ceil(total/slots))
    self.page=math.max(1,math.min(self.page or 1,pages))
    f:ClearAllPoints()
    f:SetScale(dock.scale);f:SetHeight(dock.height)
    if dock.side=="ABOVE" then
        f:SetPoint("BOTTOMRIGHT",anchor,"TOPRIGHT",0,8)
    else
        f:SetPoint("TOPRIGHT",anchor,"TOPLEFT",-10,0)
    end
    f.recipe:SetText(model.key..": "..model.recipe)
    f.target:SetText(model.description or "Read-only profession guidance")
    for i,row in ipairs(f.rows) do
        local index=(self.page-1)*slots+i
        local material=i<=slots and model.materials[index] or nil
        local msg=materialText(material)
        if not material and i<=slots and index==#model.materials+1 and model.omittedMaterials>0 then
            msg=tostring(model.omittedMaterials).." additional reagents not shown"
        end
        row:SetText(msg)
        row:SetShown(i<=slots and msg~="")
    end
    f.previous:SetShown(pages>1);f.next:SetShown(pages>1)
    if f.previous.SetEnabled then f.previous:SetEnabled(self.page>1) end
    if f.next.SetEnabled then f.next:SetEnabled(self.page<pages) end
    f.pageText:SetText(pages>1 and ("Materials "..self.page.." / "..pages) or "")
    f:Show()
end
JLP.ObjectiveStepTracker=Tracker
local init=CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent",function() Tracker:Create();Tracker:Refresh() end)
