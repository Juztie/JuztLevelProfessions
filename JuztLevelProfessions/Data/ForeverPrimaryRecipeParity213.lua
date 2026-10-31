local _, JLP = ...
-- P0-213: additional individually reviewed Forever Spell page fields.
-- Reference provenance only; no learned state, skill-up probability, NPC identity or waypoint.
local source=JLP.data and JLP.data.foreverPrimaryRecipeParity212
if not (source and source.rows and source.conflicts) then return end
local additions={
 [3171]={professionKey="ALCHEMY",recipeID=3171,recipeName="Elixir of Wisdom",outputItemID=3383,outputQuantity=2,materials={{itemID=785,quantity=1},{itemID=2450,quantity=2},{itemID=3371,quantity=1}},source="https://www.wowhead.com/forever/spell=3171/elixir-of-wisdom",status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [2661]={professionKey="BLACKSMITHING",recipeID=2661,recipeName="Copper Chain Belt",outputItemID=2851,outputQuantity=2,materials={{itemID=2840,quantity=6}},source="https://www.wowhead.com/forever/spell=2661/copper-chain-belt",status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [3923]={professionKey="ENGINEERING",recipeID=3923,recipeName="Rough Copper Bomb",outputItemID=4360,outputQuantity=3,materials={{itemID=2840,quantity=1},{itemID=4359,quantity=1},{itemID=4357,quantity=2},{itemID=2589,quantity=1}},source="https://www.wowhead.com/forever/spell=3923/rough-copper-bomb",sourceSkillMinimum=30,status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [3950]={professionKey="ENGINEERING",recipeID=3950,recipeName="Big Bronze Bomb",outputItemID=4380,outputQuantity=4,materials={{itemID=4377,quantity=2},{itemID=2841,quantity=3},{itemID=4404,quantity=1}},source="https://www.wowhead.com/forever/spell=3950/big-bronze-bomb",sourceSkillMinimum=140,status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [3930]={professionKey="ENGINEERING",recipeID=3930,recipeName="Crafted Heavy Shot",outputItemID=8068,outputQuantity=201,materials={{itemID=4364,quantity=1},{itemID=2840,quantity=1}},source="https://www.wowhead.com/forever/spell=3930/crafted-heavy-shot",status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [2149]={professionKey="LEATHERWORKING",recipeID=2149,recipeName="Handstitched Leather Boots",outputItemID=2302,outputQuantity=2,materials={{itemID=2318,quantity=2},{itemID=2320,quantity=1}},source="https://www.wowhead.com/forever/spell=2149/handstitched-leather-boots",status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [3756]={professionKey="LEATHERWORKING",recipeID=3756,recipeName="Embossed Leather Gloves",outputItemID=4239,outputQuantity=2,materials={{itemID=2318,quantity=3},{itemID=2320,quantity=2}},source="https://www.wowhead.com/forever/spell=3756/embossed-leather-gloves",status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
}
for id,row in pairs(additions) do
 if source.rows[id] or source.conflicts[id] then
  source.conflicts[id]={recipeID=id,status="DUPLICATE_SOURCE_REFERENCE",readOnly=true,nativeDispatchAllowed=false}
 else source.rows[id]=row end
end
-- Forever 3931 displays 3 but a historical comment describes 1-3. Preserve
-- explicit uncertainty rather than granting a fixed-yield producer credit.
source.conflicts[3931]={professionKey="ENGINEERING",recipeID=3931,
 status="EXTERNAL_YIELD_CONFLICT_REQUIRES_LIVE_SCHEMATIC",
 source="https://www.wowhead.com/forever/spell=3931/coarse-dynamite",
 readOnly=true,nativeDispatchAllowed=false}
source.sourceReview213="2026-10-24"
source.latestAdditions213=7
