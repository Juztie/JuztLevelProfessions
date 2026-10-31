local _, JLP = ...
-- Source-qualified historical Classic uiMapIDs; client C_Map still validates each
-- map ID and type at runtime. Only unequivocal WHOLE-ZONE requirements are listed.
-- Source: https://warcraft.wiki.gg/wiki/UiMapID/Classic (Classic 1.13.2 family)
-- NOT a map of verified micro/subzone exceptions (Azshara Bay of Storms,
-- Jaguero Isle, Jademir Lake): those MUST NOT inherit a base-zone tier.
JLP.data.foreverFishingMapIdentity={schema=1,source="WARCRAFT_WIKI_UIMAPID_CLASSIC_1_13_2",
 byMapID={
 [1411]="Durotar",[1412]="Mulgore",[1413]="The Barrens",
 [1431]="Duskwood",[1432]="Loch Modan",[1433]="Redridge Mountains",
 [1435]="Swamp of Sorrows",[1436]="Westfall",[1437]="Wetlands",
 [1438]="Teldrassil",[1439]="Darkshore",[1440]="Ashenvale",
 [1441]="Thousand Needles",[1442]="Stonetalon Mountains",
 [1443]="Desolace",[1444]="Feralas",[1445]="Dustwallow Marsh",
 [1446]="Tanaris",[1448]="Felwood",[1449]="Un'Goro Crater",
 [1450]="Moonglade",[1451]="Silithus"
 }}
