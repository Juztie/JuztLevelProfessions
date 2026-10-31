local _, JLP = ...

-- Conservative travel metadata for the profession source catalogue. This is not
-- a path-finding graph: it only classifies known source zones so the route layer
-- can prefer nearby, progression-safe profession stops without inventing travel
-- times or assuming that a flight path has been unlocked.
JLP.data.travel = {
    evidence = "classic-world-geography-continuity",
    mapMeta = {
        [1424] = { zone="Hillsbrad Foothills", continent="Eastern Kingdoms" },
        [1429] = { zone="Elwynn Forest", continent="Eastern Kingdoms" },
        [1442] = { zone="Stonetalon Mountains", continent="Kalimdor" },
        [1445] = { zone="Dustwallow Marsh", continent="Kalimdor" },
        [1450] = { zone="Moonglade", continent="Kalimdor" },
        [1451] = { zone="Silithus", continent="Kalimdor" },
        [1452] = { zone="Winterspring", continent="Kalimdor" },
        [1453] = { zone="Stormwind City", continent="Eastern Kingdoms", capital=true },
        [1454] = { zone="Orgrimmar", continent="Kalimdor", capital=true },
        [1455] = { zone="Ironforge", continent="Eastern Kingdoms", capital=true },
        [1456] = { zone="Thunder Bluff", continent="Kalimdor", capital=true },
        [1457] = { zone="Darnassus", continent="Kalimdor", capital=true },
        [1458] = { zone="Undercity", continent="Eastern Kingdoms", capital=true },
    },
    zoneContinents = {
        ["Arathi Highlands"] = "Eastern Kingdoms",
        ["Darnassus"] = "Kalimdor",
        ["Dire Maul"] = "Kalimdor",
        ["Dustwallow Marsh"] = "Kalimdor",
        ["Elwynn Forest"] = "Eastern Kingdoms",
        ["Feralas"] = "Kalimdor",
        ["Hillsbrad Foothills"] = "Eastern Kingdoms",
        ["Ironforge"] = "Eastern Kingdoms",
        ["Moonglade"] = "Kalimdor",
        ["Orgrimmar"] = "Kalimdor",
        ["Silithus"] = "Kalimdor",
        ["Stonetalon Mountains"] = "Kalimdor",
        ["Stormwind City"] = "Eastern Kingdoms",
        ["Thunder Bluff"] = "Kalimdor",
        ["Uldaman"] = "Eastern Kingdoms",
        ["Undercity"] = "Eastern Kingdoms",
        ["Winterspring"] = "Kalimdor",
    },
    proximity = {
        -- Normalized UI-map distance only.  This is guidance, not yardage and
        -- never proves NPC identity; source verification still requires the
        -- matching trainer/vendor/source workspace.
        nearNormalized = 0.025,
        evidence = "normalized-map-distance-guidance",
    },
    earlyTrainer = {
        -- Early rank training is intentionally stricter than generic same-zone
        -- routing: it is only recommended when live map position proves a small
        -- same-map detour, or the exact trainer workspace is already open.
        maxNormalizedDetour = 0.12,
        policy = "eligible-and-low-detour-only",
        evidence = "live-map-low-detour-opportunity",
    },
    weights = {
        sameMap = 0,
        sameContinent = 10,
        crossContinent = 30,
        unknown = 20,
        dungeon = 40,
    },
}
