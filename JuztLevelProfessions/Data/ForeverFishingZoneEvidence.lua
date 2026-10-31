local _, JLP = ...
-- Zone requirements from https://www.wowhead.com/forever/guide/professions/fishing/overview-leveling
-- Maps are not yet tied to verified Forever uiMapID/coordinate transforms; never fabricate pins.
local function tier(minimum,certain,names)
    return {minSkill=minimum,guaranteedCatchSkill=certain,zones=names}
end
JLP.data.foreverFishingZoneEvidence={
    contract="forever-fishing-zone-requirements-v1",sourceURL="https://www.wowhead.com/forever/guide/professions/fishing/overview-leveling",
    nativeDispatchAllowed=false,hasVerifiedMapCoordinates=false,
    tiers={
        tier(1,25,{"Dun Morogh","Durotar","Elwynn Forest","Mulgore","Teldrassil","Tirisfal Glades","Zephras Isle"}),
        tier(1,75,{"The Barrens","Darkshore","Darnassus","Ironforge","Loch Modan","Orgrimmar","Silverpine Forest","Stormwind City","Thunder Bluff","Undercity","Westfall","Blackfathom Deeps","The Deadmines","The Wailing Caverns"}),
        tier(55,150,{"Ashenvale","Duskwood","Hillsbrad Foothills","Redridge Mountains","Stonetalon Mountains","Wetlands"}),
        tier(130,225,{"Alterac Mountains","Arathi Highlands","Desolace","Dustwallow Marsh","Stranglethorn Vale (excluding Jaguero Isle)","Swamp of Sorrows","Thousand Needles","Scarlet Monastery"}),
        tier(205,300,{"Azshara (excluding Bay of Storms)","Felwood","Feralas","The Hinterlands","Maraudon","Moonglade","Stranglethorn Vale (Jaguero Isle)","Tanaris","Un'Goro Crater","Western Plaguelands"}),
        tier(330,425,{"Azshara (Bay of Storms)","Burning Steppes","Deadwind Pass","Eastern Plaguelands","Feralas (Jademir Lake)","Silithus","Winterspring","Zul'Gurub","Scholomance","Stratholme"}),
    },
}
