local _, JLP = ...
-- Wowhead Forever spell page lists these as "Taught by" for exact spell 3320.
-- Names/zones/faction are source references only; numeric NPC identity, present
-- server training stock, player eligibility and canonical waypoint are UNKNOWN.
JLP.data.foreverTrainerNameReferences200={
 contract="JLP-FOREVER-TRAINER-NAME-REFERENCE-200",source="WOWHEAD_FOREVER_TAUGHT_BY",
 sourceURL="https://www.wowhead.com/forever/spell=3320/rough-grinding-stone",
 nativeDispatchAllowed=false,executionEligible=false,readOnly=true,
 rows={
  TAILORING={
   [18401]={
    {npcName="Daryl Stack",npcID=2399,npcURL="https://www.wowhead.com/forever/npc=2399/daryl-stack",
     zone="Hillsbrad Foothills",faction="Horde",
     sourceURL="https://www.wowhead.com/forever/spell=18401/bolt-of-runecloth"},
   },
   [2964]={
    {npcName="Snang",zone="Orgrimmar",faction="Horde",
     sourceURL="https://www.wowhead.com/forever/spell=2964/bolt-of-woolen-cloth"},
    {npcName="Tepa",zone="Thunder Bluff",faction="Horde",
     sourceURL="https://www.wowhead.com/forever/spell=2964/bolt-of-woolen-cloth"},
    {npcName="Rhiannon Davis",zone="Undercity",faction="Horde",
     sourceURL="https://www.wowhead.com/forever/spell=2964/bolt-of-woolen-cloth"},
   },
  },
  ENGINEERING={
   [3924]={
    {npcName="Franklin Lloyd",npcID=11031,npcURL="https://www.wowhead.com/forever/npc=11031/franklin-lloyd",
     zone="Undercity",faction="Horde",
     sourceURL="https://www.wowhead.com/forever/spell=3924/copper-tube"},
   },
  },
  BLACKSMITHING={
   [3320]={
    {npcName="Angus Hammerhand",zone="Tirisfal Glades",faction="Horde"},
    {npcName="Dwukk",zone="Durotar",faction="Horde"},
    {npcName="Gur'dok",zone="Riverglades",faction="Horde"},
   },
   [3337]={
    {npcName="Angus Hammerhand",zone="Tirisfal Glades",faction="Horde",
     sourceURL="https://www.wowhead.com/forever/spell=3337/heavy-grinding-stone"},
    {npcName="James Van Brunt",zone="Undercity",faction="Horde",
     sourceURL="https://www.wowhead.com/forever/spell=3337/heavy-grinding-stone"},
    {npcName="Saru Steelfury",zone="Orgrimmar",faction="Horde",
     sourceURL="https://www.wowhead.com/forever/spell=3337/heavy-grinding-stone"},
   },
  },
 },
}
