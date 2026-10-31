local _,JLP=...
-- Shared, transient UI adapter for qualified manual requests only. This is
-- presentation glue to the ONE IntegratedDestinationOwner, never a router.
local Actions={contract="jlp-navigation-actions-v1",nativeDispatchAllowed=false}
local TYPES={BANK=true,AUCTION_HOUSE=true,CURRENT_STEP=true,TRAINER=true,
 VENDOR=true,RECIPE_SOURCE=true,MATERIAL_SOURCE=true,CRAFT_STATION=true,
 MANUAL=true}
local KIND_CATEGORIES={trainer="TRAINER",vendor="VENDOR",recipe="RECIPE_SOURCE",
 scroll="RECIPE_SOURCE",drop="RECIPE_SOURCE",material="MATERIAL_SOURCE",
 crafting_station="CRAFT_STATION",station="CRAFT_STATION"}
function Actions:CategoryForSource(source,fallback)
 if type(source)~="table" then return fallback or "RECIPE_SOURCE" end
 if source.currentStepDestination==true then return "CURRENT_STEP" end
 return KIND_CATEGORIES[source.kind] or KIND_CATEGORIES[source.type] or fallback or "RECIPE_SOURCE"
end
-- One guide-adapter for Dual and Single mode. Resolve from the visible
-- planner step so button presentation and click delivery use the same
-- owner-qualified trainer identity; leave other action kinds unchanged.
function Actions:GuideSource(professionKey,plan,assistSource)
 local api=JLP:GetModule("ProfessionAPI")
 local ownership=api and api.GetOwnership and api:GetOwnership(professionKey)
 if not (ownership and ownership.owned==true) then return nil,ownership and ownership.state or "PROFESSION_OWNERSHIP_UNKNOWN" end
 local current=type(plan)=="table" and plan.recommendedCurrentStep
 if current and (current.materialSupply or professionKey=="SKINNING" or professionKey=="MINING" or professionKey=="HERBALISM" or
    (professionKey=="LEATHERWORKING" and current.recipeID==19082 and current.learned~=true)) then
  local bridge=JLP:GetModule("CurrentStepTravelBridge")
  local nav=bridge and bridge:ForStep(professionKey,current)
  if nav and nav.waypointQualified and nav.source then
   local out={};for k,v in pairs(nav.source) do out[k]=v end
   out.currentStepDestination=true
   return out,nav.reason
  end
  return nil,nav and nav.reason or "CURRENT_STEP_DESTINATION_UNQUALIFIED"
 end
 if type(plan)~="table" or plan.actionKind~="train" then
   return assistSource
 end
 local step=plan.step
 local source=step and step.sourceInfo
 local gate=step and step.trainer
 local resolver=JLP:GetModule("SourceResolver")
 if not resolver or type(resolver.GetQualifiedGuideTrainerWaypoint)~="function" or
    not gate or type(gate.rank)~="string" then
   return nil,"GUIDE_TRAINER_UNQUALIFIED"
 end
 return resolver:GetQualifiedGuideTrainerWaypoint(professionKey,gate.rank,source)
end
-- Tag the workflow owner without changing canonical geography/source facts.
do
 local resolve=Actions.GuideSource
 function Actions:GuideSource(key,plan,assistSource)
  local source,reason=resolve(self,key,plan,assistSource)
  if type(source)=="table"then local copy={};for field,value in pairs(source)do copy[field]=value end
   copy.workflowProfessionKey=key;source=copy end
  return source,reason
 end
end
function Actions:GetOwnerServiceChoices(category)
 local resolver=JLP:GetModule("SourceResolver")
 return resolver and resolver.GetOwnerServiceLocations and
     resolver:GetOwnerServiceLocations(category) or {}
end
function Actions:NearestOwnerService(category)
  local rows=self:GetOwnerServiceChoices(category)
  local router=JLP:GetModule("TravelRouter")
  local player=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
  if not player or type(player.mapID)~="number" or
     type(player.x)~="number" or type(player.y)~="number" then
     return nil,"CURRENT_MAP_OR_POSITION_UNKNOWN" end
  local candidate,score
  for _,item in ipairs(rows) do
    if item and item.sourceQualified==true and item.nav and
       item.nav.mapID==player.mapID then
       local dx=item.nav.x-player.x;local dy=item.nav.y-player.y
       local dist=dx*dx+dy*dy
       if not candidate or dist<score or (dist==score and item.serviceID<candidate.serviceID) then
         candidate,score=item,dist end
    end
  end
  return candidate,candidate and "OWNER_SERVICE_ON_MAP" or "NO_CANONICAL_SERVICE_ON_MAP"
end
function Actions:Request(category,source,context)
 if not TYPES[category] then return false,"UNKNOWN_CATEGORY" end
 local service=JLP:GetModule("UnifiedDestinationNavigation")
 if not service or type(service.Request)~="function" then
   return false,"COMMON_NAVIGATION_UNAVAILABLE" end
 return service:Request(category,source,context)
end
-- A negative preflight is not a navigation action. Keep the reason and a
-- specific manual next step visible to the user; never invent a waypoint.
local function guidance(reason,source)
 local nav=type(source)=="table" and (source.nav or source) or nil
 if reason=="SOURCE_NOT_TABLE" or reason=="SOURCE_NOT_OBSERVED" or
    reason=="GUIDE_TRAINER_IDENTITY_MISSING" or
    reason=="GUIDE_TRAINER_UNQUALIFIED" or
    reason=="TRAINER_NAVIGATION_UNQUALIFIED" then
   return "Verify source","Check the Current Step source or trainer identity in Guide. If you know the location, select a manual waypoint in the existing map."
 end
 if reason=="NO_QUALIFIED_WAYPOINT" and type(nav)=="table" then
   if type(nav.mapID)~="number" or nav.mapID<1 or nav.mapID~=math.floor(nav.mapID) then
     return "Verify map","Check the source's MapID in Guide; select a manual waypoint only with a known map and location."
   end
   if type(nav.x)~="number" or type(nav.y)~="number" or
      nav.x~=nav.x or nav.y~=nav.y or nav.x<0 or nav.x>1 or nav.y<0 or nav.y>1 then
     return "Verify location","Check the source coordinates in Guide; choose a manual waypoint if you can verify the location."
   end
 end
 if reason=="STALE_SOURCE_CONTEXT" or reason=="STALE_CONTEXT" or
    reason=="CHARACTER_CHANGED" or reason=="PLAN_CONTEXT_CHANGED" then
   return "Refresh step","Reopen or refresh Guide for the current character and profession, then verify the destination again."
 end
 if reason=="COMMON_NAVIGATION_UNAVAILABLE" or reason=="DESTINATION_OWNER_UNAVAILABLE" then
   return "Check navigation","Open the existing navigation controls and verify that the shared destination service is available."
 end
 if reason=="CANONICAL_WAYPOINT_MISMATCH" or reason=="CANONICAL_NAVIGATION_PROOF_MISSING" or
    reason=="NO_CANONICAL_SOURCE_PRODUCER" or reason=="GUIDE_TRAINER_COORDINATE_CONFLICT" or
    reason=="CANONICAL_SOURCE_KIND_MISMATCH" then
   return "Verify source","The displayed location is not confirmed by the canonical source. Verify it in Guide or choose a manual waypoint."
 end
 if reason=="NO_QUALIFIED_WAYPOINT" then
   return "Verify location","No qualified map destination is available. Verify the source and MapID or select a manual waypoint."
 end
 if reason=="INVALID_DESTINATION_CATEGORY" or reason=="UNKNOWN_CATEGORY" then
   return "Verify action","This Current Step has no supported destination type. Review its source and use manual guidance."
 end
 return "Verify source","This Current Step has no qualified destination. Verify the source in Guide or select a manual waypoint."
end
function Actions:Preflight(category,source,context)
 local resolved=type(category)=="function" and category(source) or category
 if not TYPES[resolved] then return false,"UNKNOWN_CATEGORY",resolved end
 local common=JLP:GetModule("UnifiedDestinationNavigation")
 if not common or type(common.CanRequest)~="function" then
   return false,"COMMON_NAVIGATION_UNAVAILABLE",resolved
 end
 local ok,reason=common:CanRequest(resolved,source,context or {explicit=true})
 return ok==true,reason or (ok and "WAYPOINT_QUALIFIED" or "DESTINATION_UNQUALIFIED"),resolved
end
function Actions:Update(button,category,source,context)
 if not button then return false,"NO_BUTTON" end
 local ok,reason=self:Preflight(category,source,context)
 if not ok and type(source)~="table" and type(context)=="table" and
    type(context.sourceIssue)=="string" and context.sourceIssue~="" then
   -- SourceResolver's specific rejection is diagnostic only, never authority.
   reason=context.sourceIssue
 end
 local label,nextAction=guidance(reason,source)
 button.__navQualification=ok and "SOURCE_QUALIFIED" or "UNKNOWN"
 button.__navReason=ok and nil or reason
 button.__navNextAction=ok and nil or nextAction
 -- A qualified destination remains a real user-click. An unqualified one
 -- becomes an explicit VERIFY action, never an inert "Navigate To" promise.
 if button.SetEnabled then button:SetEnabled(ok or button.__navActionBound==true) end
 if button.SetText then button:SetText(ok and "Navigate To" or label) end
 return ok,reason
end
function Actions:Bind(button,category,getSource,getContext)
 if not button or type(getSource)~="function" or type(button.SetScript)~="function" then return false end
 button.__navActionBound=true
 button:SetScript("OnClick",function()
    local source=getSource()
    local ctx=type(getContext)=="function" and getContext() or {}
    if type(ctx)~="table" then ctx={} end
    ctx.explicit=true
    local eligible,why,resolved=Actions:Preflight(category,source,ctx)
    if not eligible and type(source)~="table" and
       type(ctx.sourceIssue)=="string" and ctx.sourceIssue~="" then
       why=ctx.sourceIssue
    end
    if eligible then
       local ok,reason=Actions:Request(resolved,source,ctx)
       if ok then
         if JLP.Print then JLP:Print("Navigate To: "..tostring(reason)) end
         return true,reason
       end
       why=reason -- owner/session may have changed since preflight
    end
    local _,nextAction=guidance(why,source)
    if JLP.Print then JLP:Print("Navigate To unavailable ["..tostring(why).."]. "..nextAction) end
    return false,why
 end)
 -- Preserve the widget's own hover implementation; add an explanatory
 -- tooltip only where the WoW Frame API supports HookScript.
 if type(button.HookScript)=="function" then
   button:HookScript("OnEnter",function(self)
     if self.__navQualification~="UNKNOWN" or not GameTooltip or
        type(GameTooltip.SetOwner)~="function" then return end
     GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
     GameTooltip:SetText("Destination unavailable: "..tostring(self.__navReason or "UNKNOWN"))
     if GameTooltip.AddLine then GameTooltip:AddLine(tostring(self.__navNextAction or "Verify the source."),1,1,1,true) end
     if GameTooltip.Show then GameTooltip:Show() end
   end)
   button:HookScript("OnLeave",function(self)
     if self.__navQualification=="UNKNOWN" and GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
   end)
 end
 return true
end
JLP:RegisterModule("IntegratedNavigationActions",Actions)
