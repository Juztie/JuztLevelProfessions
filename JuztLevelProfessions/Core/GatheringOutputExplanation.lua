local _,JLP=...
-- Read-only output transparency. This is NOT a drop table, chance estimate or
-- authorization to gather, craft or treat historical positions as active.
local M={contract="jlp-gathering-output-explanation-v1",nativeDispatchAllowed=false}
local kindLabels={PRIMARY="Primary material",POSSIBLE_BYPRODUCT="Possible extra output",
 QUEST_ONLY="Quest material only",EPHEMERAL="Temporary quest material",
 POSSIBLE="Encounter-dependent possibility"}
function M:Describe(profession,resource)
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 local info=bridge and bridge:GetOutputCandidates(profession,resource)
 if not info then return {status="UNKNOWN",headline="Output identity unknown",outputs={},nativeDispatchAllowed=false} end
 local out={professionKey=profession,resourceKey=resource,status=info.sourceStatus,
   sourceURL=info.sourceURL,outputs={},notLiveSpawn=true,nativeDispatchAllowed=false}
 local eligible=0
 for _,candidate in ipairs(info.outputs or {}) do
  local kind=candidate.kind or "UNKNOWN"
  local row={itemID=candidate.itemID,kind=kind,
   kindLabel=kindLabels[kind] or "Unverified output",
   smartAllowed=candidate.smartAllowed==true,
   -- No output chance implied by the scoring weight.
   priorityWeight=candidate.smartAllowed and candidate.weight or 0,
   notGuaranteed=true,sourceURL=candidate.sourceURL or out.sourceURL}
  out.outputs[#out.outputs+1]=row
  if row.smartAllowed then eligible=eligible+1 end
 end
 out.smartOutputCount=eligible
 if eligible>0 then
  out.headline="Documented Smart candidate; no guaranteed drops"
 elseif #out.outputs>0 then
  out.headline="Known item identity; excluded from ordinary Smart Materials"
 else
  out.headline="Output identity not verified for Smart Materials"
 end
 return out
end
function M:TooltipLines(profession,resource)
 local detail=self:Describe(profession,resource)
 local lines={detail.headline}
 for _,out in ipairs(detail.outputs) do
  lines[#lines+1]=out.kindLabel.." · item "..tostring(out.itemID)..
    (out.smartAllowed and " · eligible ranking signal" or " · excluded from Smart")
 end
 if #detail.outputs==0 then lines[#lines+1]="No documented itemID; no material-based route recommendation" end
 lines[#lines+1]="Evidence only: not a drop probability or live node"
 return lines
end
function M:ExplainNeed(profession,resource,needs)
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 local match=bridge and bridge:MatchMaterialNeeds(profession,resource,needs)
 local out={qualified=match and match.qualified==true or false,
  itemID=match and match.itemID,kind=match and match.outputKind,
  missing=match and match.missing or 0,weightedDemand=match and match.weightedDemand or 0,
  noGuaranteedLoot=true,nativeDispatchAllowed=false}
 if out.qualified then
  out.summary="Matched item "..tostring(out.itemID).." ("..
   (out.kind=="PRIMARY" and "primary" or "possible extra")..
   ") · missing "..tostring(out.missing).." · no guaranteed yield"
 else out.summary=self:Describe(profession,resource).headline end
 return out
end
function M:RouteHeadline(routes)
 if type(routes)~="table" then return nil end
 for _,profession in ipairs({"HERBALISM","MINING"}) do
  local route=routes[profession]
  for _,point in ipairs(route and route.points or {}) do
   local why=point.smartReasons
   if why and why.materialItemID then
    local kind=why.materialOutputKind=="POSSIBLE_BYPRODUCT" and "possible extra" or "primary"
    return profession..": item "..tostring(why.materialItemID).." ("..kind.."; no guaranteed yield)"
   end
  end
 end
 return nil
end
JLP:RegisterModule("GatheringOutputExplanation",M)
