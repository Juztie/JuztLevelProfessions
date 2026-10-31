local _, JLP = ...
-- P0-216: individual Forever spell-page joins; DB70450 reagent/output identities.
-- Guide / historic skill thresholds are NOT independent same-spell live evidence.
-- Advisory only; no learned-, trainer-stock-, waypoint- or native rights.
local base=JLP.data and JLP.data.foreverPrimaryRecipeParity212
if not (base and type(base.rows)=="table" and type(base.conflicts)=="table") then return end
local rows={
 [11449]={professionKey="ALCHEMY",recipeID=11449,recipeName="Elixir of Agility",outputItemID=8949,outputQuantity=2,
  materials={{itemID=3820,quantity=1},{itemID=3821,quantity=1},{itemID=3372,quantity=1}},
  source="https://www.wowhead.com/forever/spell=11449/elixir-of-agility",
  status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [9920]={professionKey="BLACKSMITHING",recipeID=9920,recipeName="Solid Grinding Stone",outputItemID=7966,outputQuantity=2,
  materials={{itemID=7912,quantity=4}},
  source="https://www.wowhead.com/forever/spell=9920/solid-grinding-stone",
  status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [19788]={professionKey="ENGINEERING",recipeID=19788,recipeName="Dense Blasting Powder",outputItemID=15992,outputQuantity=2,
  materials={{itemID=12365,quantity=2}},
  source="https://www.wowhead.com/forever/spell=19788/dense-blasting-powder",
  guideSkillMinimum=250,guideSkillSource="https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes",
  guideSkillOnlyNameJoin=true, -- NO exact-spell skill admission
  status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [3818]={professionKey="LEATHERWORKING",recipeID=3818,recipeName="Cured Heavy Hide",outputItemID=4236,outputQuantity=2,
  materials={{itemID=4235,quantity=1},{itemID=4289,quantity=3}},
  source="https://www.wowhead.com/forever/spell=3818/cured-heavy-hide",
  status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false}
}
for id,row in pairs(rows) do
 if base.rows[id] or base.conflicts[id] then
  base.conflicts[id]={recipeID=id,status="DUPLICATE_SOURCE_REFERENCE",readOnly=true,nativeDispatchAllowed=false}
 else base.rows[id]=row end
end
base.sourceReview216="2026-10-24"
base.latestAdditions216=4
