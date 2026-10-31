local _,JLP=...
-- P0-228: on-demand source-evidence coverage for all twelve professions.
-- Coverage of advisory references is NOT continuity of player skill gains.
-- No native calls, owner sync, waypoint coordinates, persistent receipts or fabricated yields.
local M={contract="JLP-TWELVE-PROFESSION-SOURCE-COVERAGE-228",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false}
local class={ALCHEMY="CRAFT",BLACKSMITHING="CRAFT",ENGINEERING="CRAFT",
 LEATHERWORKING="CRAFT",TAILORING="CRAFT",ENCHANTING="CRAFT",
 COOKING="SECONDARY_CRAFT",FIRST_AID="SECONDARY_CRAFT",
 HERBALISM="GATHER",MINING="GATHER",SKINNING="GATHER",FISHING="FISH"}
local function skillValid(n)return type(n)=="number" and n==math.floor(n) and n>=1 and n<=300 end
local function integer(n)return type(n)=="number" and n==math.floor(n) and n>0 and n<math.huge end
local function sourceProof(row)
 if row.proofTier=="SOURCE_SKILL_AND_REAGENTS" and
   type(row.recipeID)=="number" and # (row.reagentsPerCraft or {})>0 then
  return "EXACT_RECIPE_REAGENT_SKILL_REFERENCE"
 end
 if row.proofTier=="REAGENTS_ONLY_WINDOW_UNVERIFIED" and
   type(row.recipeID)=="number" and #(row.reagentsPerCraft or {})>0 then
  return "EXACT_RECIPE_REAGENT_RESEARCH_WINDOW"
 end
 return "UNQUALIFIED_RESEARCH_WINDOW"
end
local function make(key,skill,level,extra)
 local out={professionKey=key,skill=skill,sourceLevel=level,
  canGuaranteeNextSkill=false,observedCraft=false,observedSkillUp=false,
  recipeLearned=nil,materialsInBagsKnown=false,expectedCrafts=nil,
  materialBudget=nil,trainerStockVerified=false,canonicalWaypointVerified=false,
  nativeDispatchAllowed=false,executionEligible=false,readOnly=true}
 for k,v in pairs(extra or {}) do out[k]=v end
 return out
end
-- Reference windows loaded only on deliberate 1-300 forecast, never on UI repaint.
local function primaryWindows(key,first,slots)
 local planner=JLP:GetModule("ForeverSkillBandPlanner")
 local ok,route=false,nil
 if planner and type(planner.BuildContinuity)=="function" then
  ok,route=pcall(planner.BuildContinuity,planner,key,first)
 end
 if ok and type(route)=="table" then
  for _,r in ipairs(route.segments or {}) do
   if integer(r.fromSkill) and integer(r.toSkill) and r.toSkill<=300 and r.fromSkill<r.toSkill then
    local level=sourceProof(r)
    for skill=math.max(first,r.fromSkill),math.min(299,r.toSkill-1) do
     slots[skill]=make(key,skill,level,{recipeID=r.recipeID,
      recipe=r.recipe,recipeSourceURL=r.recipeSourceURL,
      reagentEvidence=r.evidenceMatrix and r.evidenceMatrix.reagentSet or "UNKNOWN",
      learningEvidence=r.evidenceMatrix and r.evidenceMatrix.learningAccess or "UNKNOWN",
      yieldEvidence=r.evidenceMatrix and r.evidenceMatrix.outputYield or "UNKNOWN",
      skillMinimumEvidence=r.evidenceMatrix and r.evidenceMatrix.skillMinimum or "UNKNOWN",
      referenceState=r.referenceState,sourceProvenance="FOREVER_SKILL_BAND_RESEARCH_220_225"})
    end
   end
  end
 end
 -- Early source stitches have an independent DB70450 / Forever spell reagent
 -- comparison. They may improve *reference quality*, never skill receipt authority.
 if key=="BLACKSMITHING" or key=="LEATHERWORKING" then
  local stitch=JLP:GetModule("ForeverStitchedSourceRoutes226")
  if stitch and type(stitch.AtSkill)=="function" then
   for skill=first,299 do
    local good,r=pcall(stitch.AtSkill,stitch,key,skill)
    local c=good and type(r)=="table" and r.candidates and r.candidates[1]
    if type(c)=="table" and integer(c.recipeID) and
       type(c.recipeSourceURL)=="string" and #(c.reagentsPerCraft or {})>0 then
     -- Prefer a fully published skill-minimum field in the research planner.
     -- Never replace it with an unverified guide skill interval.
     local previous=slots[skill]
     if not previous or previous.sourceLevel~="EXACT_RECIPE_REAGENT_SKILL_REFERENCE" then
      slots[skill]=make(key,skill,"SOURCE_STITCHED_RECIPE_REAGENTS",{
       recipeID=c.recipeID,recipe=c.recipe,recipeSourceURL=c.recipeSourceURL,
       researchWindowSource=c.researchWindowSource,
       reagentEvidence="EXACT_EXTERNAL_AND_DB70450_PARITY",
       learningEvidence="NOT_VERIFIED_FOR_THIS_CHARACTER",
       yieldEvidence=c.outputEvidence and "EXACT_SOURCE_YIELD" or "UNKNOWN",
       skillMinimumEvidence=c.sourceMinimumSkill and "FOREVER_PUBLISHED_REFERENCE" or "UNKNOWN",
       sourceProvenance="FOREVER_SOURCE_STITCH_226"})
     end
    end
   end
  end
 end
 -- P0-229: exact documented minimum + independent item/yield/reagent
 -- parity can identify a research LEAD at precisely its minimum. It cannot
 -- validate an interval, learned state, craft count or actual skill-up.
 local leads=JLP:GetModule("ProfessionFieldChain229")
 if leads and type(leads.MinimumLeads)=="function" then
  for skill=first,299 do
   if not slots[skill] or slots[skill].sourceLevel=="UNQUALIFIED_RESEARCH_WINDOW" then
    local ok,rows=pcall(leads.MinimumLeads,leads,key,skill)
    local firstLead=ok and type(rows)=="table" and rows[1] or nil
    if firstLead then
     slots[skill]=make(key,skill,"EXACT_MINIMUM_LEAD_NOT_VERIFIED_WINDOW",{
      recipeID=firstLead.recipeID,recipe=firstLead.recipe,
      recipeSourceURL=firstLead.recipeSourceURL,
      reagentEvidence=firstLead.proof,learningEvidence="NOT_LIVE_VERIFIED",
      skillMinimumEvidence="EXACT_FOREVER_MINIMUM_AT_THIS_POINT_ONLY",
      yieldEvidence=firstLead.outputPerCraft and "EXACT_SOURCE_FIXED_YIELD" or "UNKNOWN",
      sourceProvenance="FOREVER_PRIMARY_SOURCE_MINIMUM_229"})
    end
   end
  end
 end
end
local function secondaryWindows(key,first,slots)
 local data=JLP.data and JLP.data.foreverSecondaryLeveling
 local source=data and data.professions and data.professions[key]
 for _,s in ipairs(source and source.steps or {}) do
  local a,b=s.skillMin,s.skillMax
  if skillValid(a) and skillValid(b) and a<b and type(s.recipe)=="string" and s.recipe~="" then
   for skill=math.max(a,first),math.min(b-1,299) do
    -- Guide quantities are entire-band shopping estimates, not per-craft.
    -- Never turn them into material requirements or output yield.
    slots[skill]=make(key,skill,"HISTORICAL_GUIDE_RECIPE_BAND",{
      recipe=s.recipe,learningGate=s.accessGate,sourceProvenance=source.guideURL,
      reagentEvidence="AGGREGATED_GUIDE_SHOPPING_LIST_ONLY",
      learningEvidence="NOT_OBSERVED",yieldEvidence="UNKNOWN",
      skillMinimumEvidence="GUIDE_BAND_NOT_RECIPE_MINIMUM"})
   end
  end
 end
 -- The existing 225-300 secondary leads are not complete recipe routes.
 -- Preserve the specific spell references as *leads*, not false coverage.
 local leads=key=="COOKING" and source and source.advancedCookingReferences or
    key=="FIRST_AID" and source and source.advancedFirstAidReferences or nil
 for _,s in ipairs(leads or {}) do
  if integer(s.spellID) and skillValid(s.guideMinimumSkill) then
   for skill=math.max(s.guideMinimumSkill,first),math.min(299,(s.sourceWindowEnd or s.guideMinimumSkill+1)-1) do
    if not slots[skill] then
     slots[skill]=make(key,skill,"SOURCE_RECIPE_LEAD_NO_VERIFIED_WINDOW",{
      recipeID=s.spellID,recipe=s.name,
      sourceProvenance=source.guideURL,learningEvidence=s.learningSource or "UNKNOWN",
      reagentEvidence="NOT_PER_CRAFT_VERIFIED",yieldEvidence="NOT_CLIENT_VERIFIED"})
    end
   end
  end
 end
end
local function gatherWindows(key,first,slots)
 if key=="MINING" then
  local module=JLP:GetModule("ForeverMiningNodeProgression210")
  if module and type(module.AtSkill)=="function" then
   for skill=first,299 do
    local ok,source=pcall(module.AtSkill,module,key,skill)
    if ok and type(source)=="table" and type(source.nodes)=="table" and #source.nodes>0 then
     local n=source.nodes[1]
     slots[skill]=make(key,skill,source.coverage=="FOREVER_GUIDE_RECOMMENDED_BAND" and
       "GUIDE_NODE_SKILL_REFERENCE" or "NODE_REQUIREMENT_ONLY",{
       resource=n.name,sourceProvenance=source.sourceURL,
       nodeMinimumSkill=n.minimumSkill,observedSpawn=false,
       coordinates=nil,learningEvidence="GATHERING_MANUAL_NODE_NOT_LIVE_OBSERVED"})
    end
   end
  end
 elseif key=="FISHING" then
  local data=JLP.data and JLP.data.foreverSecondaryLeveling
  local fish=data and data.fishing
  for _,s in ipairs(fish and fish.tiers or {}) do
   if skillValid(s.skillMin) and skillValid(s.skillMax) and s.skillMin<s.skillMax then
    for skill=math.max(first,s.skillMin),math.min(299,s.skillMax-1) do
     slots[skill]=make(key,skill,"GUIDE_FISHING_AREA_REFERENCE",{
       zone=s.zone,sourceProvenance=fish.guideURL,
       requiredEffectiveFishingSkill=s.minSkill,
       fishingSkillUpObserved=false,coordinates=nil})
    end
   end
  end
 elseif key=="HERBALISM" then
  local refs=JLP.data and JLP.data.gatheringReferencePacked
  for mapID,rows in pairs(refs and refs.maps or {}) do
   for _,r in ipairs(rows) do
    if type(r)=="table" and r[1]=="GATHERSKILLMAP_1_3_0" and r[2]=="HERBALISM" and
       integer(r[4]) and skillValid(r[5]) and type(r[3])=="string" then
     for skill=math.max(r[5],first),299 do
      local old=slots[skill]
      if not old or r[5]>old.nodeMinimumSkill then
       slots[skill]=make(key,skill,"STATIC_GATHER_MAP_REFERENCE",{
        resource=r[3],resourceObjectID=r[4],nodeMinimumSkill=r[5],
        referenceMapID=mapID,sourceProvenance="GATHERSKILLMAP_1_3_0",
        observedSpawn=false,coordinates=nil})
      end
     end
    end
   end
  end
 end
 -- P0-230: a published MOB-LEVEL eligibility formula is not proof of
 -- actual mobs, their spawns/loot or a skinning skill-up. Keep that separation.
 if key=="SKINNING" then
  local skinner=JLP:GetModule("ForeverSkinningEligibility230")
  if skinner and type(skinner.AtSkill)=="function" then
   for skill=first,299 do
    local ok,advisory=pcall(skinner.AtSkill,skinner,skill)
    if ok and advisory and advisory.maximumEligibleMobLevel then
     slots[skill]=make(key,skill,"FOREVER_SKINNING_ELIGIBILITY_NOT_MOB_ROUTE",{
      requiredSkillRule=advisory.eligibilityRule,
      maxEligibleMobLevel=advisory.maximumEligibleMobLevel,
      areaCoverage=advisory.areaCoverage,
      sourceProvenance=advisory.sourceURL,actualMobEvidence=false,
      learningEvidence="REQUIRES_TOOL_AND_ACTUAL_CORPSE",
      yieldEvidence="UNKNOWN",skillMinimumEvidence="MOB_LEVEL_FORMULA_ONLY"})
    end
   end
  end
 end
end
local function compress(out,positions,first,last)
 for skill=first,last-1 do
  local r=positions[skill]
  local state=r and r.sourceLevel or "UNVERIFIED_SOURCE_GAP"
  local recipeID=r and r.recipeID or nil
  local tail=out[#out]
  if tail and tail.toSkill==skill and tail.sourceLevel==state and
    tail.recipeID==recipeID and tail.sourceProvenance==(r and r.sourceProvenance) then
    tail.toSkill=skill+1
  else out[#out+1]={fromSkill=skill,toSkill=skill+1,sourceLevel=state,
    recipeID=recipeID,recipe=r and r.recipe or nil,
    sourceProvenance=r and r.sourceProvenance or nil,
    verifiedSkillUp=false,executionEligible=false} end
 end
end
function M:Audit(key,first,last)
 key=tostring(key or ""):upper();first=first or 1;last=last or 300
 if not class[key] then return nil,"PROFESSION_NOT_REGISTERED" end
 if not skillValid(first) or not skillValid(last) or first>=last then
  return nil,"INVALID_SKILL_INTERVAL" end
 local slots={}
 if class[key]=="CRAFT" then primaryWindows(key,first,slots)
 elseif class[key]=="SECONDARY_CRAFT" then secondaryWindows(key,first,slots)
 else gatherWindows(key,first,slots) end
 local report={contract=self.contract,professionKey=key,professionType=class[key],
  skillFrom=first,skillGoal=last,referencePositions=0,unverifiedPositions=0,
  exactRecipeReagentPositions=0,historicalGuideLeadPositions=0,
  exactMinimumLeadPositions=0,
  sourceTierCounts={},firstUnverifiedSourceSkill=nil,
  contiguousVerifiedSkillUps=0,continuousClientRoute=false,
  craftReceipts=0,skillUpReceipts=0,learnedState="UNKNOWN",
  nativeDispatchAllowed=false,executionEligible=false,readOnly=true,
  result="NOT_CLIENT_VERIFIED",segments={},currentSourcePosition=slots[first],
  missingReleaseRequirements={"ACTUAL_LEARNED_AND_RANK_ACCESS", "REAGENTS_AND_OUTPUT_YIELDS",
     "ACTUAL_SKILLUP_AND_CRAFT_RECEIPTS", "CANONICAL_ACTOR_AND_NAVIGATION", "STATEFUL_REAL_CLIENT_ACCEPTANCE"}}
 for skill=first,last-1 do
  local r=slots[skill]
  if r and r.sourceLevel~="UNQUALIFIED_RESEARCH_WINDOW" then
   report.referencePositions=report.referencePositions+1
   if r.sourceLevel=="EXACT_RECIPE_REAGENT_SKILL_REFERENCE" or
      r.sourceLevel=="EXACT_RECIPE_REAGENT_RESEARCH_WINDOW" or
      r.sourceLevel=="SOURCE_STITCHED_RECIPE_REAGENTS" then
      report.exactRecipeReagentPositions=report.exactRecipeReagentPositions+1
   else
    report.historicalGuideLeadPositions=report.historicalGuideLeadPositions+1
    if r.sourceLevel=="EXACT_MINIMUM_LEAD_NOT_VERIFIED_WINDOW" then
     report.exactMinimumLeadPositions=report.exactMinimumLeadPositions+1
    end
   end
   report.sourceTierCounts[r.sourceLevel]=(report.sourceTierCounts[r.sourceLevel] or 0)+1
  else
   report.unverifiedPositions=report.unverifiedPositions+1
   report.firstUnverifiedSourceSkill=report.firstUnverifiedSourceSkill or skill
  end
 end
 compress(report.segments,slots,first,last)
 if report.referencePositions+report.unverifiedPositions~=last-first then
  return nil,"INTERNAL_POSITION_ACCOUNTING_ERROR" end
 return report
end
function M:AtSkill(key,skill)
 if not skillValid(skill) or skill>=300 then return nil,"SKILL_OUTSIDE_1_299" end
 local report,err=self:Audit(key,skill,skill+1)
 if not report then return nil,err end
 return report.currentSourcePosition or make(tostring(key):upper(),skill,"UNVERIFIED_SOURCE_GAP",{
  nextAction="VERIFY_PROFESSION_SOURCE_AND_RECIPE_LEARNING"})
end
JLP:RegisterModule("ProfessionProgressionCoverage228",M)
