local _,JLP=...
-- Source-bound advice and canonical gathering-reference handoff. No skill/item
-- credit, movement or native gathering/crafting permission.
local M={contract="herbalism-readonly-skill-guide-209",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local function valid(n) return type(n)=="number" and n==n and
 n==math.floor(n) and n>=1 and n<=300 end
local function copy(xs)
 local out={};for _,v in ipairs(xs or {}) do out[#out+1]=v end;return out
end
function M:AtSkill(key,skill)
 if key~="HERBALISM" then return nil,"NOT_HERBALISM" end
 if not valid(skill) then return nil,"INVALID_SKILL" end
 local data=JLP.data and JLP.data.foreverHerbalismProgression209
 if not data or type(data.nodes)~="table" or type(data.recommendedBands)~="table" then
  return nil,"SOURCE_UNAVAILABLE" end
 local result={professionKey=key,skill=skill,sourceURL=data.guideURL,
  sourceUpdated=data.guideUpdated,readOnly=true,nativeDispatchAllowed=false,
  executionEligible=false,coordinateAuthority=false,canonicalMapID=nil,
  navigationStatus="LOCATION_UNVERIFIED",routeEligibility=false,
  materialYieldAuthority=false,skillUpGuaranteed=false,expectedGathers=nil,
  trainerReferences={},trainerAccess="PUBLIC_IDENTITY_ONLY",trainerAvailability="UNKNOWN",
  trainerInventory="UNKNOWN",trainerCoordinateAuthority=false,
  eventReceipt="REQUIRED",nextAction="GATHER_MANUALLY_AND_RECHECK_SKILL",
  suggestedZones={},resources={},futureUnlock=nil,rankTraining="VERIFY_AT_SKILL_CAP"}
 -- Source gives actor identity, not a current training UI or a waypoint.
 for _,trainer in ipairs(data.hordeTrainerReferences or {}) do
  if type(trainer.npcID)=="number" and type(trainer.name)=="string" then
   result.trainerReferences[#result.trainerReferences+1]={
    npcID=trainer.npcID,name=trainer.name,zone=trainer.zone,kind=trainer.kind,
    actorSourceURL="https://www.wowhead.com/forever/npc="..trainer.npcID,
    trainerRankLearned="UNKNOWN",nativeDispatchAllowed=false,
    canonicalWaypoint=nil,navigationEligible=false,routeEligible=false}
  end
 end
 if skill==300 then result.status="SKILL_CAP_REACHED";result.nextAction="NONE";return result end
 local band
 for _,candidate in ipairs(data.recommendedBands) do
  if skill>=candidate.start and skill<candidate.stop then band=candidate;break end
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
 for _,node in ipairs(data.nodes) do
  if type(node[1])=="string" and valid(node[2]) then lookup[node[1]]=node end
 end
 local ordered={}
 if band then
  for _,name in ipairs(band.resources) do
   local node=lookup[name]
   if node then ordered[#ordered+1]=node end
  end
 else
  for _,node in ipairs(data.nodes) do
   if node[2]>=220 and node[2]<=skill then ordered[#ordered+1]=node end
  end
  table.sort(ordered,function(a,b)
   if a[2]~=b[2] then return a[2]>b[2] end
   return a[1]<b[1]
  end)
 end
 for _,node in ipairs(ordered) do
  if node[2]<=skill and #result.resources<6 then
   result.resources[#result.resources+1]={name=node[1],minimumSkill=node[2],
    suggestedZones=copy(node[3]),source="WOWHEAD_FOREVER_NODE_TABLE",
    observedSpawn=false,skillUpGuaranteed=false}
  end
 end
 if not band and #result.resources>0 then
  result.suggestedZones=copy(result.resources[1].suggestedZones)
 end
 for _,node in ipairs(data.nodes) do
  if node[2]>skill and (not result.futureUnlock or node[2]<result.futureUnlock.minimumSkill) then
   result.futureUnlock={name=node[1],minimumSkill=node[2]}
  end
 end
 result.status=#result.resources>0 and "SOURCE_BACKED_MANUAL_GATHER" or "VERIFY_SOURCE_AND_SKILL"
 -- Do not promote a nearby node without map-specific verified presence.
 return result
end
function M:Coverage()
 local counts={guideBands=0,nodeReferenceOnly=0,uncovered=0}
 for skill=1,299 do
  local row=self:AtSkill("HERBALISM",skill)
  if row and #row.resources>0 and row.coverage=="FOREVER_GUIDE_RECOMMENDED_BAND" then
   counts.guideBands=counts.guideBands+1
  elseif row and #row.resources>0 then counts.nodeReferenceOnly=counts.nodeReferenceOnly+1
  else counts.uncovered=counts.uncovered+1 end
 end
 counts.sourceQualifiedClientRoutes=0
 counts.actualObservedSkillUps=0
 return counts
end

local function copyValue(t)if type(t)~="table"then return t end;local x={};for k,v in pairs(t)do x[k]=copyValue(v)end;return x end
function M:GetNodeContract(resource,objectID)
 local data=JLP.data and JLP.data.foreverHerbalismProgression209
 for _,n in ipairs(data and data.nodeContracts or {})do if n.resourceKey==resource and (not objectID or n.objectID==objectID)then return copyValue(n)end end
end
function M:GetObjectContract(objectID)
 local data=JLP.data and JLP.data.foreverHerbalismProgression209
 for _,n in ipairs(data and data.nodeContracts or {})do if n.objectID==objectID then return copyValue(n)end end
end
function M:GetWaypoint(itemID,id)local b=JLP:GetModule("GatheringMaterialBridge");return b and b:GetNodeWaypoint("HERBALISM",itemID,id)end
function M:SelectSource(itemID,skill,progression,unavailable)local b=JLP:GetModule("GatheringMaterialBridge");return b and b:SelectNodeSource("HERBALISM",itemID,skill,progression,unavailable)end
function M:GetPlan(profession)
 local skill=profession and profession.cached~=true and profession.skill
 local cap=profession and profession.cached~=true and profession.maxSkill
 local p={key="HERBALISM",profession=profession,readOnly=true,nativeDispatchAllowed=false,executionEligible=false,materials={}}
 local c={kind="verify",profession="HERBALISM",skill=skill,skillUpProbability="UNKNOWN",expectedGathers=nil,readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
 local shared=JLP:GetModule("GatheringSharedMapState");local snap=shared and shared:GetSnapshot();local goal=snap and snap.supplyGoal;goal=goal and goal.professionKey=="HERBALISM"and goal
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 -- Bank/purchase does not require gathering ownership, a gathering rank or a tool.
 if goal and goal.origin=="AUTOMATIC_PLAN" and goal.status=="VERIFY_OWNER" then
  c.nextAction=goal.nextAction
 elseif goal and type(goal.required)=="number"and bridge then
  c.materialSupply=bridge:SelectHerbalismSupply(goal.itemID,goal.required,goal.strategy,goal.ownerProfession)
  local supplied=c.materialSupply;local kinds={HERBALISM="gather",BANK="bank",AUCTION="acquire"}
  c.kind=supplied and kinds[supplied.status]or "verify";c.nextAction=supplied and supplied.nextAction or "Replan Alchemy supply."
 elseif not valid(skill)then c.nextAction="Observe current Herbalism ownership and skill; no positive own-gathering readiness."
 elseif skill==300 and not goal then c.kind="complete";c.nextAction="Herbalism skill goal reached; material gathering can continue independently."
 elseif cap~=75 and cap~=150 and cap~=225 and cap~=300 then c.nextAction="Observe actual Herbalism rank/cap; UNKNOWN is not Apprentice."
 elseif skill>=cap and cap<300 and not goal then
  c.kind="train";c.rank=cap==75 and "Journeyman"or cap==150 and "Expert"or "Artisan"
  c.nextAction="Learn "..c.rank.." Herbalism manually; verify the current trainer offer and observe changed cap before more skill progression."
 else
  local source=self:SelectSource(goal and goal.itemID,skill,not goal,bridge and bridge.unavailable)
  if source then c.kind="gather";c.herbalismSource=source;local n=self:GetNodeContract(source.resourceKey,source.objectID);c.resourceReference=n
   c.positiveProgressionEvidence=n.gray and skill<n.gray and "QUALIFIED_THRESHOLD_REFERENCE_NOT_PROBABILITY"or "NOT_EXPECTED_SKILL_PROGRESS_MATERIAL_ONLY"
   c.nextAction="Visit "..n.name.." reference in "..source.zone.."; harvest manually, verify current node/difficulty and observe loot, bags and skill separately. "..n.accessNote
  else c.nextAction="Verify an eligible Herbalism source; no qualified available static point is known."end
 end
 if type(skill)=="number"and (cap==75 or cap==150 or cap==225)then
  c.futureRank=cap==75 and "Journeyman"or cap==150 and "Expert"or "Artisan";c.rankLearningMinimum=cap==75 and 50 or cap==150 and 125 or 200
  c.rankAvailable=skill>=c.rankLearningMinimum;c.rankRequiredAtCap=skill>=cap;c.rankGateScope="SKILL_PROGRESSION_NOT_QUALIFIED_MATERIAL_ACTION"
  c.characterLevelRequirement="FOREVER_EXTERNAL_NO_LEVEL_REQUIREMENT_VERIFY_CURRENT_OFFER"
 end
 p.recommendedCurrentStep=c;p.action=c.nextAction;p.actionKind=c.kind;p.status=c.kind
 local travel=JLP:GetModule("CurrentStepTravelBridge");if travel then travel:AttachPlan("HERBALISM",p)end
 return p
end
JLP:RegisterModule("ForeverHerbalismProgression209",M)
