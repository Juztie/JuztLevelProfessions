local _, JLP = ...

-- Static external-reference output yields captured from Wowhead's Forever
-- spell pages. These records are intentionally weaker than live current-build
-- observations. They are safe for dependency analysis, never by themselves for
-- Planner authority or material purchasing decisions.
local EVIDENCE = "wowhead-forever-output-yield-2026-10-05"

local function row(spellID, recipe, quantity, slug, reviewedAt)
    return {
        spellID = spellID,
        recipe = recipe,
        outputQuantity = quantity,
        outputMin = quantity,
        outputMax = quantity,
        fixed = true,
        evidence = reviewedAt and ("wowhead-forever-output-yield-"..reviewedAt) or EVIDENCE,
        sourceReviewedAt = reviewedAt or "2026-10-05",
        source = "wowhead-forever-spell",
        sourcePath = string.format("/forever/spell=%d/%s", spellID, slug),
        sourceBuildFamily = "Forever",
        externalVerified = true,
        liveVerified = false,
        dependencyQuantityEligible = true,
        plannerEligible = false,
    }
end

-- Explicit user product contract (2026-10-25), supported by ForeverTalent.
-- This is expected item output, never skill gain, observed stock or native permission.
local function productRow(id,name,slug,outputID,inputID,inputQuantity,prior)
    local r=row(id,name,1,slug,"2026-10-25")
    r.source="user-product-contract+forevertalent"
    r.sourceURL="https://wowforevertalent.com/professions/tailoring/"
    r.evidence="USER_FIXED_TAILORING_OUTPUT_2026_10_25"
    r.productFixedOutput=true;r.expectedOutputQuantity=1;r.outputItemID=outputID
    r.priorReferenceOutput=prior;r.inputItemID=inputID;r.inputQuantity=inputQuantity
    r.inputEvidence="DB2_70532_SPELLREAGENTS";r.inputSourceBuild=70532
    r.requiresConflictReview=true
    r.readOnly=true;r.nativeDispatchAllowed=false
    return r
end

JLP.data.recipeOutputYields = {
    contract = "forever-recipe-output-yield-reference-v1",
    evidence = EVIDENCE,
    sourceMetadata = {
        provider = "Wowhead Forever",
        authority = "external-reference",
        capturedAt = "2026-10-05",
        game = "Forever",
        -- The external page is a Forever-family reference captured while the
        -- project target client was build 70009. Wowhead does not expose this
        -- as a build-pinned contract, so a later live client build must
        -- corroborate the reference before dependency quantities may reuse it.
        capturedAgainstBuild = 70009,
        buildPinned = false,
        plannerEligible = false,
    },
    latestSourceReview="2026-10-24",
    recipes = {
        -- P0-224: exact high-range external yields, distinct from DB70450 effect bases.
        ["Heavy Mithril Breastplate"] = row(9959, "Heavy Mithril Breastplate", 2, "heavy-mithril-breastplate", "2026-10-24"),
        ["Cured Rugged Hide"] = row(19047, "Cured Rugged Hide", 3, "cured-rugged-hide", "2026-10-24"),
        -- P0-222: external fixed output (2) differs from DB70450 effect base (1).
        ["Heavy Copper Maul"] = row(7408, "Heavy Copper Maul", 2, "heavy-copper-maul", "2026-10-24"),
        -- P0-216: individual Forever spell pages. Historical effect bases differ.
        ["Elixir of Agility"] = row(11449, "Elixir of Agility", 2, "elixir-of-agility", "2026-10-24"),
        ["Solid Grinding Stone"] = row(9920, "Solid Grinding Stone", 2, "solid-grinding-stone", "2026-10-24"),
        ["Dense Blasting Powder"] = row(19788, "Dense Blasting Powder", 2, "dense-blasting-powder", "2026-10-24"),
        ["Cured Heavy Hide"] = row(3818, "Cured Heavy Hide", 2, "cured-heavy-hide", "2026-10-24"),
        -- P0-215: individually checked current Forever fixed outputs; DB70450
        -- historical CreateItem base=1/2 is not current output authority.
        ["Blackmouth Oil"] = row(7836, "Blackmouth Oil", 2, "blackmouth-oil", "2026-10-24"),
        ["Rough Bronze Leggings"] = row(2668, "Rough Bronze Leggings", 2, "rough-bronze-leggings", "2026-10-24"),
        ["Small Bronze Bomb"] = row(3941, "Small Bronze Bomb", 3, "small-bronze-bomb", "2026-10-24"),
        ["Embossed Leather Pants"] = row(3759, "Embossed Leather Pants", 2, "embossed-leather-pants", "2026-10-24"),
        -- P0-213: independently reviewed Forever fixed outputs, not observed live.
        ["Elixir of Wisdom"] = row(3171, "Elixir of Wisdom", 2, "elixir-of-wisdom"),
        ["Copper Chain Belt"] = row(2661, "Copper Chain Belt", 2, "copper-chain-belt"),
        ["Rough Copper Bomb"] = row(3923, "Rough Copper Bomb", 3, "rough-copper-bomb"),
        ["Big Bronze Bomb"] = row(3950, "Big Bronze Bomb", 4, "big-bronze-bomb"),
        ["Crafted Heavy Shot"] = row(3930, "Crafted Heavy Shot", 201, "crafted-heavy-shot"),
        ["Handstitched Leather Boots"] = row(2149, "Handstitched Leather Boots", 2, "handstitched-leather-boots"),
        ["Embossed Leather Gloves"] = row(3756, "Embossed Leather Gloves", 2, "embossed-leather-gloves"),
        -- P0-212 individual Forever spell pages, separate from DB70450 effects.
        ["Minor Mana Potion"] = row(2331, "Minor Mana Potion", 2, "minor-mana-potion"),
        ["Elixir of Minor Fortitude"] = row(2334, "Elixir of Minor Fortitude", 2, "elixir-of-minor-fortitude"),
        ["Minor Troll's Blood Elixir"] = row(3170, "Minor Troll's Blood Elixir", 2, "minor-trolls-blood-elixir"),
        ["Rough Bronze Shoulders"] = row(3328, "Rough Bronze Shoulders", 2, "rough-bronze-shoulders"),
        ["Light Armor Kit"] = row(2152, "Light Armor Kit", 2, "light-armor-kit"),
        -- Blacksmithing intermediates.
        ["Rough Grinding Stone"] = row(3320, "Rough Grinding Stone", 2, "rough-grinding-stone"),
        -- P0-202: independently checked on the corresponding Wowhead Forever
        -- spell pages, with exact DB70450 SpellID/output-item/reagent parity.
        ["Coarse Grinding Stone"] = row(3326, "Coarse Grinding Stone", 2, "coarse-grinding-stone"),
        ["Heavy Grinding Stone"] = row(3337, "Heavy Grinding Stone", 2, "heavy-grinding-stone"),
        ["Elixir of Minor Defense"] = row(7183, "Elixir of Minor Defense", 2, "elixir-of-minor-defense"),
        ["Cured Light Hide"] = row(3816, "Cured Light Hide", 2, "cured-light-hide"),
        -- P0-203: six further individual Forever spell pages show exact
        -- output counts and reagents. DB70450 validates itemID/ingredients;
        -- no source below is a live observation or native permission.
        ["Linen Bandage"] = row(3275, "Linen Bandage", 2, "linen-bandage"),
        ["Spiced Wolf Meat"] = row(2539, "Spiced Wolf Meat", 2, "spiced-wolf-meat"),
        ["Coarse Sharpening Stone"] = row(2665, "Coarse Sharpening Stone", 2, "coarse-sharpening-stone"),

        -- Enchanting retained tools. Forever changes several rod outputs versus
        -- common Classic assumptions, so keep them explicit.
        ["Runed Copper Rod"] = row(7421, "Runed Copper Rod", 2, "runed-copper-rod"),
        ["Runed Silver Rod"] = row(7795, "Runed Silver Rod", 2, "runed-silver-rod"),
        ["Runed Golden Rod"] = row(13628, "Runed Golden Rod", 2, "runed-golden-rod"),
        ["Runed Truesilver Rod"] = row(13702, "Runed Truesilver Rod", 1, "runed-truesilver-rod"),

        -- Engineering intermediates.
        ["Rough Blasting Powder"] = row(3918, "Rough Blasting Powder", 2, "rough-blasting-powder"),
        ["Handful of Copper Bolts"] = row(3922, "Handful of Copper Bolts", 2, "handful-of-copper-bolts"),
        ["Copper Tube"] = row(3924, "Copper Tube", 2, "copper-tube"),
        ["Coarse Blasting Powder"] = row(3929, "Coarse Blasting Powder", 2, "coarse-blasting-powder"),
        ["Whirring Bronze Gizmo"] = row(3942, "Whirring Bronze Gizmo", 2, "whirring-bronze-gizmo"),
        ["Heavy Blasting Powder"] = row(3945, "Heavy Blasting Powder", 2, "heavy-blasting-powder"),
        ["Bronze Framework"] = row(3953, "Bronze Framework", 2, "bronze-framework"),
        ["Silver Contact"] = row(3973, "Silver Contact", 6, "silver-contact"),
        ["Solid Blasting Powder"] = row(12585, "Solid Blasting Powder", 1, "solid-blasting-powder"),
        ["Unstable Trigger"] = row(12591, "Unstable Trigger", 2, "unstable-trigger"),
        -- P0-205 exact First Aid public spell output references (not live receipts).
        ["Heavy Linen Bandage"] = row(3276, "Heavy Linen Bandage", 2, "heavy-linen-bandage"),
        ["Heavy Wool Bandage"] = row(3278, "Heavy Wool Bandage", 2, "heavy-wool-bandage"),
        ["Silk Bandage"] = row(7928, "Silk Bandage", 2, "silk-bandage"),
        ["Heavy Silk Bandage"] = row(7929, "Heavy Silk Bandage", 2, "heavy-silk-bandage"),
        ["Mageweave Bandage"] = row(10840, "Mageweave Bandage", 2, "mageweave-bandage"),
        ["Runecloth Bandage"] = row(18629, "Runecloth Bandage", 2, "runecloth-bandage"),
        ["Heavy Runecloth Bandage"] = row(18630, "Heavy Runecloth Bandage", 2, "heavy-runecloth-bandage"),
        ["Minor Healing Potion"] = row(1244431, "Minor Healing Potion", 2, "minor-healing-potion"),
        ["Lesser Healing Potion"] = row(1244432, "Lesser Healing Potion", 2, "lesser-healing-potion"),
        ["Healing Potion"] = row(1244433, "Healing Potion", 2, "healing-potion"),
        -- P0-204: Forever spell page produces one casing; legacy reference said two.
        ["Mithril Casing"] = row(12599, "Mithril Casing", 1, "mithril-casing"),

        -- Leatherworking intermediates.
        ["Light Leather"] = row(2881, "Light Leather", 2, "light-leather"),
        ["Cured Medium Hide"] = row(3817, "Cured Medium Hide", 2, "cured-medium-hide"),

        -- Supersedes the older public output2 references for these six spells.
        -- Basepoints alone remain insufficient; expected quantity1 is user policy.
        ["Bolt of Linen Cloth"] = productRow(2963, "Bolt of Linen Cloth", "bolt-of-linen-cloth", 2996, 2589, 2, 2),
        ["Bolt of Woolen Cloth"] = productRow(2964, "Bolt of Woolen Cloth", "bolt-of-woolen-cloth", 2997, 2592, 3, 2),
        ["Bolt of Silk Cloth"] = productRow(3839, "Bolt of Silk Cloth", "bolt-of-silk-cloth", 4305, 4306, 4, 2),
        ["Bolt of Mageweave"] = productRow(3865, "Bolt of Mageweave", "bolt-of-mageweave", 4339, 4338, 5, 2),
        -- Runecloth follows the same explicit fixed product contract.
        ["Bolt of Runecloth"] = productRow(18401, "Bolt of Runecloth", "bolt-of-runecloth", 14048, 14047, 5, 2),
        ["Mooncloth"] = productRow(18560,"Mooncloth","mooncloth",14342,14256,2,nil),
    },
}
