local _,JLP=...
-- Read-only rank/access continuity. Contrasts public Forever names for Alchemy
-- with the original user research, retaining both as separate provenance. For
-- other crafting professions the original names are RESEARCH_ONLY. Rank caps
-- are research references, not actual live skill-cap or trainer observations.
local M={contract="JLP-PRIMARY-RANK-SOURCES-211",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local keys={ALCHEMY=true,BLACKSMITHING=true,ENGINEERING=true,LEATHERWORKING=true}
local tiers={{tier="Apprentice",cap=75},{tier="Journeyman",cap=150},
 {tier="Expert",cap=225},{tier="Artisan",cap=300}}
local function valid(n) return type(n)=="number" and n==math.floor(n) and n>=1 and n<=300 end
local function clone(row)
 local copy={}
 for k,v in pairs(row or {}) do if k~="nav" and k~="qualifiedNav" and
     k~="proposedNav" and k~="rawSourceNav" then copy[k]=v end end
 return copy
end
local function matched(proof,tier,name)
 if not proof or proof.contract~="JLP-FOREVER-ALCHEMY-RANK-211" then return false end
 local names=proof[string.lower(tier)]
 if type(names)~="table" then return false end
 for _,candidate in ipairs(names) do if name==candidate then return true end end
 return false
end
function M:AtSkill(key,skill,cap,faction)
 if not keys[key] or not valid(skill) then return nil,"UNSUPPORTED_OR_INVALID_PROFESSION_SKILL" end
 if faction~=nil and faction~="Horde" and faction~="Alliance" then
  return nil,"INVALID_FACTION" end
 local data=JLP.data and JLP.data.professionSources
 local ranks=data and data.rankRequirements and data.rankRequirements[key]
 local trainerSets=data and data.trainers and data.trainers[key]
 local external=JLP.data and JLP.data.foreverAlchemyRankCrosscheck211
 local result={contract=self.contract,profession=key,skill=skill,
  currentCap=valid(cap) and cap or nil,capObserved=valid(cap) and true or false,
  sourceURL=key=="ALCHEMY" and external and external.sourceURL or nil,
  sourceResearchOnly=key~="ALCHEMY" or not external,readOnly=true,nativeDispatchAllowed=false,
  executionEligible=false,progressionGuaranteed=false,clientRankObserved=false,
  canonicalNavigationAuthorized=false,ranks={},nextRank=nil}
 for _,tier in ipairs(tiers) do
  local row=nil
  for _,candidate in ipairs(ranks or {}) do
   if candidate.tier==tier.tier and candidate.skillCap==tier.cap then row=candidate;break end
  end
  local label=tier.tier.." "..(key:sub(1,1)..key:sub(2):lower())
  local actors=trainerSets and trainerSets[label]
  local rows=(type(actors)=="table" and faction=="Horde") and actors.Horde or nil
  local entry={rank=label,tier=tier.tier,skillCap=tier.cap,
   requiredSkill=row and row.requiredSkill or nil,
   minCharacterLevel=row and row.minCharacterLevel or nil,
   provenance=row and row.evidence or "UNKNOWN",
   trainerResearchCount=0,publicNameMatches=0,trainers={},
   trainingCurrentClientVerified=false,recipeLearningVerified=false,
   navigationQualified=false,nativeDispatchAllowed=false}
  for _,actor in ipairs(type(rows)=="table" and rows or {}) do
   if type(actor.name)=="string" and actor.name~="" then
    entry.trainerResearchCount=entry.trainerResearchCount+1
    local isMatch=key=="ALCHEMY" and matched(external,tier.tier,actor.name)
    if isMatch then entry.publicNameMatches=entry.publicNameMatches+1 end
    local safe=clone(actor)
    safe.publicNameCrosscheck=isMatch
    safe.identityStatus=isMatch and "PUBLIC_NAME_AND_RANK_CORROBORATED" or
      "USER_RESEARCH_ONLY"
    safe.currentClientStock="UNKNOWN"
    safe.currentClientTrainerAccess="UNKNOWN"
    safe.navigationQualified=false
    safe.readOnly=true
    entry.trainers[#entry.trainers+1]=safe
   end
  end
  entry.sourceStatus=entry.publicNameMatches>0 and
   "FOREVER_PUBLIC_TRAINER_NAME_RANK_CROSSCHECK" or "RESEARCH_TRAINER_ONLY"
  result.ranks[#result.ranks+1]=entry
  if not result.nextRank and tier.cap>skill then result.nextRank=entry end
 end
 if skill==300 then
  result.status="SKILL_CAP_REACHED"
  result.nextRank=nil
 elseif result.currentCap and skill>=result.currentCap and result.currentCap<300 then
  result.status="VERIFY_RANK_TRAINING_REQUIRED"
  for i,entry in ipairs(result.ranks) do
   if entry.skillCap==result.currentCap and result.ranks[i+1] then
    result.nextRank=result.ranks[i+1];break end
  end
 else result.status="REFERENCE_RANK_CONTINUITY_ONLY" end
 return result
end
function M:Coverage(key,faction)
 local totals={profession=key,positions=0,missingRanks=0,
  publicMatchedActors=0,clientVerifiedRankSteps=0,
  confirmedRecipeLearning=0,complete1300=false}
 if not keys[key] then return nil,"UNSUPPORTED_PROFESSION" end
 -- Every skill in 1..299 can be *classified*, not necessarily leveled.
 -- Rank source data is immutable; do not allocate 299 copies per forecast.
 totals.positions=299
 local item=self:AtSkill(key,1,nil,faction)
 for _,r in ipairs(item.ranks) do
  if r.trainerResearchCount==0 then totals.missingRanks=totals.missingRanks+1 end
  totals.publicMatchedActors=totals.publicMatchedActors+r.publicNameMatches
 end
 return totals
end
JLP:RegisterModule("PrimaryCraftingRankSources211",M)
