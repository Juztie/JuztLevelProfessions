local _,JLP=...
-- P0-230: publicly documented Forever skinning eligibility, not spawn,
-- skinnability, loot, route, difficulty, or a skill-up receipt.
local M={contract="JLP-FOREVER-SKINNING-ELIGIBILITY-230",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false,
 sourceURL="https://www.wowhead.com/forever/guide/professions/skinning/overview-leveling",
 sourceUpdated="2026-10-24"}
local zones={
 {from=1,to=75,names={"Any starter zone"}},
 {from=75,to=125,names={"The Barrens"},faction="Horde"},
 {from=125,to=175,names={"Ashenvale","Hillsbrad Foothills"}},
 {from=175,to=225,names={"Arathi Highlands","Stranglethorn Vale","Thousand Needles"}},
}
-- These are published trainer NAME+area leads, not owner-certified locations.
local trainers={
 {name="Kagil",area="Valley of Trials, Durotar",faction="Horde",rank="Apprentice"},
 {name="Nawka Wildsong",area="Red Cloud Mesa, Mulgore",faction="Horde",rank="Apprentice"},
 {name="Margaret Weaver",area="Death Knell, Tirisfal Glades",faction="Horde",rank="Apprentice"},
 {name="Thuwd",area="Orgrimmar",faction="Horde",rank="All"},
 {name="Dranh",area="Camp Taurajo, The Barrens",faction="Horde",rank="All"},
 {name="Killian Hagey",area="Undercity",faction="Horde",rank="All"},
 {name="Mooranta",area="Thunder Bluff",faction="Horde",rank="All"},
 {name="Mendalass Tattermend",area="Zephras Isle",faction="Neutral",rank="All"},
 {name="Ishlee Breezewhisper",area="Zephras Isle",faction="Neutral",rank="All"},
}
local function whole(n) return type(n)=="number" and n==n and n==math.floor(n)
  and n>=0 and n<2147483647 end
function M:RequiredSkill(mobLevel)
 if not whole(mobLevel) or mobLevel<1 or mobLevel>100 then return nil,"MOB_LEVEL_UNKNOWN" end
 if mobLevel<=10 then return 1 end
 if mobLevel<=20 then return (mobLevel-10)*10 end
 return mobLevel*5
end
function M:AtSkill(skill,options)
 options=type(options)=="table" and options or {}
 if not whole(skill) or skill<1 or skill>300 then return nil,"INVALID_SKILL" end
 local boost=options.observedSkillBonus
 -- Buffs are only used when caller explicitly supplies an observed amount.
 if boost~=nil and (not whole(boost) or boost>100) then return nil,"BONUS_NOT_VERIFIED" end
 local effective=skill+(boost or 0)
 local mobMax=10
 for level=11,100 do
  local min=self:RequiredSkill(level)
  if min and min<=effective then mobMax=level end
 end
 local chosen={}
 for _,band in ipairs(zones) do
  if skill>=band.from and skill<band.to and
    (not band.faction or options.faction==nil or options.faction==band.faction) then
   for _,name in ipairs(band.names) do chosen[#chosen+1]=name end
  end
 end
 local intel=JLP:GetModule("SkinningMaterialIntelligence")
 local bridge=JLP:GetModule("GatheringMaterialBridge")
 local static=intel and intel:GetProgressionSource(effective,bridge and bridge.unavailable)
 if #chosen==0 and static then chosen[1]=static.zone end
 local candidates={}
 for _,t in ipairs(trainers) do
  if (options.faction==nil and t.faction=="Neutral") or
     (options.faction=="Horde" and (t.faction=="Horde" or t.faction=="Neutral")) or
     (options.faction=="Alliance" and t.faction=="Neutral") then
   candidates[#candidates+1]={name=t.name,area=t.area,faction=t.faction,
    rank=t.rank,coordinateAuthority=false,ownerVerified=false}
  end
 end
 return {contract=self.contract,profession="SKINNING",skill=skill,
  effectiveSkill=effective,observedBonus=boost,maximumEligibleMobLevel=mobMax,
  eligibilityRule="FOREVER_PUBLISHED_LEVEL_TO_SKILL_THRESHOLD",
  sourceURL=self.sourceURL,sourceUpdated=self.sourceUpdated,
  suggestedAreas=chosen,staticSource=static,areaCoverage=skill<225 and "GUIDE_SUGGESTED_ONLY" or static and "STATIC_FOREVER_SOURCE_CURRENT_DIFFICULTY_UNKNOWN" or "UNKNOWN_225_TO_300",
  trainerNameReferences=candidates,
  requiredTool="Skinning Knife",toolOwned="UNKNOWN",toolEquippedRequired=false,toolPolicy="HISTORICAL_FACT_PLAYER_MANAGED_NOT_PLANNING_REQUIREMENT",
  corpseLooted="UNKNOWN",mobSkinnable="UNKNOWN",mobObserved=false,
  skinningSkillUpObserved=false,lootQualified=false,
  navigationStatus="LOCATION_UNVERIFIED",waypointQualified=false,
  readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  nextAction="Verify skinnable, fully looted corpse and current skill; skin manually; recheck actual skill."}
end
-- Rank eligibility is specific to Skinning, not copied crafting level gates.
-- Forever trainer reference lists no character-level requirement; current cap
-- remains the authoritative receipt. A journey to a trainer is never learning.
function M:GetPlan(profession)
 local p={key="SKINNING",profession=profession,readOnly=true,executionEligible=false,
  nativeDispatchAllowed=false,materials={},status="verify",actionKind="verify",
  rankSourceURL="https://www.wow-professions.com/forever/skinning-trainers"}
 local skill=profession and profession.cached~=true and tonumber(profession.skill)
 local cap=profession and profession.cached~=true and tonumber(profession.maxSkill)
 local shared=JLP:GetModule("GatheringSharedMapState")
 local snapshot=shared and shared:GetSnapshot()
 local manual=snapshot and snapshot.manualSupplyGoal
 manual=manual and manual.professionKey=="SKINNING"and manual or nil
 local step={kind="verify",profession="SKINNING",readOnly=true,nativeDispatchAllowed=false,
  executionEligible=false,skill=skill,rankObserved=false}
 local automatic=snapshot and snapshot.supplyGoal
 if automatic and automatic.origin=="AUTOMATIC_PLAN" and automatic.professionKey=="SKINNING" then
  local bridge=JLP:GetModule("GatheringMaterialBridge")
  local supplied=automatic.status~="VERIFY_OWNER" and bridge and bridge:SelectSkinningSupply(automatic.itemID,automatic.required,automatic.strategy)
  step.materialSupply=supplied
  local kinds={SKINNING="gather",BANK="bank",AUCTION="acquire"}
  step.kind=supplied and kinds[supplied.status] or "verify"
  step.nextAction=automatic.nextAction or (supplied and supplied.status=="BAGS_READY" and "Required material is observed in bags; resume Leatherworking." or "Verify the current Leatherworking material supply.")
  p.actionKind=step.kind;p.status=step.kind;p.action=step.nextAction;p.recommendedCurrentStep=step
  local travel=JLP:GetModule("CurrentStepTravelBridge")
  if travel and travel.AttachPlan then travel:AttachPlan("SKINNING",p) end
  return p
 end
 if not whole(skill) or skill<1 then step.nextAction="Observe Skinning ownership, skill and cap in the client."
 elseif skill>=300 and not manual then step.kind="complete";p.status="complete";p.actionKind="complete"
  step.nextAction="Skinning skill goal reached; Leatherworking material gathering may continue separately."
 elseif not cap or (cap~=75 and cap~=150 and cap~=225 and cap~=300) then
  step.nextAction="Observe the actual Skinning rank/cap before planning progression."
 else
  p.eligibility=self:AtSkill(skill,{faction=type(UnitFactionGroup)=="function" and UnitFactionGroup("player") or nil})
  local nextRank=cap==75 and "Journeyman" or cap==150 and "Expert" or cap==225 and "Artisan" or nil
  step.rankAvailable=nextRank and skill>=(cap==75 and 50 or cap==150 and 125 or 200) or false
  step.futureRank=nextRank
  step.rankObserved=true
  if skill>=cap and nextRank then
   step.kind="train";step.rank=nextRank;p.actionKind="train";p.status="RANK_CAP_REACHED"
   step.nextAction="Learn "..nextRank.." Skinning manually; wait for an observed cap change."
  else
   local inventory=JLP:GetModule("Inventory")
   step.toolPolicy="PLAYER_MANAGED_ORDINARY_TOOL"
   step.kind="gather";p.actionKind="gather";p.status="CONDITIONAL_MANUAL_GATHERING"
   step.nextAction="Find a fully looted skinnable corpse within the documented level limit; skin manually and observe actual skill and loot separately."
   local bridge=JLP:GetModule("GatheringMaterialBridge")
   local chosen=p.eligibility and p.eligibility.staticSource
   if manual then
    local eligible=bridge and bridge:GetEligibleSkinningSources(manual.itemID) or {}
    chosen=nil
    for _,r in ipairs(eligible) do
     if r.id==manual.sourceID then chosen=r;break end
    end
    chosen=chosen or eligible[1]
    step.manualMaterialGoal=true
   end
   if chosen and bridge then
    local itemID=manual and manual.itemID or chosen.itemIDs and chosen.itemIDs[1]
    step.skinningSource=bridge:GetSkinningWaypoint(itemID,chosen.id)
    step.nextAction="Visit "..chosen.name.." in "..(chosen.zone or "the referenced area")..
     "; verify a fully looted skinnable corpse, actual level and difficulty; skin manually. "..
     "Public location is not a live spawn; observe loot and skill separately."
   end
   step.skillUpProbability="UNKNOWN";step.mobCount="UNKNOWN"
  end
 end
 p.recommendedCurrentStep=step;p.action=step.nextAction
 local travel=JLP:GetModule("CurrentStepTravelBridge")
 if travel and travel.AttachPlan then travel:AttachPlan("SKINNING",p) end
 return p
end
JLP:RegisterModule("ForeverSkinningEligibility230",M)
