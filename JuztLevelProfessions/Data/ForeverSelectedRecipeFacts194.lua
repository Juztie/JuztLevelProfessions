local _, JLP = ...
-- Exact selected SpellID references for non-Tailoring crafts. Sources remain advisory.
-- Cooking Charred Wolf Meat is STARTER with a normal Cooking Fire requirement;
-- no 45-skill crafting floor inferred from the orange-to-yellow transition.
JLP.data.foreverSelectedRecipeFacts194 = {
 contract="JLP-FOREVER-SELECTED-RECIPE-FACTS-194",readOnly=true,rows={
  ENCHANTING={
   [7421]={requiredSkill=1,name="Runed Copper Rod",source="https://www.wowhead.com/forever/spell=7421/runed-copper-rod",referenceKind="FOREVER_SPELL_AND_CLASSIC_MINIMUM_CORROBORATION",navigationQualified=false},
  },
  ALCHEMY={
   [1245246]={requiredSkill=1,name="Minor Arcane Elixir",source="https://www.wowhead.com/forever/guide/professions/alchemy-overview-trainer-locations-recipes",referenceKind="FOREVER_GUIDE_EXPLICIT_MINIMUM",navigationQualified=false},
   [1251741]={requiredSkill=30,name="Minor Mender's Potion",source="https://www.wowhead.com/forever/guide/professions/alchemy-overview-trainer-locations-recipes",referenceKind="FOREVER_GUIDE_EXPLICIT_MINIMUM",navigationQualified=false},
   [1251729]={requiredSkill=35,name="Minor Spellblasting Potion",source="https://www.wowhead.com/forever/guide/professions/alchemy-overview-trainer-locations-recipes",referenceKind="FOREVER_GUIDE_EXPLICIT_MINIMUM",navigationQualified=false},
   [1251735]={requiredSkill=40,name="Minor Frenzy Potion",source="https://www.wowhead.com/forever/guide/professions/alchemy-overview-trainer-locations-recipes",referenceKind="FOREVER_GUIDE_EXPLICIT_MINIMUM",navigationQualified=false},
  },
  BLACKSMITHING={
   [2660]={requiredSkill=1,name="Rough Sharpening Stone",source="https://www.wowhead.com/forever/spell=2660/rough-sharpening-stone",referenceKind="FOREVER_SPELL_AND_CLASSIC_MINIMUM_CORROBORATION",navigationQualified=false},
   [3337]={requiredSkill=125,name="Heavy Grinding Stone",source="https://www.wowhead.com/forever/spell=3337/heavy-grinding-stone",referenceKind="FOREVER_SPELL_EXPLICIT_MINIMUM_202",navigationQualified=false},
   [7408]={requiredSkill=65,name="Heavy Copper Maul",source="https://www.wowhead.com/forever/spell=7408/heavy-copper-maul",referenceKind="FOREVER_SPELL_EXPLICIT_MINIMUM_222",navigationQualified=false},
  },
  ENGINEERING={
   [3918]={requiredSkill=1,name="Rough Blasting Powder",source="https://www.wowhead.com/forever/spell=3918/rough-blasting-powder",referenceKind="FOREVER_SPELL_QUICK_FACTS",navigationQualified=false},
   [3922]={requiredSkill=30,name="Handful of Copper Bolts",source="https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes",referenceKind="FOREVER_GUIDE_EXPLICIT_MINIMUM",navigationQualified=false},
   [3924]={requiredSkill=50,name="Copper Tube",source="https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes",referenceKind="FOREVER_GUIDE_EXPLICIT_MINIMUM",navigationQualified=false},
   [3929]={requiredSkill=75,name="Coarse Blasting Powder",source="https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes",referenceKind="FOREVER_GUIDE_EXPLICIT_MINIMUM",navigationQualified=false},
   [3938]={requiredSkill=105,name="Bronze Tube",source="https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes",referenceKind="FOREVER_GUIDE_EXPLICIT_MINIMUM",navigationQualified=false},
   [3945]={requiredSkill=125,name="Heavy Blasting Powder",source="https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes",referenceKind="FOREVER_GUIDE_EXPLICIT_MINIMUM",navigationQualified=false},
  },
  LEATHERWORKING={
   [2152]={requiredSkill=1,name="Light Armor Kit",source="https://www.wowhead.com/forever/spell=2152/light-armor-kit",referenceKind="FOREVER_SPELL_QUICK_FACTS",navigationQualified=false},
  },
  FIRST_AID={
   [3275]={requiredSkill=1,name="Linen Bandage",source="https://www.wowhead.com/forever/spell=3275/linen-bandage",referenceKind="FOREVER_SPELL_QUICK_FACTS",navigationQualified=false},
  },
 }, acquisition={
  ALCHEMY={
   [1245246]={kind="trainer",source="https://www.wowhead.com/forever/guide/professions/alchemy-overview-trainer-locations-recipes",identityStrength="WOWHEAD_GUIDE_SPELL_MODE_ONLY",teachingItemVerified=false,coordinateQualified=false},
   [1251741]={kind="drop",actor="Gnarlpine Mystic / Tirisfal Farmer",source="https://www.wowhead.com/forever/guide/professions/alchemy-overview-trainer-locations-recipes",identityStrength="WOWHEAD_GUIDE_SPELL_MODE_ONLY",teachingItemVerified=false,coordinateQualified=false},
   [1251729]={kind="drop",actor="Kobold Geomancer / Dustwind Harpy",source="https://www.wowhead.com/forever/guide/professions/alchemy-overview-trainer-locations-recipes",identityStrength="WOWHEAD_GUIDE_SPELL_MODE_ONLY",teachingItemVerified=false,coordinateQualified=false},
   [1251735]={kind="drop",actor="Hatescreech / Windfury Wind Witch / Bloodfeather Harpy",source="https://www.wowhead.com/forever/guide/professions/alchemy-overview-trainer-locations-recipes",identityStrength="WOWHEAD_GUIDE_SPELL_MODE_ONLY",teachingItemVerified=false,coordinateQualified=false},
  },
  FIRST_AID={
   [3275]={kind="trainer",source="https://www.wowhead.com/forever/guide/professions/first-aid/overview",identityStrength="WOWHEAD_GUIDE_SPELL_MODE_ONLY",teachingItemVerified=false,coordinateQualified=false},
  },
  COOKING={
   [2538]={kind="trainer_starter",workstation="Cooking Fire",campWorkstation=false,source="https://www.wowhead.com/forever/spell=2538/charred-wolf-meat",identityStrength="WOWHEAD_GUIDE_SPELL_MODE_ONLY",teachingItemVerified=false,coordinateQualified=false},
  },
  ENGINEERING={
   [3918]={kind="trainer",source="https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes",identityStrength="WOWHEAD_GUIDE_SPELL_MODE_ONLY",teachingItemVerified=false,coordinateQualified=false},
  },
 },
}
