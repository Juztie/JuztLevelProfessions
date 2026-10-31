local _,JLP=...
-- Advisory odds independent of any client-evidence capture, AH scan, or build.
-- Current-client color beats historic thresholds. Historical GREEN boundary is
-- NOT present in the packed DB: the midpoint is a modelling assumption only.
local M={contract="JLP-SKILLUP-DEFAULTS-187",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false,
 defaults={ORANGE=1,YELLOW=0.60,GREEN=0.25,GRAY=0}}
local function integer(v)
 local n=tonumber(v)
 return n and n==n and n>=0 and n<math.huge and n==math.floor(n) and n or nil
end
local function tier(v)
 local s=type(v)=="string" and v:upper() or nil
 if s=="GREY" then s="GRAY" end
 if M.defaults[s]~=nil then return s end
 return nil
end
function M:ForTier(color,options)
 local t=tier(color)
 if not t then return {tier="UNKNOWN",probability=nil,source="TIER_UNKNOWN",
  estimated=true,nativeDispatchAllowed=false} end
 options=type(options)=="table" and options or {}
 local green=tonumber(options.greenProbability)
 if not green or green<0.20 or green>0.30 then green=self.defaults.GREEN end
 local n=t=="GREEN" and green or self.defaults[t]
 return {tier=t,probability=n,expectedCastsPerSkill=(n>0 and 1/n or nil),
   source=(t=="ORANGE" or t=="GRAY") and "COLOR_RULE" or "USER_APPROVED_SCENARIO",
   estimated=(t=="YELLOW" or t=="GREEN"),requiresClientEvidence=false,
   nativeDispatchAllowed=false}
end
function M:ForSource(skill,minimum,yellow,grey,liveTier,options)
 local t=tier(liveTier)
 local s=integer(skill);local lo=integer(minimum) or 0
 local y=integer(yellow);local g=integer(grey)
 if t then
  local result=self:ForTier(t,options)
  result.tierSource="CURRENT_UI_COLOR"
  return result
 end
 if not s or not g or s<lo or s>=g then
  local row={tier=s and g and s>=g and "GRAY" or "UNKNOWN",probability=nil,
      source="SOURCE_SKILL_OUTSIDE_OR_UNAVAILABLE",estimated=true,
      requiresClientEvidence=false,nativeDispatchAllowed=false}
  if row.tier=="GRAY" then row=self:ForTier("GRAY");row.tierSource="SOURCE_GRAY_CUTOFF" end
  return row
 end
 -- A qualified recipe may START yellow: equality is a zero-width orange
 -- band, not a missing threshold. Zero still means an unavailable DB field.
 if not y or y<lo or y==0 or y>=g then
  return {tier="UNKNOWN",probability=nil,source="HISTORIC_YELLOW_GRAY_INSUFFICIENT",
   estimated=true,requiresClientEvidence=false,nativeDispatchAllowed=false}
 end
 if s<y then t="ORANGE" else
  local estimatedBoundary=y+math.floor((g-y)/2)
  t=s<estimatedBoundary and "YELLOW" or "GREEN"
 end
 local result=self:ForTier(t,options)
 result.tierSource=s<y and "SOURCE_YELLOW_CUTOFF_REFERENCE" or "INFERRED_GREEN_BOUNDARY_MIDPOINT"
 result.transitionQualified=false
 if s>=y then result.estimated=true end
 return result
end
-- Existing RecipeTelemetry is a supported, optional adaptive estimator. It is
-- never a prerequisite for the fixed defaults and does not grant native rights.
function M:GetOptionalTelemetry(key,recipeID,recipeName)
 local service=JLP:GetModule("RecipeTelemetry")
 if not service or type(service.GetRecipe)~="function" then return nil end
 local ok,row=pcall(service.GetRecipe,service,key,recipeID,recipeName)
 if not ok or type(row)~="table" or row.historicalBuild==true or
    row.buildScope~="current-build-local" then return nil end
 local count=integer(row.skillObservedCrafts)
 local rate=tonumber(row.skillUpRate)
 if not count or count<8 or not rate or rate~=rate or rate<0 or rate>1 then return nil end
 return {observedRate=rate,sampleCount=count,source="OPTIONAL_CURRENT_BUILD_TELEMETRY",
  readOnly=true,nativeDispatchAllowed=false}
end
-- A positive, same-build and adequately sampled observation may refine
-- YELLOW/GREEN advisory odds. Absolute ORANGE/GRAY rules are never overridden.
-- The underlying telemetry is entirely optional for planning.
function M:ForRecipe(key,recipeID,recipeName,skill,minimum,yellow,grey,liveTier,options,telemetry)
 local result=self:ForSource(skill,minimum,yellow,grey,liveTier,options)
 if result.tier~="YELLOW" and result.tier~="GREEN" then return result end
 local observed=telemetry
 if observed==nil then observed=self:GetOptionalTelemetry(key,recipeID,recipeName) end
 if type(observed)=="table" then
  local rate=tonumber(observed.observedRate)
  local count=integer(observed.sampleCount)
  if observed.source=="OPTIONAL_CURRENT_BUILD_TELEMETRY" and count and count>=8 and
     rate and rate==rate and rate>0 and rate<=1 then
   -- Current-build recipe-global rate is an observed comparator. Explicitly
   -- classify its missing skill-band specificity as an advisory estimate.
   result.probability=rate
   result.expectedCastsPerSkill=1/rate
   result.source="OPTIONAL_CURRENT_BUILD_RECIPE_TELEMETRY"
   result.sampleCount=count
   result.observedGlobalNotBandSpecific=true
   result.estimated=true
  end
 end
 return result
end
JLP:RegisterModule("SkillUpProbabilityPlanner",M)
