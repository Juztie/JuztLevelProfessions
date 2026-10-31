local _, JLP = ...
-- P0-212: explicit FOREVER recipe identity, output and direct reagent references.
-- Source pages are external evidence, not current-character learning, skill-ups,
-- real inventory, vendor stock, coordinates or native crafting authorization.
local rows={
 [2331]={professionKey="ALCHEMY",recipeID=2331,recipeName="Minor Mana Potion",outputItemID=2455,outputQuantity=2,materials={{itemID=785,quantity=1},{itemID=2447,quantity=1},{itemID=3371,quantity=1}},source="https://www.wowhead.com/forever/spell=2331/minor-mana-potion",status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [2334]={professionKey="ALCHEMY",recipeID=2334,recipeName="Elixir of Minor Fortitude",outputItemID=2458,outputQuantity=2,materials={{itemID=2449,quantity=2},{itemID=2447,quantity=1},{itemID=3371,quantity=1}},source="https://www.wowhead.com/forever/spell=2334/elixir-of-minor-fortitude",status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [3170]={professionKey="ALCHEMY",recipeID=3170,recipeName="Minor Troll's Blood Elixir",outputItemID=3382,outputQuantity=2,materials={{itemID=2447,quantity=1},{itemID=2449,quantity=2},{itemID=3371,quantity=1}},source="https://www.wowhead.com/forever/spell=3170/minor-trolls-blood-elixir",status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [3328]={professionKey="BLACKSMITHING",recipeID=3328,recipeName="Rough Bronze Shoulders",outputItemID=3480,outputQuantity=2,materials={{itemID=2841,quantity=5},{itemID=1210,quantity=1},{itemID=3478,quantity=1}},source="https://www.wowhead.com/forever/spell=3328/rough-bronze-shoulders",status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [3953]={professionKey="ENGINEERING",recipeID=3953,recipeName="Bronze Framework",outputItemID=4382,outputQuantity=2,materials={{itemID=2841,quantity=2},{itemID=2319,quantity=1},{itemID=2592,quantity=1}},source="https://www.wowhead.com/forever/spell=3953/bronze-framework",sourceSkillMinimum=145,teachingKind="TRAINER_NAME_REFERENCE",trainerNames={"Franklin Lloyd","Nogg","Roxxik","Buzzek Bracketswing"},trainerIDsVerified=false,trainerStockVerified=false,coordinateQualified=false,status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [2152]={professionKey="LEATHERWORKING",recipeID=2152,recipeName="Light Armor Kit",outputItemID=2304,outputQuantity=2,materials={{itemID=2318,quantity=1}},source="https://www.wowhead.com/forever/spell=2152/light-armor-kit",status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
}
-- Explicit adversarial case: same spellID has a different name in the historical DB.
-- No source-name match, no elevation to qualified producer, despite aligned item/reagents.
local conflicts={
 [2329]={professionKey="ALCHEMY",recipeID=2329,dbName="Elixir of Minor Strength",
 foreverName="Elixir of Lion's Strength",source="https://www.wowhead.com/forever/spell=2329/elixir-of-lions-strength",
 status="SOURCE_NAME_CONFLICT",readOnly=true,nativeDispatchAllowed=false}
}
JLP.data.foreverPrimaryRecipeParity212={contract="JLP-FOREVER-PRIMARY-RECIPE-PARITY-212",readOnly=true,
 nativeDispatchAllowed=false,executionEligible=false,sourceBuild=70450,rows=rows,conflicts=conflicts}
