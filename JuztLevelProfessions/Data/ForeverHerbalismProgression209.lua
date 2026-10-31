local _,JLP=...
-- Wowhead Forever Herbalism guide updated 2026-10-23. Source zones and
-- node requirements are reference guidance, never a live spawn, skill-up
-- guarantee, canonical map coordinate or player movement authorization.
JLP.data.foreverHerbalismProgression209={
 contract="forever-herbalism-source-coverage-209",readOnly=true,
 guideURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",
 guideUpdated="2026-10-23",guideCoverageEnd=225,
 -- Individual NPC IDs confirmed by the exact Forever guide links. Guide
 -- lists public waypoint text, deliberately NOT canonical owner coordinates.
 -- The NPC page may describe a different trainer tier (e.g. Faruza), so
 -- current teaching repertoire and player access always remain UNKNOWN.
 hordeTrainerReferences={
  {npcID=267329,name="Zor'la",zone="Durotar",kind="APPRENTICE_GUIDE_REFERENCE"},
  {npcID=267332,name="Garan Sunstrider",zone="Mulgore",kind="APPRENTICE_GUIDE_REFERENCE"},
  {npcID=267326,name="Florence Nightshade",zone="Tirisfal Glades",kind="APPRENTICE_GUIDE_REFERENCE"},
  {npcID=3404,name="Jandi",zone="Orgrimmar",kind="GENERAL_GUIDE_REFERENCE"},
  {npcID=3013,name="Komin Winterhoof",zone="Thunder Bluff",kind="GENERAL_GUIDE_REFERENCE"},
  {npcID=4614,name="Martha Alliestar",zone="Undercity",kind="GENERAL_GUIDE_REFERENCE"},
  {npcID=3185,name="Mishiki",zone="Durotar",kind="GENERAL_GUIDE_REFERENCE"},
  {npcID=2114,name="Faruza",zone="Tirisfal Glades",kind="GENERAL_GUIDE_REFERENCE"},
  {npcID=2390,name="Aranae Venomblood",zone="Hillsbrad Foothills",kind="GENERAL_GUIDE_REFERENCE"},
  {npcID=2856,name="Angrun",zone="Stranglethorn Vale",kind="GENERAL_GUIDE_REFERENCE"},
  {npcID=8146,name="Ruw",zone="Feralas",kind="GENERAL_GUIDE_REFERENCE"},
 },
 recommendedBands={
  {start=1,stop=70,resources={"Peacebloom","Silverleaf","Earthroot"},zones={"Durotar","Mulgore","Tirisfal Glades"}},
  {start=70,stop=115,resources={"Mageroyal","Briarthorn","Stranglekelp"},zones={"Silverpine Forest"}},
  {start=115,stop=170,resources={"Stranglekelp","Bruiseweed","Wild Steelbloom","Kingsblood","Liferoot"},zones={"Hillsbrad Foothills","Stonetalon Mountains"}},
  {start=170,stop=205,resources={"Kingsblood","Liferoot","Fadeleaf","Goldthorn","Khadgar's Whisker"},zones={"Stranglethorn Vale","Arathi Highlands"}},
  {start=205,stop=225,resources={"Fadeleaf","Goldthorn","Khadgar's Whisker","Wintersbite","Firebloom","Purple Lotus"},zones={"Alterac Mountains","Tanaris","Searing Gorge"}},
 },
 -- Explicit FIRST number in the guide's four-number node table is a node
 -- requirement, not a route starting skill or a skill-up probability.
 nodes={
  {"Peacebloom",1,{"Durotar","Mulgore","Tirisfal Glades"}},
  {"Silverleaf",1,{"Durotar","Mulgore","Tirisfal Glades"}},
  {"Earthroot",15,{"Durotar","Mulgore","Tirisfal Glades"}},
  {"Mageroyal",50,{"Silverpine Forest","The Barrens"}},
  {"Briarthorn",70,{"Silverpine Forest","The Barrens"}},
  {"Stranglekelp",85,{"Silverpine Forest","Stranglethorn Vale"}},
  {"Bruiseweed",100,{"Hillsbrad Foothills","Stonetalon Mountains"}},
  {"Wild Steelbloom",115,{"Hillsbrad Foothills","Stonetalon Mountains"}},
  {"Kingsblood",125,{"Hillsbrad Foothills","Stranglethorn Vale"}},
  {"Liferoot",150,{"Hillsbrad Foothills","Stranglethorn Vale"}},
  {"Fadeleaf",160,{"Stranglethorn Vale","Arathi Highlands"}},
  {"Goldthorn",170,{"Stranglethorn Vale","Arathi Highlands"}},
  {"Khadgar's Whisker",185,{"Stranglethorn Vale","Arathi Highlands"}},
  {"Wintersbite",195,{"Alterac Mountains"}},
  {"Firebloom",205,{"Tanaris","Searing Gorge"}},
  {"Purple Lotus",210,{"Tanaris","Stranglethorn Vale"}},
  {"Arthas' Tears",220,{"Eastern Plaguelands","Western Plaguelands"}},
  {"Sungrass",230,{"Felwood","Feralas","The Hinterlands"}},
  {"Blindweed",235,{"Swamp of Sorrows","Un'Goro Crater"}},
  {"Ghost Mushroom",245,{"The Hinterlands","Maraudon"}},
  {"Gromsblood",250,{"Felwood","Blasted Lands"}},
  {"Golden Sansam",260,{"Felwood","Feralas","Un'Goro Crater"}},
  {"Dreamfoil",270,{"Felwood","Un'Goro Crater"}},
  {"Mountain Silversage",280,{"Winterspring","Un'Goro Crater"}},
  {"Plaguebloom",285,{"Eastern Plaguelands","Western Plaguelands"}},
  {"Icecap",290,{"Winterspring"}},
 },
}

-- Compact source-qualified node fields; external reference, never current spawn/loot.
JLP.data.foreverHerbalismProgression209.nodeContracts={
 {resourceKey="PEACEBLOOM",objectID=1618,name="Peacebloom",primaryItemID=2447,minimum=1,yellow=25,green=50,gray=100,itemIDs={2447},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=1618",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="SILVERLEAF",objectID=1617,name="Silverleaf",primaryItemID=765,minimum=1,yellow=25,green=50,gray=100,itemIDs={765},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=1617",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="EARTHROOT",objectID=1619,name="Earthroot",primaryItemID=2449,minimum=15,yellow=40,green=65,gray=115,itemIDs={2449,249399},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=1619",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="MAGEROYAL",objectID=1620,name="Mageroyal",primaryItemID=785,minimum=50,yellow=75,green=100,gray=150,itemIDs={785,2452,249399},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=1620",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="BRIARTHORN",objectID=1621,name="Briarthorn",primaryItemID=2450,minimum=70,yellow=95,green=120,gray=170,itemIDs={2450,2452,249399},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=1621",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="STRANGLEKELP",objectID=2045,name="Stranglekelp",primaryItemID=3820,minimum=85,yellow=110,green=135,gray=185,itemIDs={3820,249399},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=2045",accessNote="Verify underwater access; no route or air supply is assumed."},
 {resourceKey="BRUISEWEED",objectID=1622,name="Bruiseweed",primaryItemID=2453,minimum=100,yellow=125,green=150,gray=200,itemIDs={2453},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=1622",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="WILD_STEELBLOOM",objectID=1623,name="Wild Steelbloom",primaryItemID=3355,minimum=115,yellow=140,green=165,gray=215,itemIDs={3355},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=1623",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="GRAVE_MOSS",objectID=1628,name="Grave Moss",primaryItemID=3369,minimum=120,yellow=145,green=170,gray=220,itemIDs={3369},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=1628",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="KINGSBLOOD",objectID=1624,name="Kingsblood",primaryItemID=3356,minimum=125,yellow=150,green=175,gray=225,itemIDs={3356},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=1624",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="LIFEROOT",objectID=2041,name="Liferoot",primaryItemID=3357,minimum=150,yellow=175,green=200,gray=250,itemIDs={3357},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=2041",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="FADELEAF",objectID=2042,name="Fadeleaf",primaryItemID=3818,minimum=160,yellow=185,green=210,gray=260,itemIDs={3818},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=2042",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="GOLDTHORN",objectID=2046,name="Goldthorn",primaryItemID=3821,minimum=170,yellow=195,green=220,gray=270,itemIDs={3821},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=2046",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="KHADGARS_WHISKER",objectID=2043,name="Khadgar's Whisker",primaryItemID=3358,minimum=185,yellow=210,green=235,gray=285,itemIDs={3358},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=2043",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="WINTERSBITE",objectID=2044,name="Wintersbite",primaryItemID=3819,minimum=195,yellow=220,green=245,gray=295,itemIDs={3819},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=2044",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="FIREBLOOM",objectID=2866,name="Firebloom",primaryItemID=4625,minimum=205,yellow=230,green=255,gray=305,itemIDs={4625},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=2866",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="PURPLE_LOTUS",objectID=142140,name="Purple Lotus",primaryItemID=8831,minimum=210,yellow=235,green=260,gray=310,itemIDs={8831,8153},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=142140",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="ARTHAS_TEARS",objectID=142141,name="Arthas' Tears",primaryItemID=8836,minimum=220,yellow=245,green=270,gray=320,itemIDs={8836},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=142141",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="SUNGRASS",objectID=142142,name="Sungrass",primaryItemID=8838,minimum=230,yellow=255,green=280,gray=330,itemIDs={8838},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=142142",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="BLINDWEED",objectID=142143,name="Blindweed",primaryItemID=8839,minimum=235,yellow=260,green=285,gray=335,itemIDs={8839},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=142143",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="GHOST_MUSHROOM",objectID=142144,name="Ghost Mushroom",primaryItemID=8845,minimum=245,yellow=270,green=295,gray=345,itemIDs={8845},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=142144",accessNote="Verify cave access; no dungeon admission or cave route is assumed."},
 {resourceKey="GROMSBLOOD",objectID=142145,name="Gromsblood",primaryItemID=8846,minimum=250,yellow=275,green=300,gray=350,itemIDs={8846},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=142145",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="GOLDEN_SANSAM",objectID=176583,name="Golden Sansam",primaryItemID=13464,minimum=260,yellow=285,green=310,gray=360,itemIDs={13464},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=176583",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="DREAMFOIL",objectID=176584,name="Dreamfoil",primaryItemID=13463,minimum=270,yellow=290,green=315,gray=370,itemIDs={13463},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=176584",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="MOUNTAIN_SILVERSAGE",objectID=176586,name="Mountain Silversage",primaryItemID=13465,minimum=280,yellow=305,green=330,gray=380,itemIDs={13465},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=176586",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="PLAGUEBLOOM",objectID=176587,name="Plaguebloom",primaryItemID=13466,minimum=285,yellow=310,green=335,gray=385,itemIDs={13466},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=176587",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="ICECAP",objectID=176588,name="Icecap",primaryItemID=13467,minimum=290,yellow=315,green=340,gray=390,itemIDs={13467},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=176588",accessNote="Verify current node and physical access; historical point is not a terrain route."},
 {resourceKey="BLACK_LOTUS",objectID=176589,name="Black Lotus",primaryItemID=13468,minimum=300,yellow=325,green=350,gray=400,itemIDs={13468},difficultyStatus="FOREVER_EXTERNAL_FOUR_THRESHOLD_REFERENCE",sourceURL="https://www.wowhead.com/forever/guide/professions/herbalism/overview-leveling",objectURL="https://www.wowhead.com/forever/object=176589",accessNote="Verify current node and physical access; historical point is not a terrain route."}
}
