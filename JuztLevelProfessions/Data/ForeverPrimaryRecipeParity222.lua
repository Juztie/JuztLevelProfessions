local _,JLP=...
-- P0-222 independently reviewed Forever spell/DB70450 direct reagent parity.
-- Source is a public spell page; no training availability, item ownership,
-- live difficulty, guaranteed skill-up, native crafting or waypoint authority.
local source=JLP.data and JLP.data.foreverPrimaryRecipeParity212
if not (source and type(source.rows)=="table" and type(source.conflicts)=="table") then return end
local id=7408
if source.rows[id] or source.conflicts[id] then
 source.conflicts[id]={recipeID=id,status="DUPLICATE_SOURCE_REFERENCE_222",readOnly=true,nativeDispatchAllowed=false}
else
 source.rows[id]={professionKey="BLACKSMITHING",recipeID=id,recipeName="Heavy Copper Maul",
  outputItemID=6214,outputQuantity=2,sourceSkillMinimum=65,
  materials={{itemID=2840,quantity=12},{itemID=2880,quantity=2},{itemID=2318,quantity=2}},
  source="https://www.wowhead.com/forever/spell=7408/heavy-copper-maul",
  sourceStationKind="ANVIL",trainerNames={"Dwukk","Guillaume Sorouy","James Van Brunt","Gur'dok"},
  partialExactActorReferences={{name="James Van Brunt",npcID=4596,faction="Horde",zone="Undercity",
    referenceURL="https://www.wowhead.com/forever/npc=4596/james-van-brunt",
    navigationQualified=false,stockVerified=false}},
  trainerIDsVerified=false,trainerStockVerified=false,
  status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false}
end
source.latestSourceReview222="2026-10-24"
