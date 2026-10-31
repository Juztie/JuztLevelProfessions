local _, JLP = ...
-- Alpha172: display-only Fishing isolation; route and layer SavedVariables stay shared.
local Policy={contract="jlp-gathering-view-layer-policy-v1",nativeDispatchAllowed=false}
function Policy:ForView(view,scope,includeGathering)
    if type(view)~="table" then return view end
    if scope~="FISHING" or includeGathering==true then return view end
    local overlay=view.overlay
    local routes=view.routeSnapshot
    if not overlay and not routes then return view end
    local filtered={}
    for key,value in pairs(view) do filtered[key]=value end
    if type(overlay)=="table" then
        if self._overlaySource~=overlay then
            local display={}
            for key,value in pairs(overlay) do display[key]=value end
            display.points={};display.total=0;display.enabled=false;display.observationCount=0
            self._overlaySource=overlay;self._overlayFiltered=display
        end
        -- Cache only immutable overlay identity, not player/map state.
        filtered.overlay=self._overlayFiltered
    end
    filtered.routeSnapshot=nil
    filtered.routeStatus="NO_ACTIVE_ROUTE"
    filtered.fishingFocus=true
    return filtered
end
function Policy:FilterStandalone(view,scope,includeGathering)
    return self:ForView(view,scope,includeGathering)
end
JLP:RegisterModule("GatheringViewLayerPolicy",Policy)
