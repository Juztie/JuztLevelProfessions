local _, JLP = ...

JLP.Constants = {
    TARGET_INTERFACE = 16001,
    TARGET_BUILD = 70009, -- Legacy production dataset baseline; not the active Forever build.
    LEGACY_PRODUCTION_BASELINE_BUILD = 70009,
    HISTORICAL_REFERENCE_BUILD = 70374,
    CURRENT_FOREVER_BUILD = 70450, -- Most recent bundled reference dataset, NEVER a required runtime build.
    LEGACY_REQUALIFICATION_BUILD = 70245,
    DB_SCHEMA = 4,
    SNAPSHOT_SCHEMA = 1,
    FULL_SCAN_COOLDOWN = 15 * 60,
    MAX_PRICE_BUCKETS_PER_ITEM = 48,
    PROFESSIONS = {
        TAILORING = "TAILORING",
        ENCHANTING = "ENCHANTING",
        BLACKSMITHING = "BLACKSMITHING",
        ENGINEERING = "ENGINEERING",
        ALCHEMY = "ALCHEMY",
        LEATHERWORKING = "LEATHERWORKING",
        HERBALISM = "HERBALISM",
        MINING = "MINING",
        SKINNING = "SKINNING",
        COOKING = "COOKING",
        FIRST_AID = "FIRST_AID",
        FISHING = "FISHING",
    },
    PROGRESSION_STRATEGIES = {
        RECIPE_CRAFTING = "RECIPE_CRAFTING",
        TARGETED_CRAFTING = "TARGETED_CRAFTING",
        DISENCHANT = "DISENCHANT",
        NODE_GATHERING = "NODE_GATHERING",
        AREA_GATHERING = "AREA_GATHERING",
        FISHING_AREA = "FISHING_AREA",
    },
    STRATEGIES = {
        FASTEST = "fastest",
        ECONOMICAL = "economical",
        SELF_FOUND = "self_found",
    },
    SHOPPING_SCOPES = {
        CURRENT = "current",
        NEXT_TRAINER = "next_trainer",
        TO_300 = "to_300",
    },
    EVIDENCE = {
        FOREVER_VERIFIED = "forever-verified",
        CLASSIC_CONTINUITY = "classic-continuity",
        PROVISIONAL = "provisional",
        USER_RESEARCH_HORDE_V1 = "user-research-horde-v1",
    },
}
