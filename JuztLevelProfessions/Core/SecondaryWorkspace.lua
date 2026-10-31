local _, JLP = ...

-- Secondary navigation is registry-backed presentation, NOT production authority.
-- Unlearned professions remain browsable as clearly labeled research previews.
local Service={contract="secondary-profession-navigation-v1",nativeDispatchAllowed=false}
local ORDER={"COOKING","FISHING","FIRST_AID"}

local function learnedIndex()
    local api=JLP:GetModule("ProfessionAPI")
    local out={}
    for _,row in ipairs(api and api:GetSecondaryProfessions() or {}) do
        if row.key then out[row.key]=row end
    end
    return out
end

function Service:GetMenuDefinitions()
    local known=learnedIndex()
    local registry=JLP:GetModule("ProfessionRegistry")
    local result={}
    for _,key in ipairs(ORDER) do
        local def=registry and registry:Get(key)
        if def and def.category=="SECONDARY" then
            result[#result+1]={key=key,label=def.label or def.name or key,
                learned=known[key]~=nil,profession=known[key],category="SECONDARY"}
        end
    end
    return result
end

function Service:ResolveMode(requested)
    local key=tostring(requested or ""):upper():gsub("[%s%-]","_")
    if key=="" or key=="OVERVIEW" or key=="SECONDARIES" then return "overview" end
    for _,allowed in ipairs(ORDER) do if key==allowed then return allowed end end
    return "overview"
end

function Service:ActivateCurrentStep(key)
    if (key~="FIRST_AID" and key~="COOKING" and key~="FISHING")or not learnedIndex()[key]or not(JLP.DB and JLP.DB.profile)then return false,"SECONDARY_NOT_OBSERVED"end
    JLP.DB.profile.activeSecondaryCurrentStep=key -- explicit UI choice; primary slots/focus are unchanged
    local p=JLP:GetModule("Planner");local plan=p and p:GetProfessionPlan(key)
    local nav=JLP:GetModule("CurrentStepTravelBridge")
    if nav and plan and plan.recommendedCurrentStep then nav:Sync(key,plan.recommendedCurrentStep,{contextToken="EXPLICIT_SECONDARY_CURRENT_STEP"})end
    local tracker=JLP.ObjectiveStepTracker
    if tracker and tracker.SetEnabled then tracker:SetEnabled(key,true)end
    return true,plan
end
function Service:SetCookingStationMode(mode)
    if mode~="EXISTING"and mode~="KIT"then return false,"UNKNOWN_STATION_MODE"end
    if not learnedIndex().COOKING or not(JLP.DB and JLP.DB.profile)then return false,"COOKING_NOT_OBSERVED"end
    JLP.DB.profile.cookingStationPreparation=mode -- preference, never station readiness
    JLP.DB.profile.cookingStationUseReceipt=nil -- explicit retry/cancel only; no predicted station state
    self.pendingCookingUse=nil
    return true
end
local function observer()
    local id=type(UnitGUID)=="function"and UnitGUID("player")
    return type(id)=="string"and id:match("^Player%-")and id or nil
end
local function selectedCooking()
    local api=JLP:GetModule("ProfessionAPI");local p=api and api:Get("COOKING")
    local ds=JLP:GetModule("ProfessionDatasetProvider");local d=ds and ds:GetPlannerDataset("COOKING",{allowCandidate=true})
    local current=JLP:GetModule("UniversalCurrentStep")
    return p and d and current and current:Recommend("COOKING",p,d)
end
function Service:GetCookingUseReceipt(c,d)
    local r=JLP.DB and JLP.DB.profile and JLP.DB.profile.cookingStationUseReceipt
    if type(r)~="table"or not observer()or r.observerGUID~=observer()or r.recipeID~=c.recipeID or
       r.itemID~=d.itemID or r.useSpellID~=d.useSpellID or not c.secondaryPrerequisites or r.focusID~=c.secondaryPrerequisites.focusID or
       r.status~="OBSERVED_CAST_NOT_CONSUMER_READINESS"or type(r.castGUID)~="string"then return nil end
    return r
end
function Service:ObserveCookingStationUse(event,...)
    if event=="PLAYER_ENTERING_WORLD"or event=="ZONE_CHANGED_NEW_AREA"or event=="PLAYER_LOGOUT"then self.pendingCookingUse=nil;return end
    local unit,a,b,c=...
    if unit~="player"then return end
    if event=="UNIT_SPELLCAST_SENT"then
        self.pendingCookingUse=nil
        if type(b)~="string"or #b>150 or (c~=1307227 and c~=1307226)or not observer()then return end
        local who=observer();local current=selectedCooking();local r=current and current.stationPreparation
        if who~=observer()or not r or r.status~="PLACE_MANUALLY_VERIFY_LOCATION"or r.useSpellID~=c then return end
        self.pendingCookingUse={observerGUID=who,recipeID=current.recipeID,focusID=r.focusID,itemID=r.itemID,useSpellID=c,castGUID=b}
    elseif event=="UNIT_SPELLCAST_SUCCEEDED"then
        local pending=self.pendingCookingUse;self.pendingCookingUse=nil
        if not pending or pending.observerGUID~=observer()or pending.castGUID~=a or pending.useSpellID~=b then return end
        local current=selectedCooking();local f=current and current.secondaryPrerequisites
        if not current or current.recipeID~=pending.recipeID or not f or f.focusID~=pending.focusID or pending.observerGUID~=observer()then return end
        pending.status="OBSERVED_CAST_NOT_CONSUMER_READINESS"
        JLP.DB.profile.cookingStationUseReceipt=pending -- scoped receipt, never inventory or station-MET
        return true
    elseif event=="UNIT_SPELLCAST_FAILED"or event=="UNIT_SPELLCAST_INTERRUPTED"then
        if self.pendingCookingUse and self.pendingCookingUse.castGUID==a then self.pendingCookingUse=nil end
    end
end
function Service:GetSnapshot(requested)
    local key=self:ResolveMode(requested)
    if key=="overview" then return nil,"OVERVIEW" end
    local registry=JLP:GetModule("ProfessionRegistry")
    local def=registry and registry:Get(key)
    if not def or def.category~="SECONDARY" then return nil,"UNKNOWN_SECONDARY" end
    local known=learnedIndex()
    local profession=known[key]
    local guide=JLP:GetModule("ProfessionReferenceGuide")
    local evidence=guide and guide:Get(key)
    local skill=profession and tonumber(profession.skill) or nil
    local current=skill and guide and guide:GetCurrentBand(key,skill) or nil
    local upcoming=nil
    for _,band in ipairs(evidence and evidence.bands or {}) do
        if skill and tonumber(band.skillMin) and band.skillMin>skill and (not upcoming or band.skillMin<upcoming.skillMin) then upcoming=band end
    end
    local secondaryPlanner=JLP:GetModule("SecondaryLevelingPlanner")
    local secondaryPlan=nil
    if key=="COOKING" or key=="FIRST_AID" then
        -- Unlearned professions show clearly labeled *research previews*, not invented skill observations.
        secondaryPlan=secondaryPlanner and secondaryPlanner:Build(key,skill or 1)
    end
    local fishingGuide=nil
    if key=="FISHING" then
        fishingGuide=secondaryPlanner and secondaryPlanner:GetFishingGuidance(skill or 1)
    end
    return {
        operationalPlan=(key=="FIRST_AID" or key=="COOKING" or key=="FISHING") and profession and JLP:GetModule("Planner") and JLP:GetModule("Planner"):GetProfessionPlan(key,{preview=not(JLP.DB and JLP.DB.profile and JLP.DB.profile.activeSecondaryCurrentStep==key)})or nil,
        secondaryPlan=secondaryPlan,fishingGuide=fishingGuide,
        key=key,label=def.label or key,learned=profession~=nil,
        cached=profession and profession.cached==true or false,
        skill=skill,skillModifier=profession and not profession.cached and profession.skillModifier or nil,
        maxSkill=profession and tonumber(profession.maxSkill) or nil,
        coverage=evidence and evidence.coverage or "REFERENCE_UNAVAILABLE",
        levelingType=evidence and evidence.levelingType or "UNKNOWN",
        band=current,nextBand=upcoming,
        note=evidence and evidence.note or "No documented route",
        source=evidence and (evidence.guideURL or evidence.source) or nil,
        nativeDispatchAllowed=false,
    }
end

function Service:Validate()
    local errs={}
    if #self:GetMenuDefinitions()~=3 then errs[#errs+1]="secondary-menu-count" end
    for _,key in ipairs(ORDER) do
        local row=self:GetSnapshot(key)
        if not row or row.key~=key or row.nativeDispatchAllowed~=false then errs[#errs+1]="secondary-contract:"..key end
    end
    return errs
end

JLP:RegisterModule("SecondaryWorkspace",Service)
