local _, JLP = ...
-- P0-206: Individual Forever teaching-item pages + Forever Cooking guide.
-- Names below are PUBLIC GUIDE seller leads, NOT NPC-ID/stock/canonical
-- coordinates/travel or verified recipe ownership. Read-only fields only.
local root="https://www.wowhead.com/forever/"
JLP.data.secondaryRecipeLearning206={
 contract="JLP-SECONDARY-EXACT-TEACHING-ITEMS-206",source="WOWHEAD_FOREVER_ITEM_PLUS_GUIDE",
 readOnly=true,nativeDispatchAllowed=false,
 professions={COOKING={
  {spellID=7751,itemID=6325,requiredSkill=1,name="Brilliant Smallfish",
   seller="Sewa Mistrunner",faction="Horde",vendorZone="Thunder Bluff",
   teachingItemURL=root.."item=6325/recipe-brilliant-smallfish"},
  {spellID=7753,itemID=6328,requiredSkill=50,name="Longjaw Mud Snapper",
   seller="Naal Mistrunner",faction="Horde",vendorZone="Thunder Bluff",
   teachingItemURL=root.."item=6328/recipe-longjaw-mud-snapper"},
  {spellID=7755,itemID=6330,requiredSkill=100,name="Bristle Whisker Catfish",
   seller="Naal Mistrunner",faction="Horde",vendorZone="Thunder Bluff",
   teachingItemURL=root.."item=6330/recipe-bristle-whisker-catfish"},
  {spellID=20916,itemID=17062,requiredSkill=175,name="Mithril Head Trout",
   seller="Shankys",faction="Horde",vendorZone="Orgrimmar",
   teachingItemURL=root.."item=17062/recipe-mithril-head-trout"},
 }},
 guideURL=root.."guide/professions/cooking/overview-leveling",
 npcIDAuthority=false,vendorStockAuthority=false,waypointAuthority=false}
