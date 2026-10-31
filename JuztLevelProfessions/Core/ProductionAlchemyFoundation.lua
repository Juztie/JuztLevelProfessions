local _, JLP = ...

local Foundation={
 contract="production-alchemy-readonly-foundation-v1",
 routeAuditContract="production-alchemy-current-build-route-audit-v2",
 previewContract="production-alchemy-planner-parity-preview-v2",
 sourceBuild=70245,
}
local EXPECTED_IDS={1245246,7183,3170,2331,2334,3171,3173,3176,11449,11450,11460,11467,17553}
local EXPECTED_TRAINERS={
 {cap=75,nextCap=150,requiredSkill=50,minCharacterLevel=10},
 {cap=150,nextCap=225,requiredSkill=125,minCharacterLevel=20},
 {cap=225,nextCap=300,requiredSkill=200,minCharacterLevel=35},
}

local function names(materials)
 local t={}; for _,m in ipairs(materials or {}) do t[m.name]=true end; return t
end

local function dataset()
 local provider=JLP:GetModule("ProfessionDatasetProvider")
 if provider and provider.GetCandidateDataset then return provider:GetCandidateDataset("ALCHEMY") end
 return nil,"dataset-provider-missing"
end

local function buildComparison(buildOverride)
 local svc=JLP:GetModule("ClientBuildInfo")
 if not svc then return {state="UNKNOWN",current=false,clientBuild=nil,clientBuildToken="unknown"} end
 if tonumber(buildOverride) then
  local b=tonumber(buildOverride)
  return svc:Compare(Foundation.sourceBuild,function() return "test-override",tostring(b),"test",JLP.Constants and JLP.Constants.TARGET_INTERFACE or 16001 end)
 end
 return svc:Compare(Foundation.sourceBuild)
end

function Foundation:AuditData(buildOverride)
 local d=dataset(); local errors={}; local seen={}; local expectedMin=1
 if type(d)~="table" then return {contract=self.routeAuditContract,structuralReady=false,ready=false,buildState="UNKNOWN",buildCurrent=false,errors={"dataset-missing"}} end
 if d.contract~="production-alchemy-readonly-candidate-dataset-v1" then errors[#errors+1]="candidate-contract" end
 if d.readOnly~=true or d.plannerEligible~=true or d.executionEligible~=false or d.nativeDispatchAllowed~=false or d.routeAuthorityEnabled~=false then errors[#errors+1]="authority-shape" end
 if tonumber(d.sourceBuild)~=self.sourceBuild then errors[#errors+1]="source-build" end
 if #(d.route or {})~=13 then errors[#errors+1]="route-count" end
 for i,s in ipairs(d.route or {}) do
  if tonumber(s.skillMin)~=expectedMin then errors[#errors+1]="route-gap:"..i end
  expectedMin=tonumber(s.skillTarget) or expectedMin
  if tonumber(s.recipeID)~=EXPECTED_IDS[i] then errors[#errors+1]="recipe-id:"..i end
  if seen[s.recipeID] then errors[#errors+1]="duplicate-id:"..tostring(s.recipeID) end; seen[s.recipeID]=true
  for _,m in ipairs(s.materials or {}) do if not tonumber(m.itemID) or not tonumber(m.quantity) or tonumber(m.quantity)<=0 then errors[#errors+1]="material:"..i end end
 end
 if expectedMin~=300 then errors[#errors+1]="route-end" end
 -- Historical candidate row 1 targets spell 1245246 before its Forever skill gate.
 -- Static readiness requires the public-backed *read-only* starter correction,
 -- not optional NPC inspection or an unverified low-skill fallback.
 local starter=JLP:GetModule("ForeverStarterRoute")
 local starterResolved=starter and starter.Resolve and select(1,starter:Resolve("ALCHEMY")) or nil
 if not starterResolved then errors[#errors+1]="starter-skill-gate-unresolved" end

 local trainers=d.trainerGates or {}
 if #trainers~=#EXPECTED_TRAINERS then errors[#errors+1]="trainer-count" end
 for i,expected in ipairs(EXPECTED_TRAINERS) do
  local gate=trainers[i] or {}
  for field,value in pairs(expected) do
   if tonumber(gate[field])~=value then errors[#errors+1]="trainer-"..field..":"..i end
  end
 end

 local defense=names(d.route[2] and d.route[2].materials); local mana=names(d.route[4] and d.route[4].materials)
 if not (defense.Silverleaf and defense.Peacebloom and defense["Empty Vial"]) then errors[#errors+1]="minor-defense-current-materials" end
 if not (mana.Mageroyal and mana.Peacebloom and mana["Empty Vial"]) or mana.Silverleaf then errors[#errors+1]="minor-mana-current-materials" end

 -- Current public reference parity is independent of optional NPC snapshots.
 local candidateView=JLP:GetModule("ForeverAlchemyCandidateView")
 local effective,routeReason=candidateView and candidateView:Build("ALCHEMY",d)
 if not effective then errors[#errors+1]="candidate-forever-route:"..tostring(routeReason or "missing-adapter") end
 local compare=buildComparison(buildOverride)
 local structuralReady=#errors==0
 return {
  contract=self.routeAuditContract,
  structuralReady=structuralReady,
  ready=structuralReady, -- read-only candidate readiness is client-build independent
  errors=errors,
  readOnlyStarterResolved=starterResolved~=nil,
  readOnlyEffectiveCandidateReady=effective~=nil,
  readOnlyEffectiveCandidateCount=effective and #effective.steps or 0,
  routeCount=#(d.route or {}),
  trainerCount=#trainers,
  recipeIdentityCount=(function() local n=0 for _ in pairs(d.recipeIdentities or {}) do n=n+1 end return n end)(),
  sourceBuild=d.sourceBuild,
  liveBuild=compare.clientBuild,
  clientBuildToken=compare.clientBuildToken,
  buildState=compare.state,
  buildCurrent=compare.state=="CURRENT",
  legacyMaterialDriftCount=2,
 }
end

function Foundation:BuildReadOnlyPreview(skill,maxSkill)
 local d=dataset(); if not d then return nil,"dataset-missing" end
 local planner=JLP:GetModule("Planner"); if not planner then return nil,"planner-missing" end
 local before=0; local dispatch=JLP:GetModule("NativeDispatchService"); if dispatch and dispatch.GetHistory then before=#(dispatch:GetHistory() or {}) end
 local profession={key="ALCHEMY",name="Alchemy",skill=tonumber(skill) or 1,maxSkill=tonumber(maxSkill) or 75,learned=true}
 local plan=planner:BuildProfessionPlanForDataset("ALCHEMY",profession,d)
 if not plan then return nil,"plan-missing" end
 plan.readOnly=true; plan.productionCandidate=true; plan.candidateContract=d.contract; plan.executionEligible=false; plan.nativeDispatchAllowed=false
 local req=JLP:GetModule("RequirementPlan"); local requirements=req and req:Build("ALCHEMY",plan) or nil
 local cr=JLP:GetModule("CraftReadiness"); local readiness=cr and cr:Get("ALCHEMY",plan) or nil
 local aq=JLP:GetModule("ActionQueue"); local queue=aq and aq:Build("ALCHEMY",plan,readiness) or nil
 local acq=JLP:GetModule("AcquisitionPlanner"); local acquisition=acq and acq.BuildReadOnlyForPlan and acq:BuildReadOnlyForPlan("ALCHEMY",plan) or nil
 local after=before; if dispatch and dispatch.GetHistory then after=#(dispatch:GetHistory() or {}) end
 return {contract=self.previewContract,readOnly=true,executionEligible=false,nativeDispatchAllowed=false,plan=plan,requirements=requirements,readiness=readiness,queue=queue,acquisition=acquisition,nativeDispatchDelta=after-before}
end

function Foundation:Evaluate(buildOverride)
 local a=self:AuditData(buildOverride); local p=self:BuildReadOnlyPreview(1,75); local reg=JLP:GetModule("ProfessionRegistry"); local def=reg and reg:Get("ALCHEMY")
 local structuralReady=a.structuralReady and p and p.nativeDispatchDelta==0 and def and def.maturity and def.maturity.production==false and def.maturity.candidate==true
 local ready=structuralReady -- no native rights; source/live build relation is advisory
 local state
 if not structuralReady then state="production-alchemy-readonly-foundation-blocked"
 else state="production-alchemy-readonly-foundation-ready" end
 return {
  state=state,
  ready=ready and true or false,
  structuralReady=structuralReady and true or false,
  buildCurrent=a.buildCurrent,
  promotionReady=false,
  audit=a,
  preview=p,
  productionEnabled=def and def.maturity.production==true or false,
  candidate=def and def.maturity.candidate==true or false,
 }
end

function Foundation:GetSummary()
 local e=self:Evaluate(); local a=e.audit or {}
 return string.format("Alchemy production candidate: %s · route %d/13 · identities %d/13 · trainers %d/3 · source build %s · live build %s · build state %s · client %s · promotion ready no · production enabled no · native dispatch forbidden", tostring(e.state), tonumber(a.routeCount) or 0, tonumber(a.recipeIdentityCount) or 0, tonumber(a.trainerCount) or 0, tostring(a.sourceBuild or "?"), tostring(a.liveBuild or "unknown"), tostring(a.buildState or "UNKNOWN"), tostring(a.clientBuildToken or "forever:unknown|interface:unknown"))
end

function Foundation:ValidateStaticDataset()
 local a=self:AuditData(self.sourceBuild)
 return a.structuralReady and {} or a.errors
end

function Foundation:ValidateLiveEnvironment()
 local e=self:Evaluate()
 return e.ready and {} or {e.state}
end

function Foundation:Validate()
 return self:ValidateStaticDataset()
end

JLP:RegisterModule("ProductionAlchemyFoundation",Foundation)
