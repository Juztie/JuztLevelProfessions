local _,JLP=...
local M={contract="JLP-FOREVER-MINING-NODE-ADVISORY-210",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local function valid(n)
 return type(n)=="number" and n==n and n==math.floor(n) and n>=1 and n<=300
end
local function copy(t)
 local out={};for _,v in ipairs(t or {}) do out[#out+1]=v end;return out
end
function M:AtSkill(key,skill)
 if key~="MINING" then return nil,"NOT_MINING" end
 if not valid(skill) then return nil,"INVALID_SKILL" end
 local data=JLP.data and JLP.data.foreverMiningNodeProgression210
 if not (data and type(data.recommendedBands)=="table" and
   type(data.nodeRequirements)=="table") then return nil,"SOURCE_UNAVAILABLE" end
 local result={professionKey=key,skill=skill,sourceURL=data.guideURL,
  sourceQualifier="FOREVER_PUBLIC_GUIDE_NOT_CLIENT_OBSERVATION",
  readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  canonicalMapID=nil,canonicalWaypoint=nil,coordinateAuthority=false,
  navigationStatus="LOCATION_UNVERIFIED",routeEligibility=false,
  nodes={},suggestedZones={},nextUnlock=nil,expectedGathers=nil,
  skillUpGuaranteed=false,observedNode=false,materialYieldAuthority=false,
  eventReceipt="REQUIRED",rankTraining="VERIFY_AT_SKILL_CAP",
  nextAction="MINE_MANUALLY_AND_RECHECK_SKILL"}
 if skill==300 then
  result.status="SKILL_CAP_REACHED";result.nextAction="NONE";return result
 end
 local band
 for _,b in ipairs(data.recommendedBands) do
  if skill>=b.start and skill<b.stop then band=b;break end
 end
 if band then
  result.coverage="FOREVER_GUIDE_RECOMMENDED_BAND"
  result.bandStart=band.start;result.bandEnd=band.stop
  result.suggestedZones=copy(band.zones)
 else
  result.coverage="FOREVER_NODE_REQUIREMENT_REFERENCES_ONLY"
  result.bandStart=225;result.bandEnd=300
 end
 local lookup={}
 for _,node in ipairs(data.nodeRequirements) do
  if type(node[1])=="string" and valid(node[2]) then
   lookup[node[1]]=node
   if node[2]>skill and (not result.nextUnlock or node[2]<result.nextUnlock.minimumSkill) then
    result.nextUnlock={name=node[1],minimumSkill=node[2]}
   end
  end
 end
 local candidates={}
 if band then
  for _,name in ipairs(band.nodes) do
   if lookup[name] then candidates[#candidates+1]=lookup[name] end
  end
 else
  -- 225+ recommendations rely on the published node table only, not on
  -- an invented 225-300 route. Include 175+ nodes as valid alternatives.
  for _,node in ipairs(data.nodeRequirements) do
   if node[2]>=175 and node[2]<=skill then candidates[#candidates+1]=node end
  end
  table.sort(candidates,function(a,b)
   if a[2]~=b[2] then return a[2]>b[2] end
   return a[1]<b[1]
  end)
 end
 for _,node in ipairs(candidates) do
  if node[2]<=skill and #result.nodes<6 then
   result.nodes[#result.nodes+1]={name=node[1],resource=node[1],
    minimumSkill=node[2],requiredSkill=node[2],
    suggestedZones=copy(node[3]),source="FOREVER_MINING_NODE_DIFFICULTY_TABLE",
    observedSpawn=false,skillUpGuaranteed=false}
  end
 end
 if not band and #result.nodes>0 then
  result.suggestedZones=copy(result.nodes[1].suggestedZones)
 end
 result.smelting={skillupKnownLimit=data.smeltSkillupMax,
  skillupAvailableAfter185=false,
  between140And155NoSmeltingSkillups=skill>=data.smeltGapStart and skill<data.smeltGapEnd,
  evaluation="SOURCE_ONLY_NOT_A_NATIVE_CRAFT_PERMISSION"}
 result.status=#result.nodes>0 and "SOURCE_BACKED_MANUAL_GATHER" or "VERIFY_SOURCE_AND_SKILL"
 return result
end
function M:Coverage()
 local summary={guideBands=0,nodeReferenceOnly=0,uncovered=0,
  observedSkillUps=0,canonicalRoutes=0}
 for skill=1,299 do
  local r=self:AtSkill("MINING",skill)
  if r and #r.nodes>0 and r.coverage=="FOREVER_GUIDE_RECOMMENDED_BAND" then
   summary.guideBands=summary.guideBands+1
  elseif r and #r.nodes>0 then summary.nodeReferenceOnly=summary.nodeReferenceOnly+1
  else summary.uncovered=summary.uncovered+1 end
 end
 return summary
end
-- Same canonical gathering registry used by the map. Public/historical points
-- are independent of personal observations and never live-spawn promises.
local function copyValue(t)
 if type(t)~="table" then return t end
 local out={};for k,v in pairs(t)do out[k]=copyValue(v)end;return out
end
function M:GetNodeContract(resource,objectID)
 local data=JLP.data and JLP.data.foreverMiningNodeProgression210
 for _,r in ipairs(data and data.nodeContracts or {})do
  if r.resourceKey==resource and (objectID==nil or r.objectID==objectID)then return copyValue(r)end
 end
end
function M:GetObjectContract(objectID)
 local data=JLP.data and JLP.data.foreverMiningNodeProgression210
 for _,r in ipairs(data and data.nodeContracts or {})do if r.objectID==objectID then return copyValue(r)end end
end
function M:GetWaypoint(itemID,id)
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 return bridge and bridge:GetNodeWaypoint("MINING",itemID,id)
end
function M:SelectSource(itemID,skill,progression,unavailable)
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 return bridge and bridge:SelectNodeSource("MINING",itemID,skill,progression,unavailable)
end
function M:GetPlan(profession)
 local skill=profession and profession.cached~=true and tonumber(profession.skill)
 local cap=profession and profession.cached~=true and tonumber(profession.maxSkill)
 local p={key="MINING",profession=profession,readOnly=true,nativeDispatchAllowed=false,executionEligible=false,materials={}}
 local c={kind="verify",profession="MINING",skill=skill,nativeDispatchAllowed=false,executionEligible=false,
  skillUpProbability="UNKNOWN",expectedGathers=nil,readOnly=true}
 local shared=JLP:GetModule("GatheringSharedMapState");local snap=shared and shared:GetSnapshot()
 local goal=snap and snap.supplyGoal;goal=goal and goal.professionKey=="MINING" and goal or nil
 if not valid(skill)then c.nextAction="Observe current Mining ownership and skill."
 elseif skill==300 and not goal then c.kind="complete";c.nextAction="Mining skill goal reached; material gathering can continue independently."
 elseif cap~=75 and cap~=150 and cap~=225 and cap~=300 then c.nextAction="Observe actual Mining rank/cap; UNKNOWN is not Apprentice."
 elseif goal and goal.origin=="AUTOMATIC_PLAN" and goal.status=="VERIFY_OWNER" then
  c.nextAction=goal.nextAction
 elseif goal and type(goal.required)=="number" then
  -- Resolve the concrete supply action before applying node-only tools or
  -- skill-progression rank gates. The producer keeps its own learned, skill,
  -- schematic, reagent and station checks; a cap does not forbid preparation.
  local bridge=JLP:GetModule("GatheringMaterialBridge")
  c.materialSupply=bridge and bridge.SelectMiningSupply and
   bridge:SelectMiningSupply(goal.itemID,goal.required,goal.strategy,goal.ownerProfession)
  local supplied=c.materialSupply
  local kinds={SMELT="smelt",MINING="gather",BANK="bank",AUCTION="acquire"}
  c.kind=supplied and kinds[supplied.status]or "verify"
  c.nextAction=supplied and supplied.nextAction or "Replan material supply."
 elseif not goal and skill>=cap and cap<300 then
  c.kind="train";c.rank=cap==75 and "Journeyman"or cap==150 and "Expert"or "Artisan"
  c.nextAction="Learn "..c.rank.." Mining manually; observe changed cap before resuming. No character-level gate is inferred."
 else
   local bridge=JLP:GetModule("GatheringMaterialBridge")
    local source=self:SelectSource(goal and (goal.gatherItemID or goal.itemID),skill,not goal,bridge and bridge.unavailable)
    if source then
     c.kind="gather";c.miningSource=source
     local n=self:GetNodeContract(source.resourceKey,source.objectID)
     c.positiveProgressionEvidence=n.gray and skill<n.gray and "QUALIFIED_THRESHOLD_REFERENCE_NOT_PROBABILITY"or "ADVISORY_ONLY_CURRENT_DIFFICULTY_UNKNOWN"
     c.resourceReference=n
     c.nextAction="Visit "..n.name.." reference in "..source.zone.."; verify current node/access/difficulty, mine manually and observe loot, bags and skill separately."
    else c.nextAction="Verify a qualified Mining source; no available static point is known."end
 end
 p.recommendedCurrentStep=c;p.action=c.nextAction;p.actionKind=c.kind;p.status=c.kind
 if skill and cap and cap<300 then
  c.futureRank=cap==75 and "Journeyman"or cap==150 and "Expert"or "Artisan"
  c.rankLearningMinimum=cap==75 and 50 or cap==150 and 125 or 200
  c.rankAvailable=skill>=c.rankLearningMinimum;c.rankRequiredAtCap=skill>=cap
  c.rankGateScope="SKILL_PROGRESSION_NOT_QUALIFIED_MATERIAL_PREPARATION"
  c.characterLevelRequirement="NONE_LISTED_FOREVER_REFERENCE_VERIFY_CURRENT_OFFER"
 end
 local travel=JLP:GetModule("CurrentStepTravelBridge");if travel then travel:AttachPlan("MINING",p)end
 return p
end
JLP:RegisterModule("ForeverMiningNodeProgression210",M)
