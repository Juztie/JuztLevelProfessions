local _, JLP = ...
-- One-shot diagnostic: no event listeners, saved state, sampling hooks or overlay.
-- FPS from a single API call is NOT a measured performance benchmark.
local Acceptance={contract="jlp-gathering-client-acceptance-v1",nativeDispatchAllowed=false}
local function numeric(v)
 return type(v)=="number" and v==v and math.floor(v*100+0.5)/100 or nil
end
-- Real-world acceptance requires screenshots and interaction: rectangles alone
-- are diagnostic leads, NEVER proof that a click or pointer event succeeded.
function Acceptance:ControlGeometry()
 local window=JLP.StandaloneGatheringMap
 local frame=window and window.frame
 local root=UIParent
 local result={contract="gathering-control-geometry-v1",verified=false,
  controls={},visible=0,withinViewport=0,unknown=0,outside=0}
 if not frame or not root or not root.GetLeft then return result end
 local rootL,rootR,rootT,rootB=root:GetLeft(),root:GetRight(),root:GetTop(),root:GetBottom()
 local boundsValid=type(rootL)=="number" and type(rootR)=="number" and
   type(rootT)=="number" and type(rootB)=="number"
 for _,entry in ipairs({{"close",frame.close},{"map",frame.canvas},
    {"generate",frame.generate},{"cancel_or_clear",frame.clear},
    {"resource_search",frame.resourceSearch},{"resource_previous",frame.resourcePrev},
    {"resource_next",frame.resourceNext},{"options",frame.optionsPanel},
    {"route_details",frame.detailsPanel},{"zoom_in",frame.zoomIn},
    {"zoom_out",frame.zoomOut},{"resize",frame.resizeHandle}}) do
  local name,control=entry[1],entry[2]
  if control and control.IsShown and control:IsShown() then
   result.visible=result.visible+1
   local left=control.GetLeft and control:GetLeft()
   local right=control.GetRight and control:GetRight()
   local top=control.GetTop and control:GetTop()
   local bottom=control.GetBottom and control:GetBottom()
   local measured=type(left)=="number" and type(right)=="number" and
       type(top)=="number" and type(bottom)=="number" and boundsValid
   local inBounds=measured and left>=rootL-1 and right<=rootR+1 and
       bottom>=rootB-1 and top<=rootT+1
   local status=not measured and "NOT_MEASURABLE" or
       (inBounds and "WITHIN_VIEWPORT" or "OUTSIDE_VIEWPORT")
   result.controls[#result.controls+1]={name=name,status=status}
   if status=="NOT_MEASURABLE" then result.unknown=result.unknown+1
   elseif inBounds then result.withinViewport=result.withinViewport+1
   else result.outside=result.outside+1 end
  end
 end
 return result
end
-- Explicitly user-started only, in-memory, bounded, and never a screenshot
-- substitute. One FPS sample per elapsed second; no automatic upload/storage.
function Acceptance:StartFPS()
 if self._fpsJob then return false,"MEASUREMENT_ALREADY_RUNNING" end
 self._fpsResult=nil
 self._fpsJob={elapsed=0,accum=0,count=0,sum=0,min=nil,max=nil,duration=60}
 if not self._fpsFrame and type(CreateFrame)=="function" then
  self._fpsFrame=CreateFrame("Frame",nil,UIParent)
 end
 if self._fpsFrame and self._fpsFrame.SetScript then
  self._fpsFrame:SetScript("OnUpdate",function(_,elapsed) Acceptance:FeedFPS(elapsed) end)
 end
 return true,"STARTED_60_SECOND_MEASUREMENT"
end
function Acceptance:FeedFPS(elapsed,explicitSample)
 local job=self._fpsJob
 if not job then return "NOT_RUNNING" end
 elapsed=type(elapsed)=="number" and elapsed==elapsed and
   math.max(0,math.min(elapsed,60)) or 0
 job.elapsed=job.elapsed+elapsed
 job.accum=job.accum+elapsed
 if job.accum>=1 then
  local fps=explicitSample
  if fps==nil and type(GetFramerate)=="function" then fps=GetFramerate() end
  if type(fps)=="number" and fps==fps and fps>=0 and fps<10000 then
   job.sum=job.sum+fps;job.count=job.count+1
   job.min=math.min(job.min or fps,fps);job.max=math.max(job.max or fps,fps)
  end
  job.accum=job.accum%1
 end
 if job.elapsed>=job.duration then return self:StopFPS() end
 return "MEASURING"
end
function Acceptance:StopFPS()
 local job=self._fpsJob
 if not job then return false,"NOT_RUNNING" end
 if self._fpsFrame and self._fpsFrame.SetScript then self._fpsFrame:SetScript("OnUpdate",nil) end
 local complete=job.elapsed>=job.duration and job.count>=40
 self._fpsResult={state=complete and "COMPLETE" or "INCOMPLETE",
   durationSeconds=math.min(60,job.elapsed),sampleCount=job.count,
   average=job.count>0 and numeric(job.sum/job.count) or nil,
   minimum=numeric(job.min),maximum=numeric(job.max),
   clientMeasured=complete and type(HARNESS_MODE)~="string" or false,
   warning="Gameplay FPS measurements require actual WoW-client sampling; UI click/marker alignment require screenshots."}
 self._fpsJob=nil
 return complete,self._fpsResult
end
function Acceptance:GetFPSStatus()
 if self._fpsJob then
  return {state="MEASURING",elapsedSeconds=numeric(self._fpsJob.elapsed),
    sampleCount=self._fpsJob.count,clientMeasured=false}
 end
 return self._fpsResult or {state="NOT_RUN",clientMeasured=false}
end
function Acceptance:Snapshot()
 local screenW=UIParent and UIParent.GetWidth and numeric(UIParent:GetWidth())
 local screenH=UIParent and UIParent.GetHeight and numeric(UIParent:GetHeight())
 local scale=UIParent and UIParent.GetEffectiveScale and numeric(UIParent:GetEffectiveScale())
 local window=JLP.StandaloneGatheringMap
 local frame=window and window.frame
 local visible=frame and frame.IsShown and frame:IsShown() or false
 local fps=type(GetFramerate)=="function" and numeric(GetFramerate()) or nil
 local shared=JLP:GetModule("GatheringSharedMapState")
 local opts=shared and shared:GetSnapshot()
 local route=JLP:GetModule("GatheringRoutePresentation")
 local result=route and opts and route:Build(opts.selectedMapID)
 return {viewport={width=screenW,height=screenH,scale=scale},standaloneVisible=visible,
  standalone={width=frame and frame.GetWidth and numeric(frame:GetWidth()),
   height=frame and frame.GetHeight and numeric(frame:GetHeight())},
  fpsSnapshot=fps,fpsMeasured=false,geometryClientVerified=false,
  timedFPS=self:GetFPSStatus(),controlGeometry=self:ControlGeometry(),
  refreshDiagnostics=window and window.GetRefreshDiagnostics and window:GetRefreshDiagnostics() or nil,
  routeStatus=result and result.status or "UNKNOWN",routeWorkflow=result and result.workflow or "UNKNOWN",
  mapID=opts and opts.selectedMapID,routeStops=result and result.stopCount or 0,
  statement="Client snapshot only. Screenshots, cursor/scroll/zoom alignment and timed FPS measurements require manual WoW acceptance."}
end
function Acceptance:GetSummary()
 local s=self:Snapshot()
 return "Gathering QA snapshot: UIParent "..tostring(s.viewport.width or "unknown").." x "..
  tostring(s.viewport.height or "unknown").." · scale "..tostring(s.viewport.scale or "unknown")..
  " · standalone "..tostring(s.standaloneVisible and "visible" or "hidden")..
  " · map "..tostring(s.mapID or "none").." · route "..tostring(s.routeWorkflow)..
  " / "..tostring(s.routeStops).." stops · FPS single sample "..tostring(s.fpsSnapshot or "unavailable")..
  " (single sample, NOT a benchmark). Timed FPS "..tostring(s.timedFPS.state)..
  " · visible control rectangles "..tostring(s.controlGeometry.visible)..
  ", outside viewport "..tostring(s.controlGeometry.outside)..
  " · map refresh checks/skipped "..tostring(s.refreshDiagnostics and s.refreshDiagnostics.checked or 0)..
  "/"..tostring(s.refreshDiagnostics and s.refreshDiagnostics.skipped or 0)..
  ". Screenshots and manual pointer/route alignment remain REQUIRED."
end
JLP:RegisterModule("GatheringClientAcceptance",Acceptance)
