local _,JLP=...
-- P0-224: two independent Forever spell pages, DB70450 exact direct reagents.
-- NPC names are public learning references ONLY, not current stock/location.
local root=JLP.data and JLP.data.foreverPrimaryRecipeParity212
if not (root and type(root.rows)=="table" and type(root.conflicts)=="table") then return end
local rows={
 [9959]={professionKey="BLACKSMITHING",recipeID=9959,recipeName="Heavy Mithril Breastplate",outputItemID=7930,outputQuantity=2,sourceSkillMinimum=230,
 materials={{itemID=3860,quantity=16}},source="https://www.wowhead.com/forever/spell=9959/heavy-mithril-breastplate",
 sourceStationKind="ANVIL",trainerStockVerified=false,trainerIDsVerified=false,
 status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false},
 [19047]={professionKey="LEATHERWORKING",recipeID=19047,recipeName="Cured Rugged Hide",outputItemID=15407,outputQuantity=3,sourceSkillMinimum=250,
 materials={{itemID=8171,quantity=1},{itemID=15409,quantity=1}},source="https://www.wowhead.com/forever/spell=19047/cured-rugged-hide",
 sourceStationKind="TANNING_RACK",trainerNames={"Hahrana Ironhide","Drakk Stonehand"},
 partialExactActorReferences={{name="Hahrana Ironhide",npcID=11098,faction="Horde",zone="Feralas",navigationQualified=false,stockVerified=false}},
 trainerStockVerified=false,trainerIDsVerified=false,
 status="EXACT_FOREVER_SPELL_AND_DB70450_PARITY",readOnly=true,nativeDispatchAllowed=false}
}
for id,row in pairs(rows) do
 if root.rows[id] or root.conflicts[id] then
  root.conflicts[id]={recipeID=id,status="DUPLICATE_SOURCE_REFERENCE_224",readOnly=true,nativeDispatchAllowed=false}
 else root.rows[id]=row end
end
root.latestSourceReview224="2026-10-24"
