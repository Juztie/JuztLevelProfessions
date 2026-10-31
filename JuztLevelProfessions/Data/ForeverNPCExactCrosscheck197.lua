local _,JLP=...
-- Independent exact public NPC/item/spell crosscheck; neither current server
-- stock, vendor access, faction entitlement, nor spawn waypoint is proven.
-- Wowhead Forever NPC 11189 Qia sells Pattern: Mooncloth 14526;
-- Forever spell 18560 is taught by that pattern. 2026-10-24 source check.
JLP.data.foreverNPCExactCrosschecks197={
 contract="JLP-FOREVER-NPC-EXACT-CROSSCHECK-197",productionAuthority=false,
 rows={TAILORING={ [18560]={recipeID=18560,teachingItemID=14526,
  npcID=11189,npcName="Qia",kind="vendor",zone="Winterspring",
  vendorFactionReference="Neutral",itemFactionRequirement="UNKNOWN",
  npcURL="https://www.wowhead.com/forever/npc=11189",
  spellURL="https://www.wowhead.com/forever/spell=18560",
  source="FOREVER_SPELL_AND_NPC_ITEM_PAGE_CROSSCHECK",
  currentVendorStock="UNKNOWN",currentWorldPosition="UNKNOWN",
  nativeDispatchAllowed=false,navigationQualified=false,readOnly=true}
 }}}
