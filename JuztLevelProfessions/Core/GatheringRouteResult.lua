local _, JLP = ...
-- Text-only, advisory route status receipts. No native actions or persistent
-- state. Both map entrypoints use the same explicit error vocabulary.
local Result={contract="jlp-gathering-route-result-v1",nativeDispatchAllowed=false}
local hints={
 STATE_UNAVAILABLE="Reopen the gathering guide after the addon initializes.",
 MAP_UNAVAILABLE="Select a supported zone and retry.",
 MAP_ID_INVALID="Choose a valid zone and retry.",
 ROUTE_SERVICE_UNAVAILABLE="The route planner is unavailable. Reopen the addon or reload the UI.",
 NO_VERIFIED_FISHING_POOL_POINTS="Fishing catch areas are not verified pool waypoints. Enable Herb/Ore layers for a gathering route.",
 FISHING_ONLY_CONTEXT="Fishing-only mode cannot cancel a hidden gathering route.",
 NO_ELIGIBLE_ROUTE="Try another zone, profession or route focus.",
 NO_ELIGIBLE_NODES="Try a different resource selection or route source.",
 NO_SELECTED_ROUTE_POINTS="Select resource types with historical reference points.",
 NO_MATERIAL_DEMAND="Try Skill or Balanced focus, or Custom resource selection.",
 ROUTE_CANCEL_PARTIAL="Some route engines stopped but others did not confirm cancellation; retry manually.",
 ROUTE_CANCEL_REJECTED="Route engine rejected cancellation; route is not confirmed cleared.",
 ROUTE_CANCEL_UNCONFIRMED="Route engine did not confirm cancellation; keep route until verified.",
 PLAYER_POSITION_UNAVAILABLE="Use a Loop route or move to the selected zone.",
 ROUTE_CONTEXT_CHANGED="Profession skill, imported references or personal observation history changed. Generate the route again.",
 CANCEL_UNCONFIRMED_PRESENTATION_QUARANTINED="Previous route cannot be presented until the active engine is safely restarted.",
 MAP_ART_UNAVAILABLE="Select another client-supported zone.",
}
local errors={ROUTE_ERROR=true,ROUTE_SERVICE_UNAVAILABLE=true,STATE_UNAVAILABLE=true,
 MAP_ART_UNAVAILABLE=true,GATHERING_DATA_UNAVAILABLE=true,DB_NOT_READY=true,
 INTERNAL_ERROR=true,ROUTE_ENGINE_UNAVAILABLE=true,ROUTE_CANCEL_PARTIAL=true,
 ROUTE_CANCEL_REJECTED=true,ROUTE_CANCEL_UNCONFIRMED=true}
local rejected={MAP_UNAVAILABLE=true,MAP_ID_INVALID=true,SHAPE_INVALID=true,
 PLAYER_POSITION_UNAVAILABLE=true,NO_VERIFIED_FISHING_POOL_POINTS=true,
 FISHING_ONLY_CONTEXT=true,SELECTION_INVALID=true,FOCUS_INVALID=true,
 MODE_INVALID=true,PROFESSION_NOT_LEARNED=true}
local empty={NO_ELIGIBLE_ROUTE=true,NO_ELIGIBLE_NODES=true,
 NO_SELECTED_ROUTE_POINTS=true,NO_MATERIAL_DEMAND=true}
local cancelled={CANCELLED=true,CLEARED_BY_USER=true,MODE_OR_FOCUS_CHANGED=true,
 MAP_SELECTION_CHANGED=true,CURRENT_ZONE_CHANGED=true,ROUTE_SOURCE_CHANGED=true,
 ROUTE_CONTEXT_CHANGED=true,CANCEL_UNCONFIRMED_PRESENTATION_QUARANTINED=true}
function Result:FromStatus(status, reason)
 local code=tostring(reason or status or "ROUTE_UNAVAILABLE")
 local state=status or code
 local phase,text
 if state=="READY" then phase="READY";text="Route ready"
 elseif state=="GENERATING" then phase="GENERATING";text="Generating route..."
 elseif empty[state] or empty[code] then phase="EMPTY";text="No eligible route: "..code
 elseif cancelled[state] or cancelled[code] then phase="CANCELLED";text="Route cancelled; selections preserved"
 elseif state=="IDLE" or state=="NO_ACTIVE_ROUTE" then phase="IDLE";text="No active route"
 elseif errors[state] or errors[code] or code:match("^ROUTE_.*ERROR$") or code:match("_UNAVAILABLE$") and not rejected[code] then
     phase="ERROR";text="Route planner error: "..code
 elseif rejected[state] or rejected[code] then phase="REJECTED";text="Route request declined: "..code
 else phase="ERROR";text="Route status unknown: "..code end
 return {contract=self.contract,phase=phase,code=code,message=text,
     detail=hints[code] or (phase=="READY" and "Historical waypoints; not live spawns." or
       phase=="GENERATING" and "Historical reference points are being processed." or
       phase=="CANCELLED" and "Generate a route again when ready." or
       phase=="IDLE" and "Choose resources or a Smart goal, then Generate Route." or
       "Check the selected zone and route settings."),nativeDispatchAllowed=false}
end
function Result:FromAttempt(ok,reason,status)
 if ok then return self:FromStatus(status or "GENERATING") end
 return self:FromStatus(reason or "ROUTE_UNAVAILABLE")
end
-- Newly bound receipts MUST have a valid, nonempty full context token. A
-- missing/broken service may display immediate transient feedback, but that
-- feedback never survives the next refresh or a change of route settings.
-- Legacy map-only receipts require an explicit opt-in marker; new Bind never
-- creates that marker. No SavedVariables or native action is involved.
local function token(router,mapID)
 if type(router)~="table" or type(router.GetContextToken)~="function" then return nil end
 local ok,value=pcall(router.GetContextToken,router,mapID)
 if ok and type(value)=="string" and value~="" then return value end
 return nil
end
function Result:Bind(receipt,mapID,router)
 if type(receipt)~="table" then return receipt end
 receipt.mapID=mapID
 receipt.contextToken=token(router,mapID)
 receipt.identityPolicy=receipt.contextToken and "context-token-v1" or "transient-unverified"
 return receipt
end
function Result:IsCurrent(receipt,mapID,router)
 if type(receipt)~="table" or receipt.mapID~=mapID then return false end
 if receipt.identityPolicy=="legacy-map-only" and receipt.contextToken==nil then
     return receipt.mapID==mapID
 end
 if receipt.identityPolicy=="transient-unverified" then return false end
 if type(receipt.contextToken)~="string" or receipt.contextToken=="" then return false end
 return receipt.contextToken==token(router,mapID)
end
JLP:RegisterModule("GatheringRouteResult",Result)
