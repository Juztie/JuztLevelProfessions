local _, JLP = ...

-- WoW Forever Tailoring route for target client build 1.60.1.70009.
-- The route stores explicit skill windows, expected craft counts, trainer gates,
-- material item IDs and source classes so inventory/AH logic can operate on it.
local MATERIALS = {
    LINEN_CLOTH          = { itemID = 2589,  name = "Linen Cloth", source = "auction" },
    BOLT_LINEN           = { itemID = 2996,  name = "Bolt of Linen Cloth", source = "crafted", craftedFrom = { itemID = 2589, quantity = 2 } },
    COARSE_THREAD        = { itemID = 2320,  name = "Coarse Thread", source = "vendor" },
    FINE_THREAD          = { itemID = 2321,  name = "Fine Thread", source = "vendor" },
    WOOL_CLOTH           = { itemID = 2592,  name = "Wool Cloth", source = "auction" },
    BOLT_WOOL            = { itemID = 2997,  name = "Bolt of Woolen Cloth", source = "crafted", craftedFrom = { itemID = 2592, quantity = 3 } },
    GREEN_DYE            = { itemID = 2605,  name = "Green Dye", source = "vendor" },
    SILK_CLOTH           = { itemID = 4306,  name = "Silk Cloth", source = "auction" },
    BOLT_SILK            = { itemID = 4305,  name = "Bolt of Silk Cloth", source = "crafted", craftedFrom = { itemID = 4306, quantity = 4 } },
    ELIXIR_WISDOM        = { itemID = 3383,  name = "Elixir of Wisdom", source = "auction" },
    BLEACH               = { itemID = 2324,  name = "Bleach", source = "vendor" },
    HEAVY_LEATHER        = { itemID = 4234,  name = "Heavy Leather", source = "auction" },
    BLUE_DYE             = { itemID = 6260,  name = "Blue Dye", source = "vendor" },
    RED_DYE              = { itemID = 2604,  name = "Red Dye", source = "vendor" },
    SILKEN_THREAD        = { itemID = 4291,  name = "Silken Thread", source = "vendor" },
    MAGEWEAVE_CLOTH      = { itemID = 4338,  name = "Mageweave Cloth", source = "auction" },
    BOLT_MAGEWEAVE       = { itemID = 4339,  name = "Bolt of Mageweave", source = "crafted", craftedFrom = { itemID = 4338, quantity = 5 } },
    HEAVY_SILKEN_THREAD  = { itemID = 8343,  name = "Heavy Silken Thread", source = "vendor" },
    RUNECLOTH            = { itemID = 14047, name = "Runecloth", source = "auction" },
    BOLT_RUNECLOTH       = { itemID = 14048, name = "Bolt of Runecloth", source = "crafted", craftedFrom = { itemID = 14047, quantity = 5 } },
    RUNE_THREAD          = { itemID = 14341, name = "Rune Thread", source = "vendor" },
    GOLD_BAR             = { itemID = 3577,  name = "Gold Bar", source = "auction" },
    IRONWEB_SPIDER_SILK  = { itemID = 14227, name = "Ironweb Spider Silk", source = "auction" },
    FELCLOTH             = { itemID = 14256, name = "Felcloth", source = "auction" },
    MOONCLOTH            = { itemID = 14342, name = "Mooncloth", source = "crafted", craftedFrom = { itemID = 14256, quantity = 2 } },
    GOLDEN_PEARL         = { itemID = 13926, name = "Golden Pearl", source = "auction" },
}

local ITEM_NAME_BY_ID = {}
for _, material in pairs(MATERIALS) do
    ITEM_NAME_BY_ID[material.itemID] = material.name
end

local function mat(key, quantity)
    local base = MATERIALS[key]
    local craftedFrom = nil
    if base.craftedFrom then
        craftedFrom = {
            itemID = base.craftedFrom.itemID,
            quantity = base.craftedFrom.quantity,
            name = ITEM_NAME_BY_ID[base.craftedFrom.itemID],
        }
    end
    return {
        itemID = base.itemID,
        name = base.name,
        quantity = quantity,
        source = base.source,
        craftedFrom = craftedFrom,
    }
end


-- Alpha97 staged recipe identities.  These spell/recipe IDs were cross-checked
-- against the public Wowhead Forever database on 2026-10-06.  The external
-- reference is not treated as build-pinned native authority: guarded execution
-- must still corroborate the exact ID/name against the live 1.60.1.70009
-- profession window before a craft can become eligible.
local RECIPE_IDENTITIES = {
    ["Bolt of Linen Cloth"]              = { recipeID=2963,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=2963/bolt-of-linen-cloth" },
    ["Simple Linen Pants"]               = { recipeID=12044, source="wowhead-forever", url="https://www.wowhead.com/forever/spell=12044/simple-linen-pants" },
    ["Linen Belt"]                       = { recipeID=8776,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=8776/linen-belt" },
    ["Simple Kilt"]                      = { recipeID=12046, source="wowhead-forever", url="https://www.wowhead.com/forever/spell=12046/simple-kilt" },
    ["Woolen Cape"]                      = { recipeID=2402,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=2402/woolen-cape" },
    ["Green Woolen Vest"]                = { recipeID=2399,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=2399/green-woolen-vest" },
    ["Double-stitched Woolen Shoulders"] = { recipeID=3848,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=3848/double-stitched-woolen-shoulders" },
    ["Silk Headband"]                    = { recipeID=8762,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=8762/silk-headband" },
    ["Gloves of Meditation"]             = { recipeID=3852,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=3852/gloves-of-meditation" },
    ["Formal White Shirt"]               = { recipeID=3871,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=3871/formal-white-shirt" },
    ["Small Silk Pack"]                  = { recipeID=3813,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=3813/small-silk-pack" },
    ["Azure Silk Cloak"]                 = { recipeID=8786,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=8786/azure-silk-cloak" },
    ["Crimson Silk Vest"]                = { recipeID=8791,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=8791/crimson-silk-vest" },
    ["Crimson Silk Pantaloons"]          = { recipeID=8799,  source="wowhead-forever", url="https://www.wowhead.com/forever/spell=8799/crimson-silk-pantaloons" },
    ["Black Mageweave Gloves"]           = { recipeID=12053, source="wowhead-forever", url="https://www.wowhead.com/forever/spell=12053/black-mageweave-gloves" },
    ["Black Mageweave Headband"]         = { recipeID=12072, source="wowhead-forever", url="https://www.wowhead.com/forever/spell=12072/black-mageweave-headband" },
    ["Runecloth Belt"]                   = { recipeID=18402, source="wowhead-forever", url="https://www.wowhead.com/forever/spell=18402/runecloth-belt" },
    ["Brightcloth Cloak"]                = { recipeID=18420, source="wowhead-forever", url="https://www.wowhead.com/forever/spell=18420/brightcloth-cloak" },
    ["Runecloth Pants"]                  = { recipeID=18438, source="wowhead-forever", url="https://www.wowhead.com/forever/spell=18438/runecloth-pants" },
    ["Mooncloth"]                        = { recipeID=18560, source="wowhead-forever", url="https://www.wowhead.com/forever/spell=18560/mooncloth" },
    ["Mooncloth Robe"]                   = { recipeID=22902, source="wowhead-forever", url="https://www.wowhead.com/forever/spell=22902/mooncloth-robe" },
}

local RECIPE_IDENTITY_EVIDENCE = {
    contract = "forever-tailoring-recipe-identity-reference-v1",
    source = "wowhead-forever",
    capturedAt = "2026-10-06",
    capturedAgainstPatch = "1.60.1",
    capturedAgainstBuild = 70009,
    buildPinned = false,
    liveCurrentBuildCorroborationRequired = true,
}

local ROUTE = {
    -- P0.2B: field-scoped 70450 / Forever evidence for the EXISTING 1-31 step.
    -- The historical 31 crafts is NOT a 70450-verified skill-up prediction.
    -- DB2 MinSkillLineRank=1 is raw reference ONLY; actual recipe minimum 1
    -- is attested separately by the Forever recipe page (not build-pinned).
    { skillMin=1,   skillTarget=31,  recipe="Bolt of Linen Cloth",              expectedCrafts=31,
      materials={mat("LINEN_CLOTH",2)}, evidence="forever-beta-70009",
      requiredSkill=1,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=2963/bolt-of-linen-cloth",
      rawYellowThreshold=25,rawGreyThreshold=50,
      rawDifficultySourceBuild=70450,
      recipeSource="trainer",recipeSourceEvidence="HISTORICAL_TRAINER_ROUTE_CLASS_UNVERIFIED",
      recipeLearnSourceEvidence="WOWHEAD_FOREVER_TRAINING_OVERVIEW_VS_QUESTING_WIKI_LEARNED_WITH_PROFESSION",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=2996,outputQuantityReference=2,
      outputQuantityEvidence="WOWHEAD_FOREVER_EXTERNAL_REFERENCE_UNPINNED",
      outputQuantityConflictingReference=1,
      outputQuantityConflictEvidence="QUESTING_WIKI_WOW_FOREVER_UNPINNED",
      outputQuantityConflictSourceURL="https://questing.wiki/wow-forever/professions/tailoring/",
      outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=25,craftEstimateGapToSkill=31,
      sourceQualificationContract="tailoring-bolt-linen-field-evidence-p02b-v1" },
    -- P0.2C: field-scoped evidence for the EXISTING 31-50 segment, not a new route.
    -- Build70450 proves reagent IDs/counts, output-item identity and raw trivial
    -- ranks only. The minimum is independently sourced to Wowhead Forever.
    -- External yellow/yield/learning references conflict; 23 crafts remains a
    -- 70009 advisory estimate, never a qualified 70450 skill-up forecast.
    { skillMin=31,  skillTarget=50,  recipe="Simple Linen Pants",               expectedCrafts=23,
      materials={mat("BOLT_LINEN",1),mat("COARSE_THREAD",1)},evidence="forever-beta-70009",
      requiredSkill=1,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=12044/simple-linen-pants",
      rawYellowThreshold=40,rawGreyThreshold=60,rawDifficultySourceBuild=70450,
      externalDifficultyReference="WOWHEAD_FOREVER_1_40_50_60",
      externalDifficultyConflictReference="QUESTING_WIKI_1_20_40_60",
      recipeSource="trainer",recipeSourceEvidence="HISTORICAL_TRAINER_ROUTE_CLASS_UNVERIFIED",
      recipeLearnSourceEvidence="HISTORICAL_TRAINER_VS_QUESTING_WIKI_WITH_PROFESSION",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=10045,outputQuantityReference=2,
      outputQuantityEvidence="WOWHEAD_FOREVER_EXTERNAL_REFERENCE_UNPINNED",
      outputQuantityConflictingReference=1,
      outputQuantityConflictEvidence="QUESTING_WIKI_WOW_FOREVER_UNPINNED",
      outputQuantityConflictSourceURL="https://questing.wiki/wow-forever/professions/tailoring/",
      outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=40,craftEstimateGapToSkill=50,
      sourceQualificationContract="tailoring-simple-linen-pants-field-evidence-p02c-v1" },
    -- P0.2D: DB70450 documents SpellID, reagent IDs/counts, output-item ID
    -- and raw trivials (50/85). Public Wowhead Forever tailoring overview
    -- separately lists 15 as learning minimum; this is NOT DB2 minrank.
    -- Other unpinned catalogues differ about output (2 vs 1); leave live
    -- yield and learned-state unknown. 51 crafts is historical 70009 only.
    { skillMin=50, skillTarget=77, recipe="Linen Belt", expectedCrafts=51,
      materials={mat("BOLT_LINEN",1),mat("COARSE_THREAD",1)},evidence="forever-beta-70009",
      requiredSkill=15,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
      rawYellowThreshold=50,rawGreyThreshold=85,rawDifficultySourceBuild=70450,
      externalDifficultyReference="WOWFOREVERTALENTS_ORANGE_TO_49_YELLOW_50_GREEN_68_GREY_85",
      externalDifficultyConflictReference="CLASSIC_15_50_67_85_GREEN_BOUNDARY",
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_OVERVIEW_TRAINER_EXTERNAL_UNPINNED",
      recipeLearnSourceEvidence="WOWHEAD_FOREVER_OVERVIEW_VS_QUESTING_WIKI_SKILL_UNCONFIRMED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=7026,outputQuantityReference=2,
      outputQuantityEvidence="WOWHEAD_FOREVER_EXTERNAL_REFERENCE_UNPINNED",
      outputQuantityConflictingReference=1,
      outputQuantityConflictEvidence="QUESTING_WIKI_AND_WOWFOREVERTALENTS_UNPINNED",
      outputQuantityConflictSourceURL="https://questing.wiki/wow-forever/professions/tailoring/",
      outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=50,craftEstimateGapToSkill=77,
      sourceQualificationContract="tailoring-linen-belt-field-evidence-p02d-v1" },
    -- P0.2E: 70450 verifies SPELL 12046, two direct reagents and output item;
    -- Wowhead Forever overview separately lists skill 75 (not raw minrank=1).
    -- The raw 70450 trivial fields are 75/110, NOT four complete difficulty
    -- boundaries. Classic-era 75/100/117/135 is a cross-build comparison ONLY.
    -- 48 crafts remains a build-70009 historical advisory, NOT live skillrate.
    { skillMin=77, skillTarget=102, recipe="Simple Kilt", expectedCrafts=48,
      materials={mat("BOLT_LINEN",4),mat("FINE_THREAD",1)},evidence="forever-beta-70009",
      requiredSkill=75,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
      rawYellowThreshold=75,rawGreyThreshold=110,rawDifficultySourceBuild=70450,
      externalDifficultyReference="CLASSIC_75_100_117_135_CROSS_BUILD_NOT_FOREVER_AUTHORITY",
      recipeSource="trainer",recipeSourceEvidence="HISTORICAL_TRAINER_ROUTE_CLASS_UNVERIFIED",
      recipeLearnSourceEvidence="WOWHEAD_FOREVER_OVERVIEW_SKILL_75_VS_QUESTING_WIKI_LEARNING_SKILL_UNRECORDED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=10047,outputQuantityReference=2,
      outputQuantityEvidence="WOWHEAD_FOREVER_EXTERNAL_REFERENCE_UNPINNED",
      outputQuantityConflictingReference=1,
      outputQuantityConflictEvidence="QUESTING_WIKI_WOW_FOREVER_UNPINNED",
      outputQuantityConflictSourceURL="https://questing.wiki/wow-forever/professions/tailoring/",
      outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=77,craftEstimateGapToSkill=102,
      sourceQualificationContract="tailoring-simple-kilt-field-evidence-p02e-v1" },
    -- P0.2F: DB_70450 validates spell/reagent/output item and raw trivial
    -- 80/115; raw MinSkillLineRank=1 is NOT proof of the learning minimum.
    -- Wowhead Forever Tailoring Overview separately lists minimum 75 and its
    -- spell reference lists trainers/yield 2. Questing.wiki lists output 1,
    -- but its learn requirement is unconfirmed. Nothing is live-observed.
    -- 17 crafts remains advisory build-70009 and cannot prove skill-up rates.
    { skillMin=102, skillTarget=107, recipe="Woolen Cape", expectedCrafts=17,
      materials={mat("BOLT_WOOL",1),mat("FINE_THREAD",1)},evidence="forever-beta-70009",
      requiredSkill=75,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
      rawYellowThreshold=80,rawGreyThreshold=115,rawDifficultySourceBuild=70450,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_TAUGHT_BY_EXTERNAL_UNPINNED",
      recipeLearnSourceEvidence="WOWHEAD_FOREVER_TAUGHT_BY_VS_QUESTING_WIKI_LEARNING_UNCONFIRMED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=2584,outputQuantityReference=2,
      outputQuantityEvidence="WOWHEAD_FOREVER_EXTERNAL_REFERENCE_UNPINNED",
      outputQuantityConflictingReference=1,
      outputQuantityConflictEvidence="QUESTING_WIKI_WOW_FOREVER_UNPINNED",
      outputQuantityConflictSourceURL="https://questing.wiki/wow-forever/professions/tailoring/",
      outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=102,craftEstimateGapToSkill=107,
      sourceQualificationContract="tailoring-woolen-cape-field-evidence-p02f-v1" },
    -- P0.2G: DB70450 confirms spell 2399, three direct reagents, output item
    -- and raw 85/120 trivial cutoffs, NOT actual learn minimum or full colors.
    -- Independent Forever spell/overview references list minimum 85 and trainer;
    -- neither proves this character has learned it. Unpinned catalogues differ
    -- about yield 2/1. Nine crafts are only the historical 70009 route estimate.
    { skillMin=107, skillTarget=110, recipe="Green Woolen Vest", expectedCrafts=9,
      materials={mat("BOLT_WOOL",2),mat("FINE_THREAD",2),mat("GREEN_DYE",1)},evidence="forever-beta-70009",
      requiredSkill=85,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=2399/green-woolen-vest",
      rawYellowThreshold=85,rawGreyThreshold=120,rawDifficultySourceBuild=70450,
      externalDifficultyReference="WOWHEAD_FOREVER_85_85_102_120_EXTERNAL_UNPINNED",
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_TAUGHT_BY_EXTERNAL_UNPINNED",
      recipeLearnSourceEvidence="WOWHEAD_FOREVER_TRAINER_VS_QUESTING_WIKI_LEARNING_UNRECORDED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=2582,outputQuantityReference=2,
      outputQuantityEvidence="WOWHEAD_FOREVER_EXTERNAL_REFERENCE_UNPINNED",
      outputQuantityConflictingReference=1,
      outputQuantityConflictEvidence="QUESTING_WIKI_WOW_FOREVER_UNPINNED",
      outputQuantityConflictSourceURL="https://questing.wiki/wow-forever/professions/tailoring/",
      outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=107,craftEstimateGapToSkill=110,
      sourceQualificationContract="tailoring-green-woolen-vest-field-evidence-p02g-v1" },
    -- P0.2H: DB70450 confirms SpellID 3848, direct reagents, output item
    -- and raw trivials 110/145; raw MinSkillLineRank=1 does NOT mean recipe
    -- learning minimum. Forever Tailoring Overview independently states 110.
    -- External sources report yield 2 vs 1. Neither live output, trainer
    -- access nor skill-up rate is observed. 51 crafts remains build70009 only.
    { skillMin=110, skillTarget=137, recipe="Double-stitched Woolen Shoulders", expectedCrafts=51,
      materials={mat("BOLT_WOOL",3),mat("FINE_THREAD",2)},evidence="forever-beta-70009",
      requiredSkill=110,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
      rawYellowThreshold=110,rawGreyThreshold=145,rawDifficultySourceBuild=70450,
      externalDifficultyReference="WOWHEAD_CLASSIC_110_135_152_170_CROSS_BUILD_ONLY",
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_TAUGHT_BY_EXTERNAL_UNPINNED",
      recipeLearnSourceEvidence="WOWHEAD_FOREVER_TRAINER_VS_QUESTING_WIKI_LEARNING_UNRECORDED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=4314,outputQuantityReference=2,
      outputQuantityEvidence="WOWHEAD_FOREVER_EXTERNAL_REFERENCE_UNPINNED",
      outputQuantityConflictingReference=1,
      outputQuantityConflictEvidence="QUESTING_WIKI_WOW_FOREVER_UNPINNED",
      outputQuantityConflictSourceURL="https://questing.wiki/wow-forever/professions/tailoring/",
      outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=110,craftEstimateGapToSkill=137,
      sourceQualificationContract="tailoring-double-stitched-woolen-shoulders-field-evidence-p02h-v1" },
    -- P0.2I: source conflict is a REAL 137-143 route-eligibility gap, not a
    -- missing recipe. The Forever Wowhead spell/overview says learn minimum 160,
    -- while CURRENT source DB70450 trivial fields are only 135/145. The latter
    -- are not a minimum and cannot prove accessibility at 137. Never bypass the
    -- existing RecipeDifficulty gate; keep the 70009 13 crafts advisory only.
    { skillMin=137, skillTarget=143, recipe="Silk Headband", expectedCrafts=13,
      materials={mat("BOLT_SILK",3),mat("FINE_THREAD",2)},evidence="forever-beta-70009",
      requiredSkill=160,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=8762/silk-headband",
      rawYellowThreshold=135,rawGreyThreshold=145,rawDifficultySourceBuild=70450,
      minimumSkillVsRawDifficultyConflict="WOWHEAD_FOREVER_160_VS_DB70450_TRIVIAL_135_145",
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_TAUGHT_BY_EXTERNAL_UNPINNED",
      recipeLearnSourceEvidence="WOWHEAD_FOREVER_160_VS_QUESTING_WIKI_NOT_RECORDED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=7050,outputQuantityReference=2,
      outputQuantityEvidence="WOWHEAD_FOREVER_EXTERNAL_REFERENCE_UNPINNED",
      outputQuantityConflictingReference=1,
      outputQuantityConflictEvidence="QUESTING_WIKI_WOW_FOREVER_UNPINNED",
      outputQuantityConflictSourceURL="https://questing.wiki/wow-forever/professions/tailoring/",
      outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=137,craftEstimateGapToSkill=143,
      -- P0.2J: SOURCE-BACKED INVESTIGATION CANDIDATE, NOT active 137-143 route.
      -- The previous 13 expected crafts belong ONLY to Silk Headband 70009.
      -- DB70450 raw 125/155 are difficulty bounds, not a recipe minimum;
      -- Wowhead Forever separately lists 130 for this recipe.  No 137-143
      -- craft count, player learned-state, server skill-up or trainer access
      -- has been independently observed.  Keep the actual route in VERIFY.
      gapResolutionCandidate={
          recipe="Gloves of Meditation",recipeID=3852,
          fromSkill=137,toSkill=143,
          requiredSkill=130,requiredSkillAuthority="WOWHEAD_FOREVER",
          requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
          rawYellowThreshold=125,rawGreyThreshold=155,rawDifficultySourceBuild=70450,
          materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
          materials={mat("BOLT_WOOL",4),mat("FINE_THREAD",3),mat("ELIXIR_WISDOM",1)},
          outputItemID=4318,outputYieldLiveVerified=false,
          recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_AND_FOREVER_ERA_EXTERNAL_UNPINNED",
          recipeAccessObserved=false,learnedState="NOT_OBSERVED",
          expectedCrafts=nil,craftCountQualified=false,craftCountAuthority="NO_137_143_CRAFT_RATE_EVIDENCE",
          advisoryOnly=true,routeQualified=false,plannerEligible=false,
          nativeDispatchAllowed=false,executionEligible=false,
          sourceQualificationContract="tailoring-137-143-gloves-verification-candidate-p02j-v1",
      },
      sourceQualificationContract="tailoring-silk-headband-field-evidence-p02i-v1" },
    -- P0.2L: same spell as the verified-reference candidate in 137-143.
    -- Historical 70009 SIX crafts here are not a 70450 skill-up observation.
    -- Required skill (external) and raw difficulties (DB70450) are independent
    -- of live learned/trainer state and craft-rate.  This step is a VERIFY
    -- reference until recipe-access + progression evidence exists; no shopping.
    { skillMin=143, skillTarget=145, recipe="Gloves of Meditation", expectedCrafts=6,
      materials={mat("BOLT_WOOL",4),mat("FINE_THREAD",3),mat("ELIXIR_WISDOM",1)},evidence="forever-beta-70009",
      requiredSkill=130,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
      rawYellowThreshold=125,rawGreyThreshold=155,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=4318,outputYieldLiveVerified=false,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_AND_FOREVER_ERA_EXTERNAL_UNPINNED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=143,craftEstimateGapToSkill=145,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-143-145-gloves-evidence-p02l-v1" },
    -- P0.2M: client build 70450 records the 145/155 raw difficulty bounds,
    -- not recipe learning minimum. Wowhead Forever lists 170 (un-pinned);
    -- ForeverDB 70425 lists 145, contrary to the overview. Preserve both
    -- references separately: neither is actual current-trainer/learned state.
    -- Skill 145-153 requires VERIFY, never historical 15-craft shopping.
    { skillMin=145, skillTarget=153, recipe="Formal White Shirt", expectedCrafts=15,
      materials={mat("BOLT_SILK",3),mat("BLEACH",2),mat("FINE_THREAD",1)},evidence="forever-beta-70009",
      requiredSkill=170,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
      minimumSkillVsRawDifficultyConflict="WOWHEAD_FOREVER_170_VS_DB70450_145_155_VS_FOREVERDB70425_145",
      conflictingMinimumSkillReference=145,conflictingMinimumSkillSourceBuild=70425,
      conflictingMinimumSkillSourceURL="https://www.foreverdb.app/en/forever/spells/3871/formal-white-shirt",
      rawYellowThreshold=145,rawGreyThreshold=155,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=4334,outputQuantityReference=2,
      outputQuantityEvidence="WOWHEAD_FOREVER_EXTERNAL_REFERENCE_UNPINNED",
      outputQuantityConflictingReference=1,
      outputQuantityConflictEvidence="WOWFOREVERTALENTS_70450_REFERENCE_NOT_LIVE",
      outputYieldLiveVerified=false,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_AND_WOWFOREVERTALENTS_EXTERNAL_UNPINNED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=145,craftEstimateGapToSkill=153,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-145-153-formal-white-shirt-evidence-p02m-v1" },
    -- P0.2N: 70450 verifies identity, 4305x3/4234x2/2321x3, item 4245,
    -- and RAW difficulty 145/175, NOT live learning/skill-up probability.
    -- Wowhead Forever overview gives an external learn minimum 150; the
    -- 70450-based bag catalogue says the trainer minimum is NOT in the client
    -- tables.  Beta report: becomes yellow at 145 (difficulty reference,
    -- not trainer access or a qualified number of crafts).  Classic values
    -- 150/170/185/200 are cross-build ONLY.  Twelve crafts are from 70009.
    { skillMin=153, skillTarget=160, recipe="Small Silk Pack", expectedCrafts=12,
      materials={mat("BOLT_SILK",3),mat("HEAVY_LEATHER",2),mat("FINE_THREAD",3)}, evidence="forever-beta-70009",
      requiredSkill=150,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
      rawYellowThreshold=145,rawGreyThreshold=175,rawDifficultySourceBuild=70450,
      externalDifficultyReference="WOWHEAD_FOREVER_BETA_YELLOW_145_UNPINNED",
      classicDifficultyReference="WOWHEAD_CLASSIC_150_170_185_200_CROSS_BUILD_ONLY",
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_AND_70450_BAGS_EXTERNAL_NOT_CLIENT_OBSERVED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=4245,outputQuantityReference=2,
      outputQuantityEvidence="WOWHEAD_FOREVER_EXTERNAL_REFERENCE_UNPINNED",
      outputQuantityConflictingReference=1,
      outputQuantityConflictEvidence="WOWFOREVERTALENTS_70450_REFERENCE_NOT_LIVE",
      outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=153,craftEstimateGapToSkill=160,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-153-160-small-silk-pack-evidence-p02n-v1" },
    -- P0.2O: DB70450 attests SpellID 8786, reagent IDs/quantities, output
    -- item 7053 and raw triviality 160/190. MinSkillLineRank=1 is NOT a
    -- learning minimum. Forever spell 8786 lists min 175; Forever pattern
    -- 7089 lists 140 to use the item: different claims, neither live proof.
    -- Historical 12 crafts (70009) and vendor stock are UNVERIFIED.
    { skillMin=160, skillTarget=170, recipe="Azure Silk Cloak", expectedCrafts=12,
      materials={mat("BOLT_SILK",3),mat("BLUE_DYE",2),mat("FINE_THREAD",2)},
      recipeSource="vendor-pattern",sourceRequirement={kind="pattern",name="Azure Silk Cloak",
        itemID=7089,evidence="WOWHEAD_FOREVER_ITEM_EXTERNAL_UNPINNED"},
      evidence="forever-beta-70009",requiredSkill=175,
      requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=8786/azure-silk-cloak",
      patternItemRequirementReference=140,
      patternItemRequirementAuthority="WOWHEAD_FOREVER_ITEM_EXTERNAL_UNPINNED",
      patternItemRequirementSourceURL="https://www.wowhead.com/forever/item=7089/pattern-azure-silk-cloak",
      minimumSkillVsRawDifficultyConflict="FOREVER_SPELL_175_VS_DB70450_TRIVIAL_160_190_VS_PATTERN_ITEM_140",
      rawYellowThreshold=160,rawGreyThreshold=190,rawDifficultySourceBuild=70450,
      recipeSourceEvidence="WOWHEAD_FOREVER_VENDOR_PATTERN_UNPINNED",
      recipeLearnSourceEvidence="WOWHEAD_FOREVER_SPELL_175_VS_PATTERN_ITEM_140_NOT_LIVE",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=7053,outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=160,craftEstimateGapToSkill=170,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-160-170-azure-silk-cloak-evidence-p02o-v1" },
    -- P0.2P: sourcebuild70450 identifies SpellID 8791, reagents 4305x4,
    -- 2604x2, 2321x2, output ItemID 7058 and raw difficulty 170/190.
    -- MinSkillLineRank=1 is NOT a learning minimum. Unpinned Forever Wowhead
    -- overview lists 185; 70425 ForeverDB separately lists 170. Neither
    -- proves live trainer/learned state. Historical 70009 14-craft count
    -- must not become a qualified craft/material budget or skill-up claim.
    { skillMin=170, skillTarget=180, recipe="Crimson Silk Vest",expectedCrafts=14,
      materials={mat("BOLT_SILK",4),mat("RED_DYE",2),mat("FINE_THREAD",2)},
      evidence="forever-beta-70009",requiredSkill=185,
      requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
      conflictingMinimumSkillReference=170,conflictingMinimumSkillSourceBuild=70425,
      conflictingMinimumSkillSourceURL="https://www.foreverdb.app/en/forever/spells/8791/crimson-silk-vest",
      minimumSkillVsRawDifficultyConflict="WOWHEAD_FOREVER_185_VS_FOREVERDB70425_170_VS_DB70450_TRIVIAL_170_190",
      rawYellowThreshold=170,rawGreyThreshold=190,rawDifficultySourceBuild=70450,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_TAUGHT_BY_EXTERNAL_UNPINNED",
      recipeLearnSourceEvidence="FOREVERDB70425_170_VS_WOWHEAD_FOREVER_185_NOT_LIVE",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=7058,outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=170,craftEstimateGapToSkill=180,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-170-180-crimson-silk-vest-evidence-p02p-v1" },
    -- P0.2Q: DB70450 links SpellID 8799 to Tailoring197, reagents 4305x4,
    -- 2604x2,4291x2, output ItemID7062 and raw difficulty 180/200.
    -- ForeverDB70425 reports minimum 180; unpinned Wowhead Forever spell
    -- reports 195. Neither supplies live client access/knowledge, skill-ups,
    -- yield or 27 historical 70009 craft estimates. Scope is ONLY 180-190;
    -- the historical next-interval 190-195 portion is preserved as a separate
    -- unqualified reference, NOT reclassified as build70450 fact.
    { skillMin=180, skillTarget=190, recipe="Crimson Silk Pantaloons",expectedCrafts=27,
      materials={mat("BOLT_SILK",4),mat("RED_DYE",2),mat("SILKEN_THREAD",2)},
      evidence="forever-beta-70009",requiredSkill=195,
      requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=8799/crimson-silk-pantaloons",
      conflictingMinimumSkillReference=180,conflictingMinimumSkillSourceBuild=70425,
      conflictingMinimumSkillSourceURL="https://www.foreverdb.app/en/forever/spells/8799/crimson-silk-pantaloons",
      minimumSkillVsRawDifficultyConflict="WOWHEAD_FOREVER_195_VS_FOREVERDB70425_180_VS_DB70450_TRIVIAL_180_200",
      rawYellowThreshold=180,rawGreyThreshold=200,rawDifficultySourceBuild=70450,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_TAUGHT_BY_EXTERNAL_UNPINNED",
      recipeLearnSourceEvidence="FOREVERDB70425_180_VS_WOWHEAD_FOREVER_195_NOT_LIVE",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=7062,outputYieldLiveVerified=false,
      craftCountAuthority="HISTORICAL_70009_ESTIMATE",craftCountQualified=false,
      craftEstimateGapFromSkill=180,craftEstimateGapToSkill=190,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-180-190-crimson-silk-pantaloons-evidence-p02q-v1" },
    -- P0.2R: DB70450 links Spell8799 to Tailoring197, raw triviality
    -- low180/high200, exact reagents 4305x4/2604x2/4291x2 and output7062.
    -- External ForeverDB70425 minimum180 and Wowhead Forever minimum195
    -- conflict; neither establishes actual 70450 character learned-state.
    -- The former historical 27 crafts is NOT a qualified 190-195 forecast.
    { skillMin=190, skillTarget=195, recipe="Crimson Silk Pantaloons",expectedCrafts=27,
      materials={mat("BOLT_SILK",4),mat("RED_DYE",2),mat("SILKEN_THREAD",2)},
      evidence="forever-beta-70009",requiredSkill=195,
      requiredSkillAuthority="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=8799/crimson-silk-pantaloons",
      conflictingMinimumSkillReference=180,conflictingMinimumSkillSourceBuild=70425,
      rawYellowThreshold=180,rawGreyThreshold=200,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=7062,outputYieldLiveVerified=false,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=190,craftEstimateGapToSkill=195,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-190-195-crimson-silk-pantaloons-evidence-p02r-v1" },
    -- P0.2R: DB70450 Spell12053 raw triviality195/225, reagents4339x2
    -- and 8343x2, output item10003. Wowhead Forever lists learn min215.
    -- Neither raw195 nor 12 historical crafts proves access at195.
    { skillMin=195, skillTarget=200, recipe="Black Mageweave Gloves",expectedCrafts=12,
      materials={mat("BOLT_MAGEWEAVE",2),mat("HEAVY_SILKEN_THREAD",2)},
      evidence="forever-beta-70009",requiredSkill=215,
      requiredSkillAuthority="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=12053/black-mageweave-gloves",
      rawYellowThreshold=195,rawGreyThreshold=225,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=10003,outputYieldLiveVerified=false,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=195,craftEstimateGapToSkill=200,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-195-200-black-mageweave-gloves-evidence-p02r-v1" },
    -- P0.2S: DB70450 Spell12053 SkillLine197; low195/high225 are raw
    -- triviality, NOT a learn minimum. External Wowhead Forever says 215.
    -- Historical 12 crafts carry no progression/material/rate authority.
    { skillMin=200, skillTarget=205, recipe="Black Mageweave Gloves",expectedCrafts=12,
      materials={mat("BOLT_MAGEWEAVE",2),mat("HEAVY_SILKEN_THREAD",2)},
      evidence="forever-beta-70009",requiredSkill=215,
      requiredSkillAuthority="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=12053/black-mageweave-gloves",
      rawYellowThreshold=195,rawGreyThreshold=225,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=10003,outputYieldLiveVerified=false,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=200,craftEstimateGapToSkill=205,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-200-205-black-mageweave-gloves-evidence-p02s-v1" },
    -- P0.2S: DB70450 Spell12072 SkillLine197, reagents4339x3 / 8343x2,
    -- output item10024 and raw triviality205/235. Wowhead Forever reports
    -- minimum230 (external, unpinned); real client access/yield unknown.
    -- The former 205-225 historical 32 crafts are not a qualified 205-210 rate.
    { skillMin=205, skillTarget=210, recipe="Black Mageweave Headband",expectedCrafts=32,
      materials={mat("BOLT_MAGEWEAVE",3),mat("HEAVY_SILKEN_THREAD",2)},
      evidence="forever-beta-70009",requiredSkill=230,
      requiredSkillAuthority="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=12072/black-mageweave-headband",
      rawYellowThreshold=205,rawGreyThreshold=235,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=10024,outputYieldLiveVerified=false,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=205,craftEstimateGapToSkill=210,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-205-210-black-mageweave-headband-evidence-p02s-v1" },
    -- P0.2T: sourcebuild 1.60.1.70450 Spell12072 Tailoring197, raw
    -- low205/high235, reagents4339x3/8343x2 and output item10024.
    -- Raw difficulty/MinSkillLineRank=1 cannot prove recipe learning.
    -- External unpinned Forever minimum230 is NOT live character access.
    -- Historical 32-craft count does not authorize bulk/material/rate budgets.
    { skillMin=210, skillTarget=220, recipe="Black Mageweave Headband",expectedCrafts=32,
      materials={mat("BOLT_MAGEWEAVE",3),mat("HEAVY_SILKEN_THREAD",2)},
      evidence="forever-beta-70009",requiredSkill=230,
      requiredSkillAuthority="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=12072/black-mageweave-headband",
      rawYellowThreshold=205,rawGreyThreshold=235,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=10024,outputYieldLiveVerified=false,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=210,craftEstimateGapToSkill=220,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-210-220-black-mageweave-headband-evidence-p02t-v1" },
    -- P0.2U: sourcebuild 1.60.1.70450 Spell12072 Tailoring197, raw
    -- low205/high235, SpellReagents4339x3+8343x2, SpellEffect item10024.
    -- Historical 32 crafts and unpinned external min230 are NOT live access.
    { skillMin=220, skillTarget=225, recipe="Black Mageweave Headband",expectedCrafts=32,
      materials={mat("BOLT_MAGEWEAVE",3),mat("HEAVY_SILKEN_THREAD",2)},
      evidence="forever-beta-70009",requiredSkill=230,
      requiredSkillAuthority="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=12072/black-mageweave-headband",
      rawYellowThreshold=205,rawGreyThreshold=235,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=10024,outputYieldLiveVerified=false,
      recipeSource="trainer",recipeSourceEvidence="WOWHEAD_FOREVER_EXTERNAL_UNPINNED",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=220,craftEstimateGapToSkill=225,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-220-225-black-mageweave-headband-evidence-p02u-v1" },
    -- P0.2U: Spell18402 Runecloth Belt, Tailoring197; DB raw low225/high255,
    -- SpellReagents14048x3+14341x1, SpellEffect output13856.
    -- AcquireMethod0 and MinSkillLineRank1 do NOT establish trainer or actual
    -- learning minimum. 32 crafts (historical 225-245) not 225-230 budget.
    { skillMin=225, skillTarget=230, recipe="Runecloth Belt",expectedCrafts=32,
      materials={mat("BOLT_RUNECLOTH",3),mat("RUNE_THREAD",1)},
      evidence="forever-beta-70009",requiredSkillAuthority="NOT_VERIFIED_DB70450",
      rawYellowThreshold=225,rawGreyThreshold=255,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=13856,outputYieldLiveVerified=false,
      recipeSourceEvidence="DB70450_ACQUIRE_METHOD_ZERO_NOT_ACCESS_PROOF",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=225,craftEstimateGapToSkill=230,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-225-230-runecloth-belt-evidence-p02u-v1" },
    -- P0.2V: DB sourcebuild 1.60.1.70450 Spell18402 Tailoring197,
    -- raw difficulty low225/high255, reagents14048x3+14341x1,
    -- CreateItem output13856. DB AcquireMethod0 / MinSkillLineRank1
    -- do NOT establish learning minimum, trainer availability or yield.
    -- The historic 32 crafts were for 225-245, NOT a 230-240 budget.
    { skillMin=230, skillTarget=240, recipe="Runecloth Belt",expectedCrafts=32,
      materials={mat("BOLT_RUNECLOTH",3),mat("RUNE_THREAD",1)},
      evidence="forever-beta-70009",requiredSkillAuthority="NOT_VERIFIED_DB70450",
      rawYellowThreshold=225,rawGreyThreshold=255,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=13856,outputYieldLiveVerified=false,
      recipeSourceEvidence="DB70450_ACQUIRE_METHOD_ZERO_NOT_ACCESS_PROOF",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=230,craftEstimateGapToSkill=240,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-230-240-runecloth-belt-evidence-p02v-v1" },
    -- P0.2W: DB_70450 sourcebuild 1.60.1.70450 Spell18402 Tailoring197,
    -- raw triviality 225/255, reagent 14048x3 + 14341x1, CreateItem13856.
    -- Historical 32 crafts do not verify 240-245 rate, yield or learning.
    { skillMin=240, skillTarget=245, recipe="Runecloth Belt",expectedCrafts=32,
      materials={mat("BOLT_RUNECLOTH",3),mat("RUNE_THREAD",1)},
      evidence="forever-beta-70009",requiredSkillAuthority="NOT_VERIFIED_DB70450",
      rawYellowThreshold=225,rawGreyThreshold=255,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=13856,outputYieldLiveVerified=false,
      recipeSourceEvidence="DB70450_ACQUIRE_METHOD_ZERO_NOT_ACCESS_PROOF",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=240,craftEstimateGapToSkill=245,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-240-245-runecloth-belt-evidence-p02w-v1" },
    -- P0.2W: DB_70450 Spell18420 Tailoring197, raw245/275, reagents
    -- 14048x4 + 3577x2 + 14341x1, CreateItem output14103 (Effect24).
    -- ItemSparse14484 is Pattern: Brightcloth Cloak with RequiredSkillRank230;
    -- this is pattern-item metadata, NOT observed character learning, drop
    -- location, trainer access or guaranteed recipe minimum. 25 historical
    -- crafts belong to 245-262, NOT a qualified 245-250 progress budget.
    { skillMin=245, skillTarget=250, recipe="Brightcloth Cloak",expectedCrafts=25,
      materials={mat("BOLT_RUNECLOTH",4),mat("GOLD_BAR",2),mat("RUNE_THREAD",1)},
      evidence="forever-beta-70009",requiredSkillAuthority="NOT_VERIFIED_DB70450",
      rawYellowThreshold=245,rawGreyThreshold=275,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=14103,outputYieldLiveVerified=false,
      recipeSource="drop-pattern",recipeSourceEvidence="HISTORICAL_DROP_UNVERIFIED",
      sourceRequirement={kind="pattern",name="Brightcloth Cloak",itemID=14484,
          evidence="DB70450_ITEMSPARSE_ITEMXITEMEFFECT_LINK",itemRequiredSkillRank=230},
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=245,craftEstimateGapToSkill=250,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-245-250-brightcloth-cloak-evidence-p02w-v1" },
    -- P0.2X: DB70450 SPELL 18420 belongs to Tailoring197 with raw
    -- difficulty low245/high275, reagent 14048x4,3577x2,14341x1 and
    -- output ItemID14103. Item14484's RequiredSkillRank230 is the PATTERN
    -- ITEM requirement, not a verified spell-learning minimum. No live
    -- trainer/drop, character learning, yield or skill-up rate is observed.
    -- Historical 25 crafts (70009) cannot qualify a 250-260 material budget.
    { skillMin=250, skillTarget=260, recipe="Brightcloth Cloak",expectedCrafts=25,
      materials={mat("BOLT_RUNECLOTH",4),mat("GOLD_BAR",2),mat("RUNE_THREAD",1)},
      evidence="forever-beta-70009",requiredSkillAuthority="NOT_VERIFIED_DB70450",
      rawYellowThreshold=245,rawGreyThreshold=275,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=14103,outputYieldLiveVerified=false,
      recipeSource="drop-pattern",recipeSourceEvidence="HISTORICAL_DROP_UNVERIFIED",
      sourceRequirement={kind="pattern",name="Brightcloth Cloak",itemID=14484,
          evidence="DB70450_ITEMSPARSE_ITEMXITEMEFFECT_LINK",itemRequiredSkillRank=230},
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=250,craftEstimateGapToSkill=260,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-250-260-brightcloth-cloak-evidence-p02x-v1" },
    -- P0.2Y DB70450: Spell18420 Tailoring197 raw difficulty245/275,
    -- SpellReagents14048x4/3577x2/14341x1, output item14103. Pattern14484
    -- RequiredSkillRank230 is item metadata, not observed recipe access.
    -- Historic 25 crafts are NOT a 260-262 qualified material/skillup budget.
    { skillMin=260, skillTarget=262, recipe="Brightcloth Cloak",expectedCrafts=25,
      materials={mat("BOLT_RUNECLOTH",4),mat("GOLD_BAR",2),mat("RUNE_THREAD",1)},
      evidence="forever-beta-70009",requiredSkillAuthority="NOT_VERIFIED_DB70450",
      rawYellowThreshold=245,rawGreyThreshold=275,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=14103,outputYieldLiveVerified=false,
      recipeSource="drop-pattern",recipeSourceEvidence="HISTORICAL_DROP_UNVERIFIED",
      sourceRequirement={kind="pattern",name="Brightcloth Cloak",itemID=14484,
          evidence="DB70450_ITEMSPARSE_ITEMXITEMEFFECT_LINK",itemRequiredSkillRank=230},
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=260,craftEstimateGapToSkill=262,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-260-262-brightcloth-cloak-evidence-p02y-v1" },
    -- P0.2Y DB70450: Spell18438 Tailoring197 raw difficulty255/285,
    -- reagents14048x6/14227x2/14341x1, effect output item13865.
    -- Pattern14491 RequiredSkillRank240 is item metadata, not live learning.
    -- 35 crafts are an unverified historical estimate, NOT a skill-up forecast.
    { skillMin=262, skillTarget=270, recipe="Runecloth Pants",expectedCrafts=35,
      materials={mat("BOLT_RUNECLOTH",6),mat("IRONWEB_SPIDER_SILK",2),mat("RUNE_THREAD",1)},
      evidence="forever-beta-70009",requiredSkillAuthority="NOT_VERIFIED_DB70450",
      rawYellowThreshold=255,rawGreyThreshold=285,rawDifficultySourceBuild=70450,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=13865,outputYieldLiveVerified=false,
      recipeSource="drop-pattern",recipeSourceEvidence="HISTORICAL_DROP_UNVERIFIED",
      sourceRequirement={kind="pattern",name="Runecloth Pants",itemID=14491,
          evidence="DB70450_ITEMSPARSE_ITEMXITEMEFFECT_LINK",itemRequiredSkillRank=240},
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE",
      craftEstimateGapFromSkill=262,craftEstimateGapToSkill=270,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-262-270-runecloth-pants-evidence-p02y-v1" },
    -- P1/0.34.102: DB70450 SkillLine197, Spell18438 Effect24 item13865,
    -- reagents 14048x6,14227x2,14341x1; raw trivial low255/high285.
    -- Pattern14491 is an ItemXItemEffect/ItemEffect teaching link only.
    -- This window does NOT prove live learned minimum, source, or skill-ups.
    { skillMin=270,skillTarget=278,recipe="Runecloth Pants",expectedCrafts=nil,
      historicalExpectedCrafts=35,
      materials={mat("BOLT_RUNECLOTH",6),mat("IRONWEB_SPIDER_SILK",2),mat("RUNE_THREAD",1)},
      evidence="DB70450_FIELD_REFERENCE",rawYellowThreshold=255,rawGreyThreshold=285,
      rawDifficultySourceBuild=70450,rawMinSkillLineRank=1,rawAcquireMethod=0,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=13865,outputYieldLiveVerified=false,
      recipeSource="unknown",recipeSourceEvidence="PATTERN_TEACHING_LINK_NOT_LIVE_ACCESS",
      sourceRequirement={kind="pattern",name="Runecloth Pants",itemID=14491,
          evidence="DB70450_ITEMXITEMEFFECT_ITEMEFFECT_TEACHING_LINK"},
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE_UNVERIFIED",
      craftEstimateGapFromSkill=270,craftEstimateGapToSkill=278,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,readOnly=true,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-270-278-runecloth-pants-field-db70450-v1" },
    -- DB70450 Spell18560: Effect24 item14342, reagent Felcloth14256x2,
    -- raw low270/high300. Item14526 teaching-link not trainer/vendor proof.
    -- Isolate just 278-280; preserve original 280-293 historical behavior.
    { skillMin=278,skillTarget=280,recipe="Mooncloth",expectedCrafts=nil,
      historicalExpectedCrafts=33,materials={mat("FELCLOTH",2)},
      evidence="DB70450_FIELD_REFERENCE",rawYellowThreshold=270,rawGreyThreshold=300,
      rawDifficultySourceBuild=70450,rawMinSkillLineRank=1,rawAcquireMethod=0,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=14342,outputYieldLiveVerified=false,
      recipeSource="unknown",recipeSourceEvidence="PATTERN_TEACHING_LINK_NOT_LIVE_ACCESS",
      sourceRequirement={kind="pattern",name="Mooncloth",itemID=14526,
          evidence="DB70450_ITEMXITEMEFFECT_ITEMEFFECT_TEACHING_LINK"},
      sourceSpellFocusReference=883, -- DB70450 station reference: Moonwell; NOT actual access
      sourceFocusLabel="Moonwell",sourceFocusQualification="REFERENCE_NOT_LIVE",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE_UNVERIFIED",
      craftEstimateGapFromSkill=278,craftEstimateGapToSkill=280,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,readOnly=true,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-278-280-mooncloth-field-db70450-v1" },
    -- P1 0.34.104: 280-293 source-field reference, NOT a proven 13-point
    -- progression. DB70450 Spell18560 Effect24 -> 14342, Felcloth14256x2,
    -- raw low270/high300; SpellCastingRequirements requires focus883.
    -- Preserve historical 33 only as explicitly unqualified archival data.
    { skillMin=280,skillTarget=293,recipe="Mooncloth",expectedCrafts=nil,
      historicalExpectedCrafts=33,materials={mat("FELCLOTH",2)},
      evidence="DB70450_FIELD_REFERENCE",rawYellowThreshold=270,rawGreyThreshold=300,
      rawDifficultySourceBuild=70450,rawMinSkillLineRank=1,rawAcquireMethod=0,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=14342,outputYieldLiveVerified=false,
      recipeSource="unknown",recipeSourceEvidence="PATTERN_TEACHING_LINK_NOT_LIVE_ACCESS",
      sourceRequirement={kind="pattern",name="Mooncloth",itemID=14526,
          evidence="DB70450_ITEMXITEMEFFECT_ITEMEFFECT_TEACHING_LINK"},
      sourceSpellFocusReference=883,sourceFocusLabel="Moonwell",
      sourceFocusQualification="REFERENCE_NOT_LIVE",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE_UNVERIFIED",
      craftEstimateGapFromSkill=280,craftEstimateGapToSkill=293,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,readOnly=true,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-280-293-mooncloth-progression-evidence-db70450-v1" },
    -- P1 0.34.104: 293-300 source-field reference. Spell22902 Effect24
    -- output18486, raw low290/high320, focus2250 and pattern18487 teaching
    -- link; NONE establishes live learning, station or skill-up rate.
    { skillMin=293,skillTarget=300,recipe="Mooncloth Robe",expectedCrafts=nil,
      historicalExpectedCrafts=9,
      materials={mat("BOLT_RUNECLOTH",6),mat("MOONCLOTH",4),mat("GOLDEN_PEARL",2),mat("RUNE_THREAD",2)},
      evidence="DB70450_FIELD_REFERENCE",rawYellowThreshold=290,rawGreyThreshold=320,
      rawDifficultySourceBuild=70450,rawMinSkillLineRank=1,rawAcquireMethod=0,
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=18486,outputYieldLiveVerified=false,
      recipeSource="unknown",recipeSourceEvidence="PATTERN_TEACHING_LINK_NOT_LIVE_ACCESS",
      sourceRequirement={kind="pattern",name="Mooncloth Robe",itemID=18487,
          evidence="DB70450_ITEMXITEMEFFECT_ITEMEFFECT_TEACHING_LINK"},
      sourceSpellFocusReference=2250,sourceFocusLabel="Spinning Wheel",
      sourceFocusQualification="REFERENCE_NOT_LIVE",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",
      craftCountQualified=false,craftCountAuthority="HISTORICAL_70009_ESTIMATE_UNVERIFIED",
      craftEstimateGapFromSkill=293,craftEstimateGapToSkill=300,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,readOnly=true,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-293-300-mooncloth-robe-progression-evidence-db70450-v1" },
}


for _, step in ipairs(ROUTE) do
    local identity = RECIPE_IDENTITIES[step.recipe]
    if identity then
        step.recipeID = identity.recipeID
        step.recipeIdentityEvidence = RECIPE_IDENTITY_EVIDENCE.contract
        step.recipeIdentitySource = identity.source
        step.recipeIdentityURL = identity.url
        step.recipeIdentityBuildPinned = false
        step.liveCurrentBuildCorroborationRequired = true
    end
end

-- P1: 70450-identifiable, field-scoped options for a SINGLE advisory craft.
-- An option is never eligible merely because it appears in this catalogue.
-- Planner additionally requires same-build observed knowledge and a non-gray
-- difficulty observed from the actual client's profession window.
local PROGRESSION_CANDIDATES = {
    ROUTE[7], -- 3848, can remain usable through some of 137-144 if observed
    ROUTE[8], -- 8762, conflicting minimum, never promoted by reference alone
    ROUTE[9], -- 3852, can potentially extend through 154
    ROUTE[10],-- 3871, external 145/170 minimum conflict
    ROUTE[11],-- 3813, can potentially extend through 159
    ROUTE[12],-- 8786, reference min175; usable only if ACTUALLY learned/non-gray
    ROUTE[13],-- 8791, contradictory unpinned minimums 185/170; live ONLY
    ROUTE[14],-- 8799, contradictory unpinned minimums 195/180; live ONLY
    ROUTE[15],-- 8799, P0.2R 190-195; live ONLY
    ROUTE[16],-- 12053, P0.2R 195-200; live ONLY
    ROUTE[17],-- 12053, P0.2S 200-205; observed learned/non-gray ONLY
    ROUTE[18],-- 12072, P0.2S 205-210; observed learned/non-gray ONLY
    ROUTE[19],-- 12072, P0.2T 210-220; observed learned/non-gray ONLY
    ROUTE[20],-- 12072, P0.2U 220-225; current-build observed only
    ROUTE[21],-- 18402, P0.2U 225-230; current-build observed only
    ROUTE[22],-- 18402, P0.2V 230-240; current-build observed only
    ROUTE[23],-- 18402, P0.2W 240-245; current-build observed only
    ROUTE[24],-- 18420, P0.2W 245-250; pattern not proof of learning
    ROUTE[25],-- 18420, P0.2X 250-260; pattern not proof of learning
    ROUTE[26],-- 18420, P0.2Y 260-262; observed learned ONLY
    ROUTE[27],-- 18438, P0.2Y 262-270; observed learned ONLY
    ROUTE[28],-- 18438, DB70450 270-278 only, fresh learned ONE advisory
    ROUTE[29],-- 18560, DB70450 278-280 only, fresh learned ONE advisory
    ROUTE[30],-- 18560, 280-293 DB70450 only; K102 cooldown/area applies
    ROUTE[31],-- 22902, 293-300 DB70450 only; focus/location unverified
    { recipe="Azure Silk Gloves",recipeID=3854,
      requiredSkill=145,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/spell=3854/azure-silk-gloves",
      rawYellowThreshold=140,rawGreyThreshold=170,rawDifficultySourceBuild=70450,
      materials={mat("BOLT_SILK",3),mat("HEAVY_LEATHER",2),mat("BLUE_DYE",2),mat("FINE_THREAD",2)},
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=4319,outputYieldLiveVerified=false,
      recipeSource="vendor-pattern",sourceRequirement={kind="pattern",name="Azure Silk Gloves",
        evidence="WOWHEAD_FOREVER_VENDOR_PATTERN_EXTERNAL_UNPINNED"},
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",expectedCrafts=nil,
      craftCountQualified=false,craftCountAuthority="NO_VERIFIED_137_160_CRAFT_RATE",
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false,
      sourceQualificationContract="tailoring-p1-azure-silk-gloves-field-70450-v1" },
    { recipe="Earthen Vest",recipeID=8764,
      requiredSkill=170,requiredSkillAuthority="WOWHEAD_FOREVER",
      requiredSkillSourceURL="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes",
      rawYellowThreshold=155,rawGreyThreshold=185,rawDifficultySourceBuild=70450,
      materials={mat("BOLT_SILK",3),{itemID=7067,name="Elemental Earth",quantity=1,source="auction"},mat("FINE_THREAD",2)},
      materialEvidence="DB_70450_SPELLREAGENTS",materialSourceBuild=70450,
      outputItemID=7051,outputYieldLiveVerified=false,recipeSource="trainer",
      recipeAccessObserved=false,learnedState="NOT_OBSERVED",expectedCrafts=nil,
      craftCountQualified=false,advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false },
    { recipe="Bolt of Mageweave",recipeID=3865,
      requiredSkill=175,requiredSkillAuthority="WOWHEAD_FOREVER",
      rawYellowThreshold=145,rawGreyThreshold=150,rawDifficultySourceBuild=70450,
      materials={mat("MAGEWEAVE_CLOTH",5)},materialEvidence="DB_70450_SPELLREAGENTS",
      outputItemID=4339,recipeSource="trainer",expectedCrafts=nil,craftCountQualified=false,
      advisoryOnly=true,routeQualified=false,plannerEligible=false,
      nativeDispatchAllowed=false,executionEligible=false },
}

local TRAINERS = {
    { cap=75,  nextCap=150, rank="Journeyman Tailoring", requiredSkill=50, minCharacterLevel=10 },
    { cap=150, nextCap=225, rank="Expert Tailoring",     requiredSkill=125, minCharacterLevel=20,
      sourceURL="https://www.wow-professions.com/forever/tailoring-trainers" },
    { cap=225, nextCap=300, rank="Artisan Tailoring",    requiredSkill=200, minCharacterLevel=35, sourceURL="https://www.wow-professions.com/forever/tailoring-trainers" },
}

JLP.data.tailoring = {
    key = "TAILORING",
    name = "Tailoring",
    skillMin = 1,
    skillMax = 300,
    evidence = "forever-beta-70009",
    sourceBuild = 70009,
    authorityClass="PRODUCTION", productionBaselineBuild=70009, legacyProductionBaseline=true,
    requalificationTargetBuild=70245,
    datasetStatus = "route-1-300-integrated",
    recipeIdentityContract = RECIPE_IDENTITY_EVIDENCE.contract,
    recipeIdentityEvidence = RECIPE_IDENTITY_EVIDENCE,
    recipeIdentities = RECIPE_IDENTITIES,
    progressionCandidates=PROGRESSION_CANDIDATES,
    -- Source-qualified planning, not observed skill-ups or fixed output yield.
    earlyProgression={fromSkill=25,toSkill=31,recipeID=12044,
        recipe="Simple Linen Pants",requiredSkill=1,rank="Apprentice",
        yellow=40,green=50,gray=60,outputItemID=10045,
        sourceURL="https://www.wowhead.com/forever/spell=12044/simple-linen-pants",
        sourceBuild=70450,sourceCheckedAt="2026-10-24",
        learning="VERIFY_CURRENT_TRAINER_OR_LEARNED_RECIPE",
        outputYieldStatus="CONFLICTING_EXTERNAL_REFERENCES"},
    -- Current panel learned-state remains mandatory for a CRAFT recommendation.
    linenProgression={contract="tailoring-40-50-forever-v1",sourceCheckedAt="2026-10-25",
        recipes={
            {recipeID=12044,recipe="Simple Linen Pants",requiredSkill=1,yellow=40,gray=60,
                outputItemID=10045,slug="simple-linen-pants",learning="profession",
                sourceURL="https://www.wowhead.com/forever/spell=12044/simple-linen-pants"},
            {recipeID=2385,recipe="Brown Linen Vest",requiredSkill=10,yellow=45,gray=70,
                outputItemID=2568,slug="brown-linen-vest",learning="trainer",
                sourceURL="https://www.wowhead.com/forever/spell=2385/brown-linen-vest"},
            {recipeID=8776,recipe="Linen Belt",requiredSkill=15,yellow=50,gray=85,
                outputItemID=7026,slug="linen-belt",learning="trainer",
                sourceURL="https://www.wowhead.com/forever/spell=8776/linen-belt"}}},
    linenProducer={contract="linen-2963-client-schematic-70532-v1",recipeID=2963,
        outputItemID=2996,quantityMin=1,quantityMax=1,inputItemID=2589,inputQuantity=2,
        sourceBuild=70532,source="Referencer/Spildata/JuztProfessionProbe.lua",
        sourceSHA256="ad9c51f68e1cdb8359f15058054ffe1f5e4fc5cfefc51a6abe6ac65f2e949f6a",
        capturedAt=1792708450,panelBaseSkillLineID=197,
        evidence="CLIENT_RECIPE_SCHEMATIC_NOT_OBSERVED_CRAFT"},
    journeymanProgression={contract="tailoring-50-77-forever-v1",checkedAt="2026-10-25",
        rank={cap=75,nextCap=150,requiredSkill=50,minCharacterLevel=10,rank="Journeyman Tailoring",
            sourceURL="https://www.wow-professions.com/forever/tailoring-trainers"},
        recipes={
            {recipeID=8776,recipe="Linen Belt",requiredSkill=15,yellow=50,green=67,gray=85,
                outputItemID=7026,reagents="2996:1,2320:1",slug="linen-belt"},
            {recipeID=2385,recipe="Brown Linen Vest",requiredSkill=10,yellow=45,green=57,gray=70,
                outputItemID=2568,reagents="2996:1,2320:1",slug="brown-linen-vest"},
            {recipeID=2397,recipe="Reinforced Linen Cape",requiredSkill=60,yellow=60,green=77,gray=95,
                outputItemID=2580,reagents="2996:2,2320:3",slug="reinforced-linen-cape"},
            {recipeID=2402,recipe="Woolen Cape",requiredSkill=75,yellow=80,green=97,gray=115,
                outputItemID=2584,reagents="2997:1,2321:1",slug="woolen-cape"},
            {recipeID=12046,recipe="Simple Kilt",requiredSkill=75,yellow=75,green=92,gray=110,
                outputItemID=10047,reagents="2996:4,2321:1",slug="simple-kilt"}}},
    woolProgression={contract="tailoring-77-102-wool-v1",
        continuationContract="tailoring-102-107-source-v1",continuationTarget=107,sourceBuild=70532,
        nextContract="tailoring-107-125-source-v1",nextTarget=125,
        expertContract="tailoring-125-225-source-v1",expertTarget=225,
        artisanContract="tailoring-225-300-source-v1",artisanTarget=300,
        sourceSHA256="ad9c51f68e1cdb8359f15058054ffe1f5e4fc5cfefc51a6abe6ac65f2e949f6a",
        capturedAt=1792708450,producerRecipeID=2964,producerOutputItemID=2997,
        producerInputItemID=2592,producerInputQuantity=3,producerOutputQuantity=1,
        -- Public75/75/77/85 versus packed70/85: no inferred yellow boundary.
        producerMinimum=75,producerYellow=75,producerGreen=77,producerGray=85,
        producerCastSeconds=5.125,
        recipes={
            {id=2402,name="Woolen Cape",minimum=75,yellow=80,green=97,gray=115,dbYellow=80,
                output=2584,reagents="2997:1,2321:1",slug="woolen-cape",castSeconds=8,learning="trainer"},
            {id=12046,name="Simple Kilt",minimum=75,yellow=75,green=92,gray=110,dbYellow=75,
                output=10047,reagents="2996:4,2321:1",slug="simple-kilt",learning="trainer"},
            {id=2397,name="Reinforced Linen Cape",minimum=60,yellow=60,green=77,gray=95,dbYellow=60,
                output=2580,reagents="2996:2,2320:3",slug="reinforced-linen-cape",learning="trainer"},
            {id=8776,name="Linen Belt",minimum=15,yellow=50,green=67,gray=85,dbYellow=50,
                output=7026,reagents="2996:1,2320:1",slug="linen-belt",learning="trainer"},
            {id=2401,name="Woolen Boots",minimum=95,yellow=95,green=112,gray=130,dbYellow=95,
                output=2583,reagents="2997:4,2321:2,2318:2",slug="woolen-boots",learning="trainer"},
            {id=2406,name="Gray Woolen Shirt",minimum=100,yellow=100,green=100,gray=110,dbYellow=90,
                output=2587,reagents="2997:2,2321:1,4340:1",slug="gray-woolen-shirt",castSeconds=8,
                learning="trainer",difficultyConflict="PUBLIC_100_100_100_110_VS_DB_90_110"},
            {id=3758,name="Green Woolen Bag",minimum=95,yellow=100,green=nil,gray=135,dbYellow=100,
                output=4241,reagents="2997:4,2605:1,2321:1",slug="green-woolen-bag",learning="pattern",
                learningConflict="PATTERN_4292_MIN75_VS_RECIPE_OVERVIEW95_CONSERVATIVE_FLOOR"},
            -- User-confirmed individual Forever Quick Facts, 2026-10-25.
            -- Category overview125 remains a source conflict, not a learning gate.
            {id=3839,name="Bolt of Silk Cloth",minimum=100,yellow=110,green=115,gray=120,dbYellow=110,
                output=4305,reagents="4306:4",slug="bolt-of-silk-cloth",learning="trainer",
                minimumAuthority="USER_CONFIRMED_FOREVER_QUICK_FACTS_2026_10_25",
                sourceURL="https://www.wowhead.com/forever/spell=3839/bolt-of-silk-cloth",
                categoryMinimumConflict=125,liveVerified=false,trainingCostDisplay="5"},
            {id=3848,name="Double-stitched Woolen Shoulders",minimum=110,yellow=110,green=127,gray=145,dbYellow=110,
                output=4314,reagents="2997:3,2321:2",slug="double-stitched-woolen-shoulders",learning="trainer",
                fromSkill=107,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW",outputQuantityReference=2,
                outputQuantityAuthority="USER_REPORTED_INDIVIDUAL_FOREVER_PAGE",outputQuantityConflict=1,
                outputConflictSource="https://wowforevertalent.com/professions/tailoring/"},
            {id=3849,name="Reinforced Woolen Shoulders",minimum=120,yellow=120,green=137,gray=155,dbYellow=120,
                output=4315,reagents="2997:6,2319:2,2321:2",slug="reinforced-woolen-shoulders",learning="trainer",
                fromSkill=107,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW",outputQuantityStatus="UNKNOWN"},
            {id=3852,name="Gloves of Meditation",minimum=130,yellow=125,green=140,gray=155,dbYellow=125,output=4318,reagents="2997:4,2321:3,3383:1",slug="gloves-of-meditation",learning="trainer",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=3868,name="Phoenix Gloves",minimum=125,yellow=125,green=142,gray=160,dbYellow=125,output=4331,reagents="2997:4,5500:1,2321:4,2324:2",slug="phoenix-gloves",learning="pattern",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",outputQuantityConflict=2,recipeItemID=4348,recipeItemRequiredSkill=100},
            {id=3813,name="Small Silk Pack",minimum=150,yellow=145,green=160,gray=175,dbYellow=145,output=4245,reagents="4305:3,4234:2,2321:3",slug="small-silk-pack",learning="trainer",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=3854,name="Azure Silk Gloves",minimum=145,yellow=140,green=155,gray=170,dbYellow=140,output=4319,reagents="4305:3,4234:2,6260:2,2321:2",slug="azure-silk-gloves",learning="trainer",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=8784,name="Green Silk Armor",minimum=165,yellow=150,green=165,gray=180,dbYellow=150,output=7065,reagents="4305:5,2605:2,4291:1",slug="green-silk-armor",learning="pattern",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=7090,recipeItemRequiredSkill=130},
            {id=8764,name="Earthen Vest",minimum=170,yellow=155,green=170,gray=185,dbYellow=155,output=7051,reagents="4305:3,7067:1,2321:2",slug="earthen-vest",learning="trainer",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=8786,name="Azure Silk Cloak",minimum=175,yellow=160,green=175,gray=190,dbYellow=160,output=7053,reagents="4305:3,6260:2,2321:2",slug="azure-silk-cloak",learning="trainer",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=8791,name="Crimson Silk Vest",minimum=185,yellow=170,green=180,gray=190,dbYellow=170,output=7058,reagents="4305:4,2604:2,2321:2",slug="crimson-silk-vest",learning="trainer",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=8789,name="Crimson Silk Cloak",minimum=180,yellow=165,green=180,gray=195,dbYellow=165,output=7056,reagents="4305:5,2604:2,6371:2,4291:1",slug="crimson-silk-cloak",learning="pattern",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",outputQuantityConflict=2,recipeItemID=7087,recipeItemRequiredSkill=145},
            {id=8799,name="Crimson Silk Pantaloons",minimum=195,yellow=180,green=190,gray=200,dbYellow=180,output=7062,reagents="4305:4,2604:2,4291:2",slug="crimson-silk-pantaloons",learning="trainer",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=8774,name="Green Silken Shoulders",minimum=180,yellow=165,green=180,gray=195,dbYellow=165,output=7057,reagents="4305:5,4291:2",slug="green-silken-shoulders",learning="unknown",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",outputQuantityConflict=2},
            {id=3862,name="Icy Cloak",minimum=200,yellow=185,green=200,gray=215,dbYellow=185,output=4327,reagents="4339:3,4291:2,3829:1,4337:2",slug="icy-cloak",learning="pattern",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",outputQuantityConflict=2,sourceSpellFocusReference=2250,recipeItemID=4355,recipeItemRequiredSkill=165},
            {id=12048,name="Black Mageweave Vest",minimum=205,yellow=185,green=200,gray=215,dbYellow=185,output=9998,reagents="4339:2,4291:3",slug="black-mageweave-vest",learning="trainer",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=8802,name="Crimson Silk Robe",minimum=205,yellow=185,green=200,gray=215,dbYellow=185,output=7063,reagents="4305:8,7068:4,3827:2,2604:4,4291:1",slug="crimson-silk-robe",learning="pattern",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",outputQuantityConflict=2,recipeItemID=7088,recipeItemRequiredSkill=170},
            {id=12050,name="Black Mageweave Robe",minimum=210,yellow=190,green=205,gray=220,dbYellow=190,output=10001,reagents="4339:3,8343:1",slug="black-mageweave-robe",learning="trainer",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",outputQuantityConflict=2},
            {id=12053,name="Black Mageweave Gloves",minimum=215,yellow=195,green=210,gray=225,dbYellow=195,output=10003,reagents="4339:2,8343:2",slug="black-mageweave-gloves",learning="trainer",fromSkill=125,expert=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=12065,name="Mageweave Bag",minimum=225,yellow=205,green=220,gray=235,dbYellow=205,output=10050,reagents="4339:4,4291:2",slug="mageweave-bag",learning="UNKNOWN_EXACT_TEACHER_OR_SOURCE",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=12072,name="Black Mageweave Headband",minimum=230,yellow=205,green=220,gray=235,dbYellow=205,output=10024,reagents="4339:3,8343:2",slug="black-mageweave-headband",learning="UNKNOWN_EXACT_TEACHER_OR_SOURCE",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=12074,name="Black Mageweave Shoulders",minimum=230,yellow=205,green=220,gray=235,dbYellow=205,output=10027,reagents="4339:3,8343:2",slug="black-mageweave-shoulders",learning="UNKNOWN_EXACT_TEACHER_OR_SOURCE",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=12079,name="Red Mageweave Bag",minimum=235,yellow=210,green=225,gray=240,dbYellow=210,output=10051,reagents="4339:4,2604:2,8343:2",slug="red-mageweave-bag",learning="UNKNOWN_EXACT_TEACHER_OR_SOURCE",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=12082,name="Shadoweave Boots",minimum=240,yellow=215,green=230,gray=245,dbYellow=215,output=10031,reagents="4339:6,10285:6,8343:3,4304:2",slug="shadoweave-boots",learning="UNKNOWN_EXACT_TEACHER_OR_SOURCE",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR"},
            {id=12081,name="Admiral's Hat",minimum=240,yellow=215,green=230,gray=245,dbYellow=215,output=10030,reagents="4339:3,4589:6,8343:2",slug="admirals-hat",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=10318,recipeItemRequiredSkill=200},
            {id=18409,name="Runecloth Cloak",minimum=265,yellow=240,green=255,gray=270,dbYellow=240,output=13860,reagents="14048:4,14227:1,14341:1",slug="runecloth-cloak",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=14472,recipeItemRequiredSkill=220},
            {id=18440,name="Mooncloth Leggings",minimum=290,yellow=270,green=285,gray=300,dbYellow=270,output=14137,reagents="14048:6,14342:4,14341:1",slug="mooncloth-leggings",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=14497,recipeItemRequiredSkill=245,sourceSpellFocusReference=2250},
            -- Exact70532 pattern requirements + Forever source-specific guide, not old product-category minima.
            {id=18423,name="Runecloth Boots",minimum=235,yellow=250,green=265,gray=280,dbYellow=250,output=13864,reagents="14048:4,14227:2,8170:4,14341:1",slug="runecloth-boots",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,outputQuantityConflict=2,minimumAuthority="FOREVER_PATTERN_DB2_70532",recipeItemID=14488,recipeItemRequiredSkill=235,categoryMinimumConflict=280,acquisitionSourceStatus="FOREVER_NAMED_VENDOR_REFERENCE"},
            {id=18417,name="Runecloth Gloves",minimum=230,yellow=245,green=260,gray=275,dbYellow=245,output=13863,reagents="14048:4,8170:4,14341:1",slug="runecloth-gloves",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="FOREVER_PATTERN_DB2_70532",recipeItemID=14481,recipeItemRequiredSkill=230,categoryMinimumConflict=275,acquisitionSourceStatus="FOREVER_NAMED_VENDOR_REFERENCE"},
            {id=27659,name="Enchanted Runecloth Bag",minimum=230,yellow=245,green=260,gray=275,dbYellow=245,output=22248,reagents="14048:5,16203:2,14341:2",slug="enchanted-runecloth-bag",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,outputQuantityConflict=2,minimumAuthority="FOREVER_PATTERN_DB2_70532",recipeItemID=22308,recipeItemRequiredSkill=230,categoryMinimumConflict=275,acquisitionSourceStatus="VENDOR_CATEGORY_KANIA_REFERENCE_REQUIRES_CONFIRMATION"},
            {id=18560,name="Mooncloth",minimum=250,yellow=270,green=285,gray=300,dbYellow=270,output=14342,reagents="14256:2",slug="mooncloth",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=14526,recipeItemRequiredSkill=230,sourceSpellFocusReference=883,cooldownMS=342000000,userFixedOutput=true},
            {id=1257472,name="Earthenweave Boots",minimum=225,yellow=240,green=255,gray=270,dbYellow=240,output=254093,reagents="14048:4,7076:2,8170:2,14341:1",slug="earthenweave-boots",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",outputQuantityConflict=2,recipeItemID=254094,recipeItemRequiredSkill=225,acquisitionSourceStatus="UNCONFIRMED_FOREVER_PATTERN_SOURCE"},
            {id=1257485,name="Earthenweave Mantle",minimum=240,yellow=255,green=270,gray=285,dbYellow=255,output=254119,reagents="14048:6,7076:1,14341:1",slug="earthenweave-mantle",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",outputQuantityConflict=2,recipeItemID=254120,recipeItemRequiredSkill=240,acquisitionSourceStatus="UNCONFIRMED_FOREVER_PATTERN_SOURCE"},
            {id=1257488,name="Earthenweave Leggings",minimum=245,yellow=260,green=275,gray=290,dbYellow=260,output=254125,reagents="14048:6,7076:2,14341:1",slug="earthenweave-leggings",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=254126,recipeItemRequiredSkill=245,acquisitionSourceStatus="UNCONFIRMED_FOREVER_PATTERN_SOURCE"},
            {id=1257486,name="Earthenweave Vest",minimum=250,yellow=265,green=280,gray=295,dbYellow=265,output=254121,reagents="14048:8,7076:1,14341:1",slug="earthenweave-vest",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=254122,recipeItemRequiredSkill=250,acquisitionSourceStatus="UNCONFIRMED_FOREVER_PATTERN_SOURCE"},
            {id=1257489,name="Ghostweave Mantle",minimum=250,yellow=265,green=280,gray=295,dbYellow=265,output=254127,reagents="14048:5,9210:3,14227:1,14341:1",slug="ghostweave-mantle",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=254128,recipeItemRequiredSkill=250,acquisitionSourceStatus="UNCONFIRMED_FOREVER_PATTERN_SOURCE"},
            {id=1257490,name="Ghostweave Boots",minimum=255,yellow=265,green=280,gray=295,dbYellow=265,output=254129,reagents="14048:4,9210:2,14227:1,8170:2,14341:1",slug="ghostweave-boots",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",outputQuantityConflict=2,recipeItemID=254130,recipeItemRequiredSkill=255,acquisitionSourceStatus="UNCONFIRMED_FOREVER_PATTERN_SOURCE"},
            {id=1257491,name="Earthenweave Cuffs",minimum=255,yellow=270,green=285,gray=300,dbYellow=270,output=254131,reagents="14048:5,7076:1,14341:1",slug="earthenweave-cuffs",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=254132,recipeItemRequiredSkill=255,acquisitionSourceStatus="UNCONFIRMED_FOREVER_PATTERN_SOURCE"},
            {id=1257493,name="Ghostweave Hood",minimum=260,yellow=275,green=290,gray=305,dbYellow=275,output=254135,reagents="14048:6,9210:3,14227:2,14341:1",slug="ghostweave-hood",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",outputQuantityConflict=2,recipeItemID=254136,recipeItemRequiredSkill=260,acquisitionSourceStatus="UNCONFIRMED_FOREVER_PATTERN_SOURCE"},
            {id=1257494,name="Earthenweave Crown",minimum=260,yellow=275,green=290,gray=305,dbYellow=275,output=254137,reagents="14048:6,7076:3,14341:1",slug="earthenweave-crown",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=254138,recipeItemRequiredSkill=260,acquisitionSourceStatus="UNCONFIRMED_FOREVER_PATTERN_SOURCE"},
            {id=1257487,name="Runecloth Cuffs",minimum=250,yellow=265,green=280,gray=295,dbYellow=265,output=254123,reagents="14048:5,14227:1,14341:1",slug="runecloth-cuffs",learning="pattern",fromSkill=225,artisan=true,outputQuantityReference=1,minimumAuthority="WOWHEAD_FOREVER_OVERVIEW_CONSERVATIVE_FLOOR",recipeItemID=254124,recipeItemRequiredSkill=250},
        }},
    route = ROUTE,
    steps = ROUTE,
    trainerGates = TRAINERS,
    materials = MATERIALS,
}

-- BEGIN GENERATED DB2 70532 TAILORING
JLP.data.tailoring.db2 = {contract="tailoring-db2-70532-fields-v1",sourceBuild=70532,
    manifestSHA256="d3cb243e761c833b3d43cba28842d8d36d5f46eacc58fff17290f4fb5aada959",recipes={
    [2963]={abilityID=2359,name="Bolt of Linen Cloth",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=25,trivialHigh=50,numSkillUps=1,reagentRecordID=19519,reagents="2589:2",effectID=681036,outputItemID=2996,effectBasePoints=1.0,castRecordID=14,spellMiscID=315950,castBaseMS=3000,castMinimumMS=3000},
    [2964]={abilityID=2370,name="Bolt of Woolen Cloth",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=70,trivialHigh=85,numSkillUps=1,reagentRecordID=19520,reagents="2592:3",effectID=681037,outputItemID=2997,effectBasePoints=1.0,castRecordID=33,spellMiscID=315951,castBaseMS=5125,castMinimumMS=3000},
    [12044]={abilityID=6576,name="Simple Linen Pants",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=40,trivialHigh=60,numSkillUps=1,reagentRecordID=19511,reagents="2996:1,2320:1",effectID=680963,outputItemID=10045,effectBasePoints=1.0,castRecordID=33,spellMiscID=315883,castBaseMS=5125,castMinimumMS=3000},
    [2385]={abilityID=2361,name="Brown Linen Vest",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=45,trivialHigh=70,numSkillUps=1,reagentRecordID=19484,reagents="2996:1,2320:1",effectID=680793,outputItemID=2568,effectBasePoints=1.0,castRecordID=33,spellMiscID=315730,castBaseMS=5125,castMinimumMS=3000},
    [8776]={abilityID=4848,name="Linen Belt",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=50,trivialHigh=85,numSkillUps=1,reagentRecordID=19814,reagents="2996:1,2320:1",effectID=685547,outputItemID=7026,effectBasePoints=1.0,castRecordID=33,spellMiscID=319898,castBaseMS=5125,castMinimumMS=3000},
    [2397]={abilityID=2367,name="Reinforced Linen Cape",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=60,trivialHigh=95,numSkillUps=1,reagentRecordID=19548,reagents="2996:2,2320:3",effectID=681261,outputItemID=2580,effectBasePoints=1.0,castRecordID=34,spellMiscID=316155,castBaseMS=8000,castMinimumMS=4000},
    [2402]={abilityID=2371,name="Woolen Cape",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=80,trivialHigh=115,numSkillUps=1,reagentRecordID=19502,reagents="2997:1,2321:1",effectID=680909,outputItemID=2584,effectBasePoints=1.0,castRecordID=34,spellMiscID=315834,castBaseMS=8000,castMinimumMS=4000},
    [12046]={abilityID=6578,name="Simple Kilt",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=75,trivialHigh=110,numSkillUps=1,reagentRecordID=20148,reagents="2996:4,2321:1",effectID=690051,outputItemID=10047,effectBasePoints=1.0,castRecordID=33,spellMiscID=323614,castBaseMS=5125,castMinimumMS=3000},
    [2401]={abilityID=2373,name="Woolen Boots",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=95,trivialHigh=130,numSkillUps=1,reagentRecordID=19521,reagents="2997:4,2321:2,2318:2",effectID=681094,outputItemID=2583,effectBasePoints=1.0,castRecordID=35,spellMiscID=316003,castBaseMS=12500,castMinimumMS=5000},
    [2406]={abilityID=2375,name="Gray Woolen Shirt",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=90,trivialHigh=110,numSkillUps=1,reagentRecordID=19489,reagents="2997:2,2321:1,4340:1",effectID=680810,outputItemID=2587,effectBasePoints=1.0,castRecordID=34,spellMiscID=315746,castBaseMS=8000,castMinimumMS=4000},
    [3758]={abilityID=4000,name="Green Woolen Bag",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=100,trivialHigh=135,numSkillUps=1,reagentRecordID=19909,reagents="2997:4,2605:1,2321:1",effectID=686710,outputItemID=4241,effectBasePoints=1.0,castRecordID=35,spellMiscID=320872,castBaseMS=12500,castMinimumMS=5000},
    [3839]={abilityID=2376,name="Bolt of Silk Cloth",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=110,trivialHigh=120,numSkillUps=1,reagentRecordID=19579,reagents="4306:4",effectID=681562,outputItemID=4305,effectBasePoints=1.0,castRecordID=33,spellMiscID=316419,castBaseMS=5125,castMinimumMS=3000},
    [3848]={abilityID=2385,name="Double-stitched Woolen Shoulders",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=110,trivialHigh=145,numSkillUps=1,reagentRecordID=19585,reagents="2997:3,2321:2",effectID=681611,outputItemID=4314,effectBasePoints=1.0,castRecordID=35,spellMiscID=316463,castBaseMS=12500,castMinimumMS=5000},
    [3849]={abilityID=2386,name="Reinforced Woolen Shoulders",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=120,trivialHigh=155,numSkillUps=1,reagentRecordID=19586,reagents="2997:6,2319:2,2321:2",effectID=681612,outputItemID=4315,effectBasePoints=1.0,castRecordID=37,spellMiscID=316464,castBaseMS=25000,castMinimumMS=10000},
    [3852]={abilityID=2389,name="Gloves of Meditation",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=125,trivialHigh=155,numSkillUps=1,reagentRecordID=19730,reagents="2997:4,2321:3,3383:1",effectID=682799,outputItemID=4318,effectBasePoints=1.0,castRecordID=37,spellMiscID=317531,castBaseMS=25000,castMinimumMS=10000},
    [3868]={abilityID=2402,name="Phoenix Gloves",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=125,trivialHigh=160,numSkillUps=1,reagentRecordID=19574,reagents="2997:4,5500:1,2321:4,2324:2",effectID=681503,outputItemID=4331,effectBasePoints=1.0,castRecordID=37,spellMiscID=316366,castBaseMS=25000,castMinimumMS=10000},
    [3813]={abilityID=4003,name="Small Silk Pack",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=145,trivialHigh=175,numSkillUps=1,reagentRecordID=19627,reagents="4305:3,4234:2,2321:3",effectID=681862,outputItemID=4245,effectBasePoints=1.0,castRecordID=37,spellMiscID=316686,castBaseMS=25000,castMinimumMS=10000},
    [3854]={abilityID=2390,name="Azure Silk Gloves",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=140,trivialHigh=170,numSkillUps=1,reagentRecordID=19708,reagents="4305:3,4234:2,6260:2,2321:2",effectID=682181,outputItemID=4319,effectBasePoints=1.0,castRecordID=37,spellMiscID=316970,castBaseMS=25000,castMinimumMS=10000},
    [8784]={abilityID=4869,name="Green Silk Armor",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=150,trivialHigh=180,numSkillUps=1,reagentRecordID=19905,reagents="4305:5,2605:2,4291:1",effectID=686694,outputItemID=7065,effectBasePoints=1.0,castRecordID=38,spellMiscID=320857,castBaseMS=45000,castMinimumMS=15000},
    [8764]={abilityID=4852,name="Earthen Vest",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=155,trivialHigh=185,numSkillUps=1,reagentRecordID=19918,reagents="4305:3,7067:1,2321:2",effectID=686878,outputItemID=7051,effectBasePoints=1.0,castRecordID=38,spellMiscID=321014,castBaseMS=45000,castMinimumMS=15000},
    [8786]={abilityID=4870,name="Azure Silk Cloak",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=160,trivialHigh=190,numSkillUps=1,reagentRecordID=19906,reagents="4305:3,6260:2,2321:2",effectID=686696,outputItemID=7053,effectBasePoints=1.0,castRecordID=38,spellMiscID=320859,castBaseMS=45000,castMinimumMS=15000},
    [8791]={abilityID=4872,name="Crimson Silk Vest",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=170,trivialHigh=190,numSkillUps=1,reagentRecordID=19885,reagents="4305:4,2604:2,2321:2",effectID=686470,outputItemID=7058,effectBasePoints=1.0,castRecordID=37,spellMiscID=320676,castBaseMS=25000,castMinimumMS=10000},
    [8789]={abilityID=4871,name="Crimson Silk Cloak",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=165,trivialHigh=195,numSkillUps=1,reagentRecordID=19862,reagents="4305:5,2604:2,6371:2,4291:1",effectID=686142,outputItemID=7056,effectBasePoints=1.0,castRecordID=38,spellMiscID=320418,castBaseMS=45000,castMinimumMS=15000},
    [8799]={abilityID=4876,name="Crimson Silk Pantaloons",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=180,trivialHigh=200,numSkillUps=1,reagentRecordID=19974,reagents="4305:4,2604:2,4291:2",effectID=687671,outputItemID=7062,effectBasePoints=1.0,castRecordID=37,spellMiscID=321648,castBaseMS=25000,castMinimumMS=10000},
    [8774]={abilityID=4856,name="Green Silken Shoulders",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=165,trivialHigh=195,numSkillUps=1,reagentRecordID=19904,reagents="4305:5,4291:2",effectID=686646,outputItemID=7057,effectBasePoints=1.0,castRecordID=38,spellMiscID=320818,castBaseMS=45000,castMinimumMS=15000},
    [3862]={abilityID=2398,name="Icy Cloak",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=185,trivialHigh=215,numSkillUps=1,reagentRecordID=19660,reagents="4339:3,4291:2,3829:1,4337:2",effectID=681976,outputItemID=4327,effectBasePoints=1.0,castRecordID=38,spellMiscID=316796,castBaseMS=45000,castMinimumMS=15000},
    [12048]={abilityID=6580,name="Black Mageweave Vest",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=185,trivialHigh=215,numSkillUps=1,reagentRecordID=20044,reagents="4339:2,4291:3",effectID=688794,outputItemID=9998,effectBasePoints=1.0,castRecordID=39,spellMiscID=322573,castBaseMS=60000,castMinimumMS=30000},
    [8802]={abilityID=4877,name="Crimson Silk Robe",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=185,trivialHigh=215,numSkillUps=1,reagentRecordID=19968,reagents="4305:8,7068:4,3827:2,2604:4,4291:1",effectID=687581,outputItemID=7063,effectBasePoints=1.0,castRecordID=39,spellMiscID=321578,castBaseMS=60000,castMinimumMS=30000},
    [12050]={abilityID=6582,name="Black Mageweave Robe",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=190,trivialHigh=220,numSkillUps=1,reagentRecordID=20127,reagents="4339:3,8343:1",effectID=689788,outputItemID=10001,effectBasePoints=1.0,castRecordID=39,spellMiscID=323401,castBaseMS=60000,castMinimumMS=30000},
    [12053]={abilityID=6584,name="Black Mageweave Gloves",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=195,trivialHigh=225,numSkillUps=1,reagentRecordID=20239,reagents="4339:2,8343:2",effectID=691002,outputItemID=10003,effectBasePoints=1.0,castRecordID=39,spellMiscID=324409,castBaseMS=60000,castMinimumMS=30000},
    [12065]={abilityID=6596,name="Mageweave Bag",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=205,trivialHigh=235,numSkillUps=1,reagentRecordID=20091,reagents="4339:4,4291:2",effectID=689407,outputItemID=10050,effectBasePoints=1.0,castRecordID=39,spellMiscID=323088,castBaseMS=60000,castMinimumMS=30000},
    [8489]={abilityID=4714,name="Red Swashbuckler's Shirt",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=150,trivialHigh=160,numSkillUps=1,reagentRecordID=19890,reagents="4305:3,2604:2,4291:1",effectID=686501,outputItemID=6796,effectBasePoints=1.0,castRecordID=37,spellMiscID=320703,castBaseMS=25000,castMinimumMS=10000},
    [3865]={abilityID=2377,name="Bolt of Mageweave",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=145,trivialHigh=150,numSkillUps=1,reagentRecordID=19634,reagents="4338:5",effectID=681889,outputItemID=4339,effectBasePoints=1.0,castRecordID=34,spellMiscID=316713,castBaseMS=8000,castMinimumMS=4000},
    [3871]={abilityID=2405,name="Formal White Shirt",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=145,trivialHigh=155,numSkillUps=1,reagentRecordID=19594,reagents="4305:3,2324:2,2321:1",effectID=681661,outputItemID=4334,effectBasePoints=1.0,castRecordID=37,spellMiscID=316505,castBaseMS=25000,castMinimumMS=10000},
    [12072]={abilityID=6603,name="Black Mageweave Headband",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=205,trivialHigh=235,numSkillUps=1,reagentRecordID=20189,reagents="4339:3,8343:2",effectID=690413,outputItemID=10024,effectBasePoints=1.0,castRecordID=39,spellMiscID=323923,castBaseMS=60000,castMinimumMS=30000},
    [12074]={abilityID=6605,name="Black Mageweave Shoulders",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=205,trivialHigh=235,numSkillUps=1,reagentRecordID=20210,reagents="4339:3,8343:2",effectID=690672,outputItemID=10027,effectBasePoints=1.0,castRecordID=39,spellMiscID=324132,castBaseMS=60000,castMinimumMS=30000},
    [12079]={abilityID=6610,name="Red Mageweave Bag",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=210,trivialHigh=240,numSkillUps=1,reagentRecordID=20192,reagents="4339:4,2604:2,8343:2",effectID=690426,outputItemID=10051,effectBasePoints=1.0,castRecordID=39,spellMiscID=323936,castBaseMS=60000,castMinimumMS=30000},
    [12082]={abilityID=6613,name="Shadoweave Boots",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=215,trivialHigh=245,numSkillUps=1,reagentRecordID=20116,reagents="4339:6,10285:6,8343:3,4304:2",effectID=689566,outputItemID=10031,effectBasePoints=1.0,castRecordID=39,spellMiscID=323224,castBaseMS=60000,castMinimumMS=30000},
    [12081]={abilityID=6612,name="Admiral's Hat",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=215,trivialHigh=245,numSkillUps=1,reagentRecordID=20096,reagents="4339:3,4589:6,8343:2",effectID=689435,outputItemID=10030,effectBasePoints=1.0,castRecordID=39,spellMiscID=323110,castBaseMS=60000,castMinimumMS=30000},
    [12088]={abilityID=6619,name="Cindercloth Boots",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=215,trivialHigh=245,numSkillUps=1,reagentRecordID=20097,reagents="4339:5,7077:1,8343:3,4304:2",effectID=689436,outputItemID=10044,effectBasePoints=1.0,castRecordID=39,spellMiscID=323111,castBaseMS=60000,castMinimumMS=30000},
    [12092]={abilityID=6623,name="Dreamweave Circlet",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=220,trivialHigh=250,numSkillUps=1,reagentRecordID=20162,reagents="4339:8,8153:4,10286:2,8343:3,6037:1,1529:1",effectID=690164,outputItemID=10041,effectBasePoints=1.0,castRecordID=39,spellMiscID=323712,castBaseMS=60000,castMinimumMS=30000},
    [18401]={abilityID=10396,name="Bolt of Runecloth",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=210,trivialHigh=215,numSkillUps=1,reagentRecordID=20559,reagents="14047:5",effectID=696812,outputItemID=14048,effectBasePoints=1.0,castRecordID=35,spellMiscID=329168,castBaseMS=12500,castMinimumMS=5000},
    [18402]={abilityID=10397,name="Runecloth Belt",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=225,trivialHigh=255,numSkillUps=1,reagentRecordID=20590,reagents="14048:3,14341:1",effectID=697096,outputItemID=13856,effectBasePoints=1.0,castRecordID=39,spellMiscID=329406,castBaseMS=60000,castMinimumMS=30000},
    [18403]={abilityID=10398,name="Frostweave Tunic",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=225,trivialHigh=255,numSkillUps=1,reagentRecordID=20591,reagents="14048:5,7079:2,14341:1",effectID=697097,outputItemID=13869,effectBasePoints=1.0,castRecordID=39,spellMiscID=329407,castBaseMS=60000,castMinimumMS=30000},
    [18404]={abilityID=10399,name="Frostweave Robe",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=225,trivialHigh=255,numSkillUps=1,reagentRecordID=20592,reagents="14048:5,7079:2,14341:1",effectID=697114,outputItemID=13868,effectBasePoints=1.0,castRecordID=39,spellMiscID=329421,castBaseMS=60000,castMinimumMS=30000},
    [18405]={abilityID=10401,name="Runecloth Bag",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=230,trivialHigh=260,numSkillUps=1,reagentRecordID=20551,reagents="14048:5,8170:2,14341:1,249430:4,249409:2",effectID=696745,outputItemID=14046,effectBasePoints=1.0,castRecordID=39,spellMiscID=329112,castBaseMS=60000,castMinimumMS=30000},
    [18406]={abilityID=10400,name="Runecloth Robe",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=230,trivialHigh=260,numSkillUps=1,reagentRecordID=20570,reagents="14048:5,14227:1,14341:1",effectID=696867,outputItemID=13858,effectBasePoints=1.0,castRecordID=39,spellMiscID=329215,castBaseMS=60000,castMinimumMS=30000},
    [18407]={abilityID=10402,name="Runecloth Tunic",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=230,trivialHigh=260,numSkillUps=1,reagentRecordID=20571,reagents="14048:5,14227:1,14341:1",effectID=696868,outputItemID=13857,effectBasePoints=1.0,castRecordID=39,spellMiscID=329216,castBaseMS=60000,castMinimumMS=30000},
    [18409]={abilityID=10404,name="Runecloth Cloak",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=240,trivialHigh=270,numSkillUps=1,reagentRecordID=20573,reagents="14048:4,14227:1,14341:1",effectID=696870,outputItemID=13860,effectBasePoints=1.0,castRecordID=39,spellMiscID=329218,castBaseMS=60000,castMinimumMS=30000},
    [18417]={abilityID=10412,name="Runecloth Gloves",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=245,trivialHigh=275,numSkillUps=1,reagentRecordID=20495,reagents="14048:4,8170:4,14341:1",effectID=696021,outputItemID=13863,effectBasePoints=1.0,castRecordID=39,spellMiscID=328523,castBaseMS=60000,castMinimumMS=30000,patternItemID=14481,patternRequiredSkill=230,patternProfessionID=197,patternLinkID=153847,patternEffectID=222883,patternTriggerType=6,patternRequiredLevel=0,patternMinFactionID=0,patternMinReputation=0,patternBonding=1},
    [18423]={abilityID=10420,name="Runecloth Boots",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=250,trivialHigh=280,numSkillUps=1,reagentRecordID=20490,reagents="14048:4,14227:2,8170:4,14341:1",effectID=695982,outputItemID=13864,effectBasePoints=1.0,castRecordID=39,spellMiscID=328492,castBaseMS=60000,castMinimumMS=30000,patternItemID=14488,patternRequiredSkill=235,patternProfessionID=197,patternLinkID=153853,patternEffectID=222889,patternTriggerType=6,patternRequiredLevel=0,patternMinFactionID=0,patternMinReputation=0,patternBonding=1},
    [27659]={abilityID=13812,name="Enchanted Runecloth Bag",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=245,trivialHigh=275,numSkillUps=1,reagentRecordID=20820,reagents="14048:5,16203:2,14341:2",effectID=701678,outputItemID=22248,effectBasePoints=1.0,castRecordID=39,spellMiscID=333044,castBaseMS=60000,castMinimumMS=30000,patternItemID=22308,patternRequiredSkill=230,patternProfessionID=197,patternLinkID=154207,patternEffectID=223243,patternTriggerType=6,patternRequiredLevel=0,patternMinFactionID=0,patternMinReputation=0,patternBonding=0},
    [18438]={abilityID=10425,name="Runecloth Pants",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=255,trivialHigh=285,numSkillUps=1,reagentRecordID=20483,reagents="14048:6,14227:2,14341:1",effectID=695905,outputItemID=13865,effectBasePoints=1.0,castRecordID=39,spellMiscID=328431,castBaseMS=60000,castMinimumMS=30000},
    [18444]={abilityID=10430,name="Runecloth Headband",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=265,trivialHigh=295,numSkillUps=1,reagentRecordID=20486,reagents="14048:4,14227:2,14341:1",effectID=695908,outputItemID=13866,effectBasePoints=1.0,castRecordID=39,spellMiscID=328434,castBaseMS=60000,castMinimumMS=30000},
    [18440]={abilityID=10427,name="Mooncloth Leggings",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=270,trivialHigh=300,numSkillUps=1,reagentRecordID=20484,reagents="14048:6,14342:4,14341:1",effectID=695906,outputItemID=14137,effectBasePoints=1.0,castRecordID=39,spellMiscID=328432,castBaseMS=60000,castMinimumMS=30000},
    [18451]={abilityID=10437,name="Felcloth Robe",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=275,trivialHigh=305,numSkillUps=1,reagentRecordID=20566,reagents="14048:8,14256:8,12662:4,14341:2",effectID=696859,outputItemID=14106,effectBasePoints=1.0,castRecordID=39,spellMiscID=329207,castBaseMS=60000,castMinimumMS=30000},
    [18560]={abilityID=10487,name="Mooncloth",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=270,trivialHigh=300,numSkillUps=1,reagentRecordID=20460,reagents="14256:2",effectID=695702,outputItemID=14342,effectBasePoints=1.0,castRecordID=39,spellMiscID=328262,castBaseMS=60000,castMinimumMS=30000},
    [1257472]={abilityID=55527,name="Earthenweave Boots",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=240,trivialHigh=270,numSkillUps=1,reagentRecordID=37098,reagents="14048:4,7076:2,8170:2,14341:1",effectID=1265366,outputItemID=254093,effectBasePoints=1.0,castRecordID=39,spellMiscID=811140,castBaseMS=60000,castMinimumMS=30000},
    [1257485]={abilityID=55540,name="Earthenweave Mantle",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=255,trivialHigh=285,numSkillUps=1,reagentRecordID=37111,reagents="14048:6,7076:1,14341:1",effectID=1265379,outputItemID=254119,effectBasePoints=1.0,castRecordID=39,spellMiscID=811153,castBaseMS=60000,castMinimumMS=30000},
    [1257488]={abilityID=55543,name="Earthenweave Leggings",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=260,trivialHigh=290,numSkillUps=1,reagentRecordID=37114,reagents="14048:6,7076:2,14341:1",effectID=1265382,outputItemID=254125,effectBasePoints=1.0,castRecordID=39,spellMiscID=811156,castBaseMS=60000,castMinimumMS=30000},
    [1257486]={abilityID=55541,name="Earthenweave Vest",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=265,trivialHigh=295,numSkillUps=1,reagentRecordID=37112,reagents="14048:8,7076:1,14341:1",effectID=1265380,outputItemID=254121,effectBasePoints=1.0,castRecordID=39,spellMiscID=811154,castBaseMS=60000,castMinimumMS=30000},
    [1257489]={abilityID=55544,name="Ghostweave Mantle",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=265,trivialHigh=295,numSkillUps=1,reagentRecordID=37115,reagents="14048:5,9210:3,14227:1,14341:1",effectID=1265383,outputItemID=254127,effectBasePoints=1.0,castRecordID=39,spellMiscID=811157,castBaseMS=60000,castMinimumMS=30000},
    [1257490]={abilityID=55545,name="Ghostweave Boots",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=265,trivialHigh=295,numSkillUps=1,reagentRecordID=37116,reagents="14048:4,9210:2,14227:1,8170:2,14341:1",effectID=1265384,outputItemID=254129,effectBasePoints=1.0,castRecordID=39,spellMiscID=811158,castBaseMS=60000,castMinimumMS=30000},
    [1257491]={abilityID=55546,name="Earthenweave Cuffs",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=270,trivialHigh=300,numSkillUps=1,reagentRecordID=37117,reagents="14048:5,7076:1,14341:1",effectID=1265385,outputItemID=254131,effectBasePoints=1.0,castRecordID=39,spellMiscID=811159,castBaseMS=60000,castMinimumMS=30000},
    [1257493]={abilityID=55548,name="Ghostweave Hood",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=275,trivialHigh=305,numSkillUps=1,reagentRecordID=37119,reagents="14048:6,9210:3,14227:2,14341:1",effectID=1265387,outputItemID=254135,effectBasePoints=1.0,castRecordID=39,spellMiscID=811161,castBaseMS=60000,castMinimumMS=30000},
    [1257494]={abilityID=55549,name="Earthenweave Crown",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=275,trivialHigh=305,numSkillUps=1,reagentRecordID=37120,reagents="14048:6,7076:3,14341:1",effectID=1265388,outputItemID=254137,effectBasePoints=1.0,castRecordID=39,spellMiscID=811162,castBaseMS=60000,castMinimumMS=30000},
    [1257487]={abilityID=55542,name="Runecloth Cuffs",skillLineID=197,skillupSkillLineID=2948,minSkillLineRank=1,trivialLow=265,trivialHigh=295,numSkillUps=1,reagentRecordID=37113,reagents="14048:5,14227:1,14341:1",effectID=1265381,outputItemID=254123,effectBasePoints=1.0,castRecordID=39,spellMiscID=811155,castBaseMS=60000,castMinimumMS=30000},
    },pattern4292={itemID=4292,requiredSkill=197,requiredSkillRank=75,
        useSpellID=402265,relatedRecipeID=3758,useItemEffectID=97731,recipeItemEffectID=222386,
        useTriggerType=0,recipeTriggerType=6,recipeMinimumStatus="UNKNOWN",nativeDispatchAllowed=false},
    rankLinks={[3908]=1240953,[3909]=1240964},
    fieldLimits={minimum="NOT_RECIPE_LEARNING_MINIMUM",green="UNKNOWN_FROM_DB2",
        yield="EFFECT_BASE_POINTS_NOT_SCHEMATIC_YIELD",rankCap="RUNTIME_OBSERVATION_REQUIRED"}}
-- END GENERATED DB2 70532 TAILORING
