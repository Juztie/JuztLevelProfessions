local _, JLP = ...
-- P0-219: Exact Forever spell-page learning floors. These are READ-ONLY
-- external references with DB70450 and public-route identity/reagent checks.
-- The DB70450 difficulty interval is NOT the learning minimum. Item output
-- counts are source references only and cannot authorize native actions.
JLP.data.foreverExactBSLWSourceSkills219={
 contract="JLP-EXACT-BSLW-FOREVER-SPELL-SKILLS-219",readOnly=true,
 nativeDispatchAllowed=false,coordinateQualified=false,
 rows={
  BLACKSMITHING={
   [16657]={recipeID=16657,name="Imperial Plate Boots",requiredSkill=295,outputItemID=12426,
    sourceYield=2,source="https://www.wowhead.com/forever/spell=16657/imperial-plate-boots",
    evidence="FOREVER_SPELL_QUICK_FACTS_AND_DIRECT_REAGENTS",acquisition="UNKNOWN",waypointQualified=false},
  },
  LEATHERWORKING={
   [10487]={recipeID=10487,name="Thick Armor Kit",requiredSkill=200,outputItemID=8173,
    sourceYield=2,source="https://www.wowhead.com/forever/spell=10487/thick-armor-kit",
    evidence="FOREVER_SPELL_QUICK_FACTS_AND_DIRECT_REAGENTS",acquisition="TRAINER_NAME_REFERENCES_ONLY",waypointQualified=false,
    trainerActor={npcID=3007,name="Una",faction="Horde",source="https://www.wowhead.com/forever/npc=3007/una",
      referenceKind="NPC_IDENTITY_AND_SPELL_PAGE_TEACHER_NAME",stockVerified=false,coordinateQualified=false}},
   [19058]={recipeID=19058,name="Rugged Armor Kit",requiredSkill=250,outputItemID=15564,
    sourceYield=2,source="https://www.wowhead.com/forever/spell=19058/rugged-armor-kit",
    evidence="FOREVER_SPELL_QUICK_FACTS_AND_DIRECT_REAGENTS",acquisition="TRAINER_NAME_REFERENCE_ONLY",waypointQualified=false,
    trainerActor={npcID=11098,name="Hahrana Ironhide",faction="Horde",source="https://www.wowhead.com/forever/npc=11098/hahrana-ironhide",
      referenceKind="NPC_IDENTITY_WITH_HISTORICAL_SPELL_COMMENT",stockVerified=false,coordinateQualified=false}},
   [19071]={recipeID=19071,name="Wicked Leather Headband",requiredSkill=280,outputItemID=15086,
    sourceYield=2,source="https://www.wowhead.com/forever/spell=19071/wicked-leather-headband",
    evidence="FOREVER_SPELL_QUICK_FACTS_AND_DIRECT_REAGENTS",acquisition="UNKNOWN",waypointQualified=false},
  },
 },
}
