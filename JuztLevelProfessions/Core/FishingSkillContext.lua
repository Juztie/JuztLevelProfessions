local _, JLP = ...
-- Only GetProfessionInfo's 8th return (skillModifier) may prove Fishing bonuses.
-- Unknown must not be treated as verified zero; cached skills never prove modifiers.
local Context={contract="jlp-fishing-skill-context-v1",nativeDispatchAllowed=false}
local function nonnegative(v)
 if type(v)=="number" and v==v and v>=0 and v~=math.huge then return v end
end
function Context:FromSnapshot(snapshot)
 local raw=type(snapshot)=="table" and nonnegative(snapshot.skill) or nil
 local bonus=type(snapshot)=="table" and not snapshot.cached and nonnegative(snapshot.skillModifier) or nil
 local known=raw~=nil and bonus~=nil
 local result={rawSkill=raw,observedBonus=bonus,effectiveSkill=known and raw+bonus or nil,
  bonusStatus=known and "OBSERVED_GET_PROFESSION_INFO" or "UNKNOWN",
  requirementSkill=raw,requirementBonus=bonus,comparisonStatus=known and "EFFECTIVE_OBSERVED" or "RAW_ONLY_CONSERVATIVE",
  nativeDispatchAllowed=false}
 return result
end
function Context:Describe(context)
 if not context or context.rawSkill==nil then return "Fishing skill unavailable · bonus UNKNOWN" end
 if context.effectiveSkill then
  return "Fishing raw "..tostring(context.rawSkill).." + observed bonus "..tostring(context.observedBonus)..
   " = effective "..tostring(context.effectiveSkill)
 end
 return "Fishing raw "..tostring(context.rawSkill).." · bonus UNKNOWN · effective UNKNOWN (raw-only check)"
end
JLP:RegisterModule("FishingSkillContext",Context)
