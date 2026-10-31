local _,JLP=...
-- P0/188: one non-mutating end-to-end readiness/progression handoff for all 12
-- professions. No historical observations, data provenance or planning odds may
-- authorize native crafting or auto-confirm completion. Every ambiguous field
-- remains UNKNOWN. A separate ledger/client event is needed to confirm output.
local M={contract="JLP-CURRENT-STEP-CHAIN-188",readOnly=true,
    nativeDispatchAllowed=false,executionEligible=false}
local function count(n)
 n=tonumber(n)
 if n and n==n and n>=0 and n<math.huge and n==math.floor(n) then return n end
end
local function getNavigation(step,plan)
 return type(step.navigation)=="table" and step.navigation or
     (type(plan)=="table" and plan.currentStepNavigation) or nil
end
local function materials(step)
 local rows={} -- immutable projected output, never edit input
 local unknown,needed=0,0
 local source=type(step.materials)=="table" and step.materials or {}
 for _,m in ipairs(source) do
  if type(m)=="table" and count(m.itemID) and count(m.itemID)>0 then
   local q=count(m.required or m.perCraft or m.quantity)
   local missing=m.bagsKnown==true and count(m.missing) or nil
   local immediate=count(m.immediateRequired or m.perCraft or m.quantity)
   local nextMissing=m.bagsKnown==true and count(m.bags) and immediate and
       math.max(0,immediate-m.bags) or missing
   if missing==nil or q==nil then unknown=unknown+1 else needed=needed+(nextMissing or missing) end
   rows[#rows+1]={itemID=m.itemID,name=m.name,required=q,
    missing=missing,immediateRequired=immediate,immediateMissing=nextMissing,bagsKnown=m.bagsKnown==true,
    source=m.source,estimatedPrice=m.price,readOnly=true}
  end
 end
 return rows,unknown,needed
end
function M:Build(key,step,plan)
 if type(step)~="table" then return {contract=self.contract,profession=key,
  state="UNKNOWN",reason="CURRENT_STEP_UNAVAILABLE",readOnly=true,
  nativeDispatchAllowed=false,executionEligible=false} end
 local nav=getNavigation(step,plan)
 local rows,unknown,needed=materials(step)
 local kind=step.kind
 local knownLearned=type(step.learned)=="boolean"
 local stage="VERIFY"
 if kind=="complete" then stage="COMPLETE"
 elseif kind=="train" then stage="TRAIN"
 elseif kind=="learn" then stage=step.recipeID~=nil and "LEARN_RECIPE" or "LEARN_PROFESSION"
 elseif kind=="gather" then stage="GATHER"
 elseif kind=="craft" then
  if step.learned==false then stage="LEARN_RECIPE"
  elseif not knownLearned then stage="VERIFY_RECIPE"
  elseif #rows==0 then stage="VERIFY_MATERIALS"
  elseif unknown>0 then stage="VERIFY_INVENTORY"
  elseif needed>0 then stage="ACQUIRE_MATERIALS"
  else stage="MANUAL_CRAFT_ONE" end
 end
 -- A live learned=false observation is an actual LEARN gate, not the same
 -- state as a learned but GRAY recipe. Preserve the decisive next action.
 if step.manualCraftBlockedByLiveDifficulty==true then stage="VERIFY_RECIPE"
 elseif step.manualCraftBlockedByLiveLearning==true then
  stage=step.learned==false and "LEARN_RECIPE" or "VERIFY_RECIPE"
 end
 if step.patternAcquisition and step.learned~=true then
  stage=step.requiredNextAction=="acquire-recipe" and "ACQUIRE_RECIPE" or
      step.requiredNextAction=="learn-recipe" and "LEARN_RECIPE" or "VERIFY_RECIPE_ACQUISITION"
 end
 if step.actionType=="ENCHANT_APPLICATION" and stage=="MANUAL_CRAFT_ONE" then
  stage=step.enchantTarget and step.enchantTarget.ready and "MANUAL_ENCHANT_ONE" or "VERIFY_ENCHANT_TARGET"
 end
 if step.manualCraftBlockedByRecipePrerequisite then stage=key=="ENGINEERING" and "VERIFY_ENGINEERING_PREREQUISITES" or key=="BLACKSMITHING" and "VERIFY_BLACKSMITHING_PREREQUISITES" or key=="ALCHEMY" and "VERIFY_ALCHEMY_PREREQUISITES" or "VERIFY_ENCHANTING_PREREQUISITES" end
 if step.learningMethod=="automatic" and step.learned~=true then stage="VERIFY_AUTOMATIC_RECIPE" end
 if step.trainerAcquisition and step.learned~=true then
  stage=step.requiredNextAction=="learn-trainer" and "LEARN_RECIPE" or "VERIFY_TRAINER_OFFER"
 end
 if step.ordinaryRodAcquisition then
  local rod=step.ordinaryRodAcquisition
  stage=rod.status=="UNKNOWN_INVENTORY" and "VERIFY_ORDINARY_ROD_INVENTORY" or
      rod.status=="BANK_OBSERVED" and "RETRIEVE_ORDINARY_ROD" or "ACQUIRE_ORDINARY_ROD"
 end
 local nextProgress=(kind=="complete") and "PROFESSION_COMPLETE" or
    (kind=="craft" and "RECHECK_SKILL_RECIPE_INVENTORY_AND_RECEIPTS" or
     (kind=="gather" and "RECHECK_SKILL_AND_NODE_ELIGIBILITY" or
      "RECHECK_PROFESSION_AND_REPLAN"))
 if step.annoraAccess and step.annoraAccess.stage=="RECHECK_TRAINER_OFFER" then stage="VERIFY_TRAINER_OFFER" end
 local access=step.patternAcquisition and step.patternAcquisition.vendorAccess
 if access and step.learned==false and step.patternAcquisition.patternPossession~="UNKNOWN"and (step.patternAcquisition.status=="RETRIEVE_ACCESS_ITEM_FROM_BANK"or step.patternAcquisition.status=="EQUIP_ACCESS_ITEM_MANUALLY"or step.patternAcquisition.status=="VENDOR_ACCESS_QUEST_MANUALLY"or step.patternAcquisition.status=="VERIFY_DUNGEON_QUEST_OBJECTIVES"or step.patternAcquisition.status=="VERIFY_VENDOR_ACCESS_PREREQUISITE")then
  stage=access.status=="BANK"and "RETRIEVE_VENDOR_ACCESS_ITEM"or access.status=="EQUIP_MANUALLY"and "VERIFY_VENDOR_EQUIPMENT"or
   (access.status=="QUEST_START"or access.status=="QUEST_RETURN")and "MANUAL_VENDOR_ACCESS_QUEST"or access.status=="QUEST_OBJECTIVES"and "VERIFY_DUNGEON_OBJECTIVES"or "VERIFY_VENDOR_ACCESS"
 end
 -- Stage is an advisory action, never a claim that craftability is authorized.
 return {contract=self.contract,profession=key,stage=stage,kind=kind,
  actionType=step.actionType,enchantTarget=step.enchantTarget,toolRequirement=step.toolRequirement,
  annoraAccess=step.annoraAccess,
  ordinaryRodAcquisition=step.ordinaryRodAcquisition,learningMethod=step.learningMethod,materialService=step.materialService,
  recipeID=step.recipeID,patternAcquisition=step.patternAcquisition,skill=count(step.skill),
  skillGoal=count(step.skillTarget),navigation=nav,
  travelEngine=nav and nav.travelEngine or "IntegratedTravelEngine",
  arrow=nav and nav.arrow or "IntegratedJuztTom",
  navigationStatus=nav and nav.status or "LOCATION_UNVERIFIED",
  waypointQualified=nav and nav.waypointQualified==true or false,
  navigationManual=true,materials=rows,unknownMaterialTypes=unknown,
  verifiedShortage=(#rows>0 and unknown==0) and needed or nil,
  skillUpProbability=step.skillUpPlanning and step.skillUpPlanning.probability or nil,
  probabilityEvidence=step.skillUpPlanning and step.skillUpPlanning.source or "UNKNOWN",
  nextProgressionCheck=nextProgress,
  accountMaterialReservations=type(step.accountMaterialReservations)=="table" and
      step.accountMaterialReservations or nil,
  crossProfessionDependencies=type(step.crossProfessionDependencies)=="table" and
      step.crossProfessionDependencies or nil,
  rankSourceContinuity=type(step.rankSourceContinuity)=="table" and
      step.rankSourceContinuity or nil,
  recipeSourcePlanning=type(step.recipeSourcePlanning)=="table" and
      step.recipeSourcePlanning or nil,
  recipeSourceState=type(step.recipeSourcePlanning)=="table" and
      step.recipeSourcePlanning.state or "UNKNOWN",
  sourceFieldEvidence=type(step.recipeSourcePlanning)=="table" and
      step.recipeSourcePlanning.fieldEvidence or nil,
  unresolvedSourceFields=type(step.recipeSourcePlanning)=="table" and
      step.recipeSourcePlanning.unresolvedSourceFields or nil,
  materialObservationState=#rows==0 and "NO_MATERIAL_LINES" or
      (unknown>0 and "INVENTORY_UNKNOWN" or "BAGS_OBSERVED"),
  completionProof="ACTUAL_CLIENT_EVENT_REQUIRED",
  clientEvidenceRequiredForPlanning=false,
  readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
  userClickRequired=true}
end
function M:Attach(key,step,plan)
 local result=self:Build(key,step,plan)
 if type(step)=="table" then step.completionChain=result end
 if type(plan)=="table" then plan.currentStepCompletionChain=result end
 return result
end
JLP:RegisterModule("CurrentStepCompletionChain",M)
