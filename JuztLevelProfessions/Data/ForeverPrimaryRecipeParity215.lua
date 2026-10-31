local _, JLP = ...
-- P0-215: Four independently viewed individual Wowhead Forever spell pages.
-- DB70450 confirms exact SpellID/name/CreateItem and immediate reagents.
-- The DB70450 effect base is historical, NOT a fixed-output authority.
-- This read-only catalogue is not live learned-state, vendor stock, actual
-- skill-up, an inventory receipt, navigation or native crafting permission.
local base=JLP.data and JLP.data.foreverPrimaryRecipeParity212
if not (base and type(base.rows)=="table" and type(base.conflicts)=="table") then return end
local rows={
 [7836]={professionKey="ALCHEMY",recipeID=7836,recipeName="Blackmouth Oil",
  outputItemID=6370,outputQuantity=2,
  materials={{itemID=6358,quantity=2},{itemID=3371,quantity=1}},
  source="https://www.wowhead.com/forever/spell=7836/blackmouth-oil",
  sourceSkillMinimum=80,teachingKind="TRAINER_REFERENCE",trainerNames={"Yelmak","Doctor Marsh","Bena Winterhoof","Doctor Herbert Halsey","Rogvar","Serge Hinott"},
  status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [2668]={professionKey="BLACKSMITHING",recipeID=2668,recipeName="Rough Bronze Leggings",
  outputItemID=2865,outputQuantity=2,materials={{itemID=2841,quantity=6}},
  source="https://www.wowhead.com/forever/spell=2668/rough-bronze-leggings",
  status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [3941]={professionKey="ENGINEERING",recipeID=3941,recipeName="Small Bronze Bomb",
  outputItemID=4374,outputQuantity=3,materials={{itemID=4364,quantity=4},{itemID=2841,quantity=2},{itemID=4404,quantity=1},{itemID=2592,quantity=1}},
  source="https://www.wowhead.com/forever/spell=3941/small-bronze-bomb",
  sourceSkillMinimum=120,sourceStationKind="ANVIL",teachingKind="TRAINER_REFERENCE",
  trainerNames={"Nogg","Franklin Lloyd","Roxxik","Buzzek Bracketswing"},
  partialExactActorReferences={{name="Franklin Lloyd",npcID=11031,source="https://www.wowhead.com/forever/npc=11031/franklin-lloyd",role="EXTERNAL_NPC_IDENTITY_ONLY",waypointAuthorized=false}},
  status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [3759]={professionKey="LEATHERWORKING",recipeID=3759,recipeName="Embossed Leather Pants",
  outputItemID=4242,outputQuantity=2,materials={{itemID=4231,quantity=1},{itemID=2318,quantity=6},{itemID=2320,quantity=2}},
  source="https://www.wowhead.com/forever/spell=3759/embossed-leather-pants",
  status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
}
for id,proof in pairs(rows) do
 if base.rows[id] or base.conflicts[id] then
  base.conflicts[id]={recipeID=id,status="DUPLICATE_SOURCE_REFERENCE",readOnly=true,nativeDispatchAllowed=false}
 else
  base.rows[id]=proof
 end
end
base.sourceReview215="2026-10-24"
base.latestAdditions215=4
