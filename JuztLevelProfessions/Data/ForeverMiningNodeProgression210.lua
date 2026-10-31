local _,JLP=...
-- Wowhead Forever Mining Overview: mining-node skill requirements and suggested
-- leveling zones; NOT observed spawns, route authority or skill-up evidence.
JLP.data.foreverMiningNodeProgression210={
 contract="forever-mining-node-progression-210",readOnly=true,
 guideURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",
 capturedDate="2026-10-24",guideCoverageEnd=225,
 -- Guideline windows describe options, not the minimum to mine every entry.
 recommendedBands={
  {start=1,stop=65,nodes={"Copper Vein"},zones={"Durotar","Mulgore","Tirisfal Glades"},zoneQualification="STARTER_ZONE_EXAMPLES"},
  {start=65,stop=125,nodes={"Copper Vein","Tin Vein","Silver Vein"},zones={"The Barrens","Thousand Needles"}},
  {start=125,stop=175,nodes={"Tin Vein","Silver Vein","Iron Deposit","Gold Vein"},zones={"Desolace","Stranglethorn Vale","Thousand Needles"}},
  {start=175,stop=225,nodes={"Gold Vein","Mithril Deposit","Truesilver Deposit"},zones={"Azshara","Tanaris","The Hinterlands"}},
 },
 -- Requirement is the FIRST value in the source node's four-point difficulty
 -- sequence. E.g. Rich Thorium 275 300 325 375; 300 is NOT its minimum.
 nodeRequirements={
  {"Copper Vein",1,{"Durotar","Mulgore","Tirisfal Glades"}},
  {"Tin Vein",65,{"The Barrens","Thousand Needles"}},
  {"Silver Vein",75,{"The Barrens","Thousand Needles"}},
  {"Iron Deposit",125,{"Desolace","Stranglethorn Vale"}},
  {"Gold Vein",155,{"Stranglethorn Vale","Tanaris"}},
  {"Mithril Deposit",175,{"Azshara","Tanaris","The Hinterlands"}},
  {"Truesilver Deposit",230,{"Azshara","Tanaris","The Hinterlands"}},
  {"Dark Iron Deposit",230,{"Burning Steppes","Searing Gorge","Blackrock Depths"}},
  {"Small Thorium Vein",245,{"Burning Steppes","Tanaris","Un'Goro Crater"}},
  {"Rich Thorium Vein",275,{"Azshara","Eastern Plaguelands","Un'Goro Crater"}},
 },
 smeltSkillupMax=185,smeltGapStart=140,smeltGapEnd=155,
 -- No source proves player owns these ores, learned smelting, forge access,
 -- craft count needed per skill-up, AH price or canonical waypoint.
 nativeDispatchAllowed=false,canonicalWaypoint=nil,
}

-- Individually checked Forever object minima; independent guide color/output facts.
-- Copper compact three-value row remains unassigned; eligibility is not chance.
JLP.data.foreverMiningNodeProgression210.nodeContracts={{resourceKey="COPPER_VEIN",objectID=1731,name="Copper Vein",minimum=1,yellow=nil,green=nil,gray=nil,itemIDs={2770,2835,774,818,1210},sourceURL="https://www.wowhead.com/forever/object=1731/copper-vein",difficultyStatus="PARTIAL_THREE_VALUES_UNASSIGNED",difficultyURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",probability="UNKNOWN",lootQuantity="UNKNOWN"},{resourceKey="TIN_VEIN",objectID=1732,name="Tin Vein",minimum=65,yellow=90,green=115,gray=165,itemIDs={2771,2836,1206,1210,1529,1705},sourceURL="https://www.wowhead.com/forever/object=1732/tin-vein",difficultyStatus="FOREVER_FOUR_THRESHOLD_REFERENCE",difficultyURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",probability="UNKNOWN",lootQuantity="UNKNOWN"},{resourceKey="SILVER_VEIN",objectID=1733,name="Silver Vein",minimum=75,yellow=100,green=125,gray=175,itemIDs={2775,1206,1210,1705},sourceURL="https://www.wowhead.com/forever/object=1733/silver-vein",difficultyStatus="FOREVER_FOUR_THRESHOLD_REFERENCE",difficultyURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",probability="UNKNOWN",lootQuantity="UNKNOWN"},{resourceKey="IRON_DEPOSIT",objectID=1735,name="Iron Deposit",minimum=125,yellow=150,green=175,gray=225,itemIDs={2772,2838,1529,1705,3864,7909},sourceURL="https://www.wowhead.com/forever/object=1735/iron-deposit",difficultyStatus="FOREVER_FOUR_THRESHOLD_REFERENCE",difficultyURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",probability="UNKNOWN",lootQuantity="UNKNOWN"},{resourceKey="GOLD_VEIN",objectID=1734,name="Gold Vein",minimum=155,yellow=180,green=205,gray=255,itemIDs={2776,1529,1705,3864},sourceURL="https://www.wowhead.com/forever/object=1734/gold-vein",difficultyStatus="FOREVER_FOUR_THRESHOLD_REFERENCE",difficultyURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",probability="UNKNOWN",lootQuantity="UNKNOWN"},{resourceKey="MITHRIL_DEPOSIT",objectID=2040,name="Mithril Deposit",minimum=175,yellow=200,green=225,gray=275,itemIDs={3858,7912,3864,7909,7910,9262},sourceURL="https://www.wowhead.com/forever/object=2040/mithril-deposit",difficultyStatus="FOREVER_FOUR_THRESHOLD_REFERENCE",difficultyURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",probability="UNKNOWN",lootQuantity="UNKNOWN"},{resourceKey="TRUESILVER_DEPOSIT",objectID=2047,name="Truesilver Deposit",minimum=230,yellow=255,green=280,gray=330,itemIDs={7911,3864,7909,7910},sourceURL="https://www.wowhead.com/forever/object=2047/truesilver-deposit",difficultyStatus="FOREVER_FOUR_THRESHOLD_REFERENCE",difficultyURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",probability="UNKNOWN",lootQuantity="UNKNOWN"},{resourceKey="DARK_IRON_DEPOSIT",objectID=165658,name="Dark Iron Deposit",minimum=230,yellow=255,green=280,gray=330,itemIDs={11370,9262,11382,11754},sourceURL="https://www.wowhead.com/forever/object=165658/dark-iron-deposit",difficultyStatus="FOREVER_FOUR_THRESHOLD_REFERENCE",difficultyURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",probability="UNKNOWN",lootQuantity="UNKNOWN"},{resourceKey="SMALL_THORIUM_VEIN",objectID=324,name="Small Thorium Vein",minimum=245,yellow=270,green=295,gray=345,itemIDs={10620,12365,7910,9262,12361,12799,12364},sourceURL="https://www.wowhead.com/forever/object=324/small-thorium-vein",difficultyStatus="FOREVER_FOUR_THRESHOLD_REFERENCE",difficultyURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",probability="UNKNOWN",lootQuantity="UNKNOWN"},{resourceKey="RICH_THORIUM_VEIN",objectID=175404,name="Rich Thorium Vein",minimum=275,yellow=300,green=325,gray=375,itemIDs={10620,12365,7910,12361,12799,12363,12800,12364},sourceURL="https://www.wowhead.com/forever/object=175404/rich-thorium-vein",difficultyStatus="FOREVER_FOUR_THRESHOLD_REFERENCE",difficultyURL="https://www.wowhead.com/forever/guide/professions/mining/overview-leveling",probability="UNKNOWN",lootQuantity="UNKNOWN"}}
