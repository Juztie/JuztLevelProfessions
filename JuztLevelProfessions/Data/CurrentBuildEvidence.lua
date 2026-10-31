local _, JLP = ...

-- Declarative current-build evidence. Core policy must not own profession-specific
-- recipe/material rows. Rows are immutable release evidence and are matched against
-- the active dataset by stable recipeID + exact reagent itemID/quantity pairs.
local function rows(...)
    return {...}
end

local function ev(recipeID, materials, sourceKey, note, extra)
    local parts = {}
    for _, material in ipairs(materials or {}) do
        parts[#parts+1] = tostring(material[1]) .. "x" .. tostring(material[2])
    end
    table.sort(parts)
    local row = {
        recipeID = recipeID,
        materials = materials,
        sourceKey = sourceKey,
        capturedBuild = 70245,
        evidenceKey = tostring(recipeID) .. ":" .. table.concat(parts, ","),
        note = note,
    }
    for k, v in pairs(type(extra) == "table" and extra or {}) do row[k] = v end
    return row
end

JLP.data.currentBuildEvidence = {
    contract = "current-build-evidence-registry-v1",
    targetBuild = 70245,
    capturedAt = "2026-10-07",
    sources = {
        wowheadTailoring = {kind="public-db", url="https://www.wowhead.com/forever/skill=197/tailoring"},
        wowheadAlchemy = {kind="public-db", url="https://www.wowhead.com/forever/skill=171/alchemy"},
        wowheadEnchanting = {kind="public-db", url="https://www.wowhead.com/forever/skill=333/enchanting"},
        foreverDiff = {kind="client-db", url="https://foreverdiff.com/", build=70245},
    },
    professions = {
        TAILORING = {
            validationBasis = "WOWHEAD_FOREVER",
            contract = "profession-current-build-evidence-v1",
            build = 70245,
            sourceBuild = 70009,
            policy = {requirePublicComplete=true, requireTrainerContract=true, requireRouteAccessMetadata=true, requireAccessReferenceResolved=true, },
            publicComplete = true,
            rows = rows(
                ev(2963,  {{2589,2}}, "wowheadTailoring", "Bolt of Linen Cloth"),
                ev(12044, {{2996,1},{2320,1}}, "wowheadTailoring", "Simple Linen Pants"),
                ev(8776,  {{2996,1},{2320,1}}, "wowheadTailoring", "Linen Belt"),
                ev(12046, {{2996,4},{2321,1}}, "wowheadTailoring", "Simple Kilt"),
                ev(2402,  {{2997,1},{2321,1}}, "wowheadTailoring", "Woolen Cape"),
                ev(2399,  {{2997,2},{2321,2},{2605,1}}, "wowheadTailoring", "Green Woolen Vest"),
                ev(3848,  {{2997,3},{2321,2}}, "wowheadTailoring", "Double-stitched Woolen Shoulders"),
                ev(8762,  {{4305,3},{2321,2}}, "wowheadTailoring", "Silk Headband"),
                ev(3852,  {{2997,4},{2321,3},{3383,1}}, "wowheadTailoring", "Gloves of Meditation"),
                ev(3871,  {{4305,3},{2324,2},{2321,1}}, "wowheadTailoring", "Formal White Shirt"),
                ev(3813,  {{4305,3},{4234,2},{2321,3}}, "wowheadTailoring", "Small Silk Pack"),
                ev(8786,  {{4305,3},{6260,2},{2321,2}}, "wowheadTailoring", "Azure Silk Cloak"),
                ev(8791,  {{4305,4},{2604,2},{2321,2}}, "wowheadTailoring", "Crimson Silk Vest"),
                ev(8799,  {{4305,4},{2604,2},{4291,2}}, "wowheadTailoring", "Crimson Silk Pantaloons"),
                ev(12053, {{4339,2},{8343,2}}, "wowheadTailoring", "Black Mageweave Gloves"),
                ev(12072, {{4339,3},{8343,2}}, "wowheadTailoring", "Black Mageweave Headband"),
                ev(18402, {{14048,3},{14341,1}}, "wowheadTailoring", "Runecloth Belt"),
                ev(18420, {{14048,4},{3577,2},{14341,1}}, "wowheadTailoring", "Brightcloth Cloak"),
                ev(18438, {{14048,6},{14227,2},{14341,1}}, "wowheadTailoring", "Runecloth Pants"),
                ev(18560, {{14256,2}}, "wowheadTailoring", "Mooncloth"),
                ev(22902, {{14048,6},{14342,4},{13926,2},{14341,2}}, "wowheadTailoring", "Mooncloth Robe")
            ),
            notes = {
                "21/21 public current Forever recipe reagent rows captured; optional client snapshot comparison is available but not required.",
                "Public web evidence is not native execution authority and does not rewrite sourceBuild=70009 provenance."
            },
        },
        ENCHANTING = {
            validationBasis = "WOWHEAD_FOREVER",
            contract = "profession-current-build-evidence-v1",
            build = 70245,
            sourceBuild = 70009,
            policy = {requirePublicComplete=true, requireTrainerContract=true, requireRouteAccessMetadata=true, requireAccessReferenceResolved=true, requirePublicToolAndTarget=true},
            publicComplete = true,
            rows = rows(
                ev(7418,  {{247786,1}}, "wowheadEnchanting", "Enchant Bracer - Inferior Stamina", {requiredToolItemID=6218, targetSlot="BRACERS"}),
                ev(7420,  {{10940,1}}, "wowheadEnchanting", "Enchant Chest - Inferior Stamina", {requiredToolItemID=6218, targetSlot="CHEST"}),
                ev(7771,  {{10940,2}}, "wowheadEnchanting", "Enchant Cloak - Minor Protection", {requiredToolItemID=6218, targetSlot="CLOAK"}),
                ev(13501, {{11083,1}}, "wowheadEnchanting", "Enchant Bracer - Lesser Stamina", {requiredToolItemID=6339, targetSlot="BRACERS"}),
                ev(13661, {{11137,1}}, "wowheadEnchanting", "Enchant Bracer - Strength", {requiredToolItemID=11130, targetSlot="BRACERS"}),
                ev(13815, {{11137,1}}, "wowheadEnchanting", "Enchant Gloves - Agility", {requiredToolItemID=11145, targetSlot="GLOVES"}),
                ev(13939, {{11176,1},{11174,2}}, "wowheadEnchanting", "Enchant Bracer - Greater Strength", {requiredToolItemID=11145, targetSlot="BRACERS"}),
                ev(20017, {{11176,6}}, "wowheadEnchanting", "Enchant Shield - Greater Stamina", {requiredToolItemID=11145, targetSlot="SHIELD"})
            ),
            notes = {
                "8/8 public current Forever recipe reagent rows, rod requirements and target-slot semantics captured.",
                "Runed rod hierarchy remains independently enforced by EnchantingToolResolver; client schematic comparison is optional and does not gate dataset reference qualification."
            },
        },
        ALCHEMY = {
            validationBasis = "WOWHEAD_FOREVER",
            contract = "profession-current-build-evidence-v1",
            build = 70245,
            sourceBuild = 70245,
            policy = {requirePublicComplete=true, requireTrainerContract=true, requireRouteAccessMetadata=true, requireAccessReferenceResolved=true, },
            publicComplete = true,
            rows = rows(
                ev(1245246, {{2447,1},{3371,1}}, "wowheadAlchemy", "Minor Arcane Elixir"),
                ev(7183, {{765,1},{2447,1},{3371,1}}, "wowheadAlchemy", "Elixir of Minor Defense"),
                ev(3170, {{2447,1},{2449,2},{3371,1}}, "wowheadAlchemy", "Minor Troll's Blood Elixir"),
                ev(2331, {{785,1},{2447,1},{3371,1}}, "wowheadAlchemy", "Minor Mana Potion"),
                ev(2334, {{2449,2},{2447,1},{3371,1}}, "wowheadAlchemy", "Elixir of Minor Fortitude"),
                ev(3171, {{785,1},{2450,2},{3371,1}}, "wowheadAlchemy", "Elixir of Wisdom"),
                ev(3173, {{785,1},{3820,1},{3371,1}}, "wowheadAlchemy", "Lesser Mana Potion"),
                ev(3176, {{2453,2},{2450,2},{3372,1}}, "wowheadAlchemy", "Lesser Troll's Blood Elixir"),
                ev(11449, {{3820,1},{3821,1},{3372,1}}, "wowheadAlchemy", "Elixir of Agility"),
                ev(11450, {{3355,1},{3821,1},{3372,1}}, "wowheadAlchemy", "Elixir of Defense"),
                ev(11460, {{8836,1},{8925,1}}, "wowheadAlchemy", "Draught of Detect Undead"),
                ev(11467, {{8838,1},{3821,1},{8925,1}}, "wowheadAlchemy", "Elixir of Greater Agility"),
                ev(17553, {{8838,2},{8839,2},{8925,1}}, "wowheadAlchemy", "Superior Mana Potion")
            ),
        },
    },
}
