local _, JLP = ...
-- Canonical, read-only join of owner-provided build-70450 recipe reference fields.
-- DB2 never proves learned recipes, real yields, four-color difficulty, or NPC availability.
local Bundle={contract="JLP-RECIPE-FIELD-BUNDLE-70450-1",sourceBuild=70450,
 readOnly=true,productionAuthority=false,executionEligible=false,nativeDispatchAllowed=false}
local BUILD=70450
local function uint(n)
 return type(n)=="number" and n>0 and n<2147483647 and n==math.floor(n)
end
local function currentBuild()
 local info=JLP:GetModule("ClientBuildInfo")
 if not info or type(info.GetBuildNumber)~="function" then return nil end
 local ok,b=pcall(info.GetBuildNumber,info)
 return ok and b or nil
end
local function required(name)
 local m=JLP:GetModule(name)
 if not m then return nil,"MISSING_INTEGRATION_"..name end
 return m,nil
end
function Bundle:GetProof(key,spellID,build)
 if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
 if not uint(spellID) then return nil,"INVALID_SPELL_ID" end
 -- The static 70450 source bundle is available with unknown live build;
 -- UNKNOWN is not a live corroboration or a native authorization.
 local c,err=required("Build70450RecipeCatalogue");if not c then return nil,err end
 local output; output,err=required("Build70450CraftOutput");if not output then return nil,err end
 local difficulty;difficulty,err=required("Build70450SkillDifficulty");if not difficulty then return nil,err end
 local acquisition;acquisition,err=required("Build70450RecipeAcquisition");if not acquisition then return nil,err end
 local row;row,err=c:GetRecipe(key,spellID,BUILD);if not row then return nil,err end
 if row.sourceBuild~=BUILD or row.spellID~=spellID or
    row.nativeDispatchAllowed~=false or row.productionAuthority~=false or row.readOnly~=true then
  return nil,"RECIPE_REFERENCE_AUTHORITY_CONFLICT"
 end
 local y; y,err=output:ForKnownRecipe(row.professionKey,spellID,1,BUILD)
 if not y then return nil,"OUTPUT_SOURCE_"..tostring(err) end
 if y.sourceBuild~=BUILD or y.spellID~=spellID or y.professionKey~=row.professionKey or
    y.productionAuthority~=false then
  return nil,"OUTPUT_REFERENCE_IDENTITY_CONFLICT"
 end
 -- Verify the duplicated CREATE_ITEM view against the typed SpellEffect view.
 -- This is a SOURCE crosscheck, never a verification of produced quantities.
 local raw={}
 for _,r in ipairs(row.outputs or {}) do
  local identity=tostring(r.effectIndex)..":"..tostring(r.itemID)
  if raw[identity] then return nil,"DUPLICATE_RECIPE_OUTPUT_EFFECT" end
  raw[identity]=r.rawEffectBasePointsF
 end
 local found=0
 for _,effect in ipairs(y.effects or {}) do
  if effect.kind=="CREATED_ITEM" then
   local identity=tostring(effect.effectIndex)..":"..tostring(effect.itemID)
   if raw[identity]==nil or raw[identity]~=effect.rawEffectBasePointsF then
    return nil,"CREATE_ITEM_EFFECT_PARITY_CONFLICT"
   end
   found=found+1
  end
 end
 if found~=#(row.outputs or {}) then return nil,"OUTPUT_EFFECT_COUNT_CONFLICT" end
 local d; d,err=difficulty:ForDecodedRecipe(row)
 if not d then return nil,"SKILL_SOURCE_"..tostring(err) end
 if d.spellID~=spellID or d.professionKey~=row.professionKey or
    d.rawMinSkillLineRank~=row.rawMinSkillLineRank or
    d.rawTrivialSkillLineRankLow~=row.rawYellowThreshold or
    d.rawTrivialSkillLineRankHigh~=row.rawGreyThreshold or
    d.nativeDispatchAllowed~=false then return nil,"SKILL_IDENTITY_CONFLICT" end
 local a;a,err=acquisition:GetRecipeSources(row.professionKey,spellID,BUILD)
 if not a then return nil,"ACQUISITION_SOURCE_"..tostring(err) end
 if a.professionKey~=row.professionKey or a.spellID~=spellID or
    (a.clientBuildRelation~="MATCH" and a.clientBuildRelation~="HISTORICAL_REFERENCE" and a.clientBuildRelation~="MISMATCH" and a.clientBuildRelation~="UNKNOWN") or a.productionAuthority~=false or
    a.nativeDispatchAllowed~=false then return nil,"ACQUISITION_IDENTITY_CONFLICT" end
 local materials=nil
 local state="NOT_A_CRAFTING_RECIPE"
 if row.recordKind=="RECIPE_CANDIDATE" then
  state=row.reagentState
  if row.reagents then
   materials,err=c:GetMaterialNeeds(row.professionKey,spellID,1,BUILD)
   if not materials then return nil,"REAGENT_SOURCE_"..tostring(err) end
   if materials.sourceBuild~=BUILD or materials.spellID~=spellID or
      materials.professionKey~=row.professionKey or materials.nativeDispatchAllowed~=false then
    return nil,"REAGENT_IDENTITY_CONFLICT" end
   local expected={}
   for _,r in ipairs(row.reagents) do
    expected[r.itemID]=(expected[r.itemID] or 0)+r.quantity
   end
   local seen={}
   for _,r in ipairs(materials.requirements or {}) do
    if seen[r.itemID] or expected[r.itemID]~=r.rawTotal then
     return nil,"REAGENT_QUANTITY_PARITY_CONFLICT"
    end
    seen[r.itemID]=true
   end
   for id in pairs(expected) do if not seen[id] then return nil,"MISSING_REAGENT_IN_BUNDLE" end end
  end
 end
 local sourceFlags={}
 if row.name==nil then sourceFlags[#sourceFlags+1]="SPELL_NAME_NOT_IN_EXPORT" end
 if state=="NO_REAGENT_RECORD" then sourceFlags[#sourceFlags+1]="REAGENT_ROW_NOT_IN_EXPORT" end
 if state=="EMPTY_REAGENT_SLOTS" then sourceFlags[#sourceFlags+1]="EMPTY_REAGENT_SLOTS_NOT_NO_MATERIAL_PROOF" end
 if d.numericBoundaryCount~=2 then sourceFlags[#sourceFlags+1]="YELLOW_GREY_SOURCE_UNQUALIFIED" end
 if #y.effects==0 then sourceFlags[#sourceFlags+1]="NO_TYPED_OUTPUT_EFFECT_IN_EXPORT" end
 if y.sourceReferenceConflict then sourceFlags[#sourceFlags+1]="OUTPUT_REFERENCE_CONFLICT" end
 if a.hasConflictingSource then sourceFlags[#sourceFlags+1]="ACQUISITION_RESEARCH_CONFLICT" end
 return {contract=self.contract,sourceBuild=BUILD,clientBuildRelation=currentBuild()==BUILD and "MATCH" or
    (currentBuild() and "HISTORICAL_REFERENCE" or "UNKNOWN"),
  professionKey=row.professionKey,spellID=spellID,name=row.name,
  classification=row.recordKind,classificationEvidence=row.classificationEvidence,
  reagents=materials and materials.requirements or nil,reagentState=state,
  outputOutcome=y.outcome,outputEffects=y.effects,outputQuantityLiveVerified=false,
  yellow=d.yellow,grey=d.grey,orange=nil,green=nil,skillSourceStatus=d.yellowGreyState,
  rawMinSkillLineRank=d.rawMinSkillLineRank,learnSkillRank=nil,
  teachingItems=a.teachingItems,teachingItemCount=a.teachingItemCount,
  acquisitionResearchSources=a.researchSources,acquisitionState=a.sourceState,
  acquisitionServerVerified=false,serverRecipeAvailable="UNKNOWN",
  requiredFaction="UNKNOWN",requiredSpecialization="UNKNOWN",requiredPhase="UNKNOWN",
  sourceFlags=sourceFlags,sourceFieldParity="RECIPE_REAGENT_TYPED_EFFECT_SKILL_SOURCE_CONSISTENT",
  teachingItemRelationEvidence="PACKED_ADDON_ITEMEFFECT_REFERENCE_NOT_RECHECKED_FROM_TASK06_CSV",
  state=#sourceFlags==0 and "CLIENT_FIELDS_CONSISTENT" or "CLIENT_FIELDS_PARTIAL",
  allFieldsLiveVerified=false,sourceQualified=false,
  readOnly=true,productionAuthority=false,nativeDispatchAllowed=false,
  executionEligible=false},nil
end
function Bundle:GetCoverage()
 local c,err=required("Build70450RecipeCatalogue");if not c then return nil,err end
 local e;e,err=c:GetCoverage();if not e then return nil,err end
 return {contract=self.contract,sourceBuild=BUILD,professionCount=e.professionCount,
  uniqueIdentities=e.uniqueProfessionSpellRecords,recipeCandidates=e.recipeCandidates,
  abilityOnly=e.abilityOnly,clientSourceQA=e.qualityAssurance,
  liveServerSourcesVerified=false,allFieldsLiveVerified=false,
  readOnly=true,productionAuthority=false,nativeDispatchAllowed=false},nil
end
JLP:RegisterModule("RecipeEvidenceBundle70450",Bundle)
