local _,JLP=...
-- Read-only diagnostic. Never sizes/reanchors frames or changes active pages,
-- popups, waypoints, objective trackers, crafting, or SavedVariables.
local Audit={contract="jlp-ui-presentation-audit-70450-v1",nativeDispatchAllowed=false}
local PAGES={"Overview","Guide","Auction House","Bank","History","Settings","Secondaries"}
local function finite(v)
 return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end
local function safe(frame,method)
 if not frame or type(frame[method])~="function" then return nil end
 local ok,value=pcall(frame[method],frame)
 return ok and value or nil
end
function Audit:Inspect()
 local main=JLP.MainWindow
 local frame=main and main.frame
 local parent=UIParent
 local w,h=safe(parent,"GetWidth"),safe(parent,"GetHeight")
 local fw,fh=safe(frame,"GetWidth"),safe(frame,"GetHeight")
 local scale=safe(frame,"GetScale") or (frame and frame._scale)
 local pages={};local absent=0
 for _,name in ipairs(PAGES) do
  local registered=JLP.UIPages and JLP.UIPages[name]~=nil
  local loaded=main and main.frame and main.frame.pages and main.frame.pages[name]~=nil or false
  pages[#pages+1]={name=name,registered=registered,loaded=loaded}
  if not registered then absent=absent+1 end
 end
 local popupCount=0
 local registry=JLP.UIWindowRegistry
 for _,entry in pairs(registry and registry.entries or {}) do
  if entry.owner and safe(entry.frame,"IsShown")==true then popupCount=popupCount+1 end
 end
 local visibility=safe(frame,"IsShown")
 local fit=main and main.lastViewportFit
 local viewportFits=fit and fit.fits==true and
   finite(w) and finite(h) and finite(fw) and finite(fh) and finite(scale) and
   fw*scale<=w+0.01 and fh*scale<=h+0.01 or false
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 local active=owner and owner.active or nil
 local hud=JLP:GetModule("IntegratedNavigationHUD")
 return {contract=self.contract,build=70450,readOnly=true,nativeDispatchAllowed=false,
  viewport={width=w,height=h,windowWidth=fw,windowHeight=fh,windowScale=scale,
   fitted=viewportFits,fitRecorded=fit and fit.fits or false},
  activePage=main and main.activePage or "NONE",windowVisible=visibility==true,
  popupCount=popupCount,missingPageRegistrations=absent,pages=pages,
  destinationCategory=active and active.category or "NONE",
  destinationPriority=active and active.priority or 0,
  hudEnabled=hud and hud.enabled==true or false,
  hudScale=hud and hud.renderedScale or nil,
  status=not frame and "WINDOW_NOT_INITIALIZED" or
   not viewportFits and "VIEWPORT_REQUIRES_INSPECTION" or
   absent>0 and "MISSING_PAGE_REGISTRATION" or "GEOMETRY_CHECK_PASSED",
  visualVerification="REQUIRES_LIVE_CLIENT",
  popupInteractionVerification="REQUIRES_LIVE_CLIENT"}
end
function Audit:Print()
 local s=self:Inspect()
 if type(JLP.Print)~="function" then return false,"PRINTER_UNAVAILABLE" end
 JLP:Print("UI 70450: "..s.status.." / active "..s.activePage..
   " / page registrations "..tostring(#s.pages-s.missingPageRegistrations).."/"..#s.pages)
 JLP:Print("Viewport "..tostring(s.viewport.width).."x"..tostring(s.viewport.height)..
   " / fitted "..tostring(s.viewport.fitted).." / open popups "..tostring(s.popupCount))
 JLP:Print("Navigation "..s.destinationCategory.." / priority "..tostring(s.destinationPriority)..
   " / HUD "..(s.hudEnabled and "ON" or "OFF").." / live visual QA REQUIRED")
 return true,s.status
end
JLP:RegisterModule("UIPresentationAudit70450",Audit)
