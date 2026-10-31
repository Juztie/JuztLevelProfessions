local _, JLP = ...
-- Curated Forever spell output yields. Output ID and yield are independent of
-- historical estimated craft counts and never authorize native crafting.
-- IDs/quantities cross-checked against the corresponding Forever spell pages.
JLP.data.foreverIntermediateOutputs={
    contract="forever-intermediate-output-evidence-v1",build=70245,
    source="wowhead-forever",nativeDispatchAllowed=false,
    rows={
        {professionKey="TAILORING",recipeID=18560,outputItemID=14342,outputName="Mooncloth",outputQuantity=1,
            outputAuthority="USER_FIXED_TAILORING_OUTPUT_2026_10_25"},
        {professionKey="ALCHEMY",recipeID=7183,outputItemID=5997,outputName="Elixir of Minor Defense",outputQuantity=2},
        {professionKey="BLACKSMITHING",recipeID=3320,outputItemID=3470,outputName="Rough Grinding Stone",outputQuantity=2},
        -- P0-224: high-skill conditional chains with exact Forever/direct-DB parity.
        {professionKey="BLACKSMITHING",recipeID=9959,outputItemID=7930,outputName="Heavy Mithril Breastplate",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="LEATHERWORKING",recipeID=19047,outputItemID=15407,outputName="Cured Rugged Hide",outputQuantity=3,requiresPrimarySourceParity=true},
        -- P0-222: conditional reference for a finished product; not actually owned stock.
        {professionKey="BLACKSMITHING",recipeID=7408,outputItemID=6214,outputName="Heavy Copper Maul",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="BLACKSMITHING",recipeID=3326,outputItemID=3478,outputName="Coarse Grinding Stone",outputQuantity=2},
        {professionKey="BLACKSMITHING",recipeID=3337,outputItemID=3486,outputName="Heavy Grinding Stone",outputQuantity=2},
        {professionKey="ENGINEERING",recipeID=3918,outputItemID=4357,outputName="Rough Blasting Powder",outputQuantity=2},
        {professionKey="ENGINEERING",recipeID=3929,outputItemID=4364,outputName="Coarse Blasting Powder",outputQuantity=2},
        {professionKey="ENGINEERING",recipeID=3922,outputItemID=4359,outputName="Handful of Copper Bolts",outputQuantity=2},
        {professionKey="LEATHERWORKING",recipeID=2881,outputItemID=2318,outputName="Light Leather",outputQuantity=2},
        {professionKey="LEATHERWORKING",recipeID=3816,outputItemID=4231,outputName="Cured Light Hide",outputQuantity=2},
        -- P0-204: individually matched Forever spell page output, profession,
        -- DB70450 CreateItem itemID, and exact immediate reagent list.
        -- These are conditional BOM edges; historical DB effect bases can differ.
        {professionKey="BLACKSMITHING",recipeID=9920,outputItemID=7966,outputName="Solid Grinding Stone",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="ENGINEERING",recipeID=3924,outputItemID=4361,outputName="Copper Tube",outputQuantity=2},
        {professionKey="ENGINEERING",recipeID=3942,outputItemID=4375,outputName="Whirring Bronze Gizmo",outputQuantity=2},
        {professionKey="ENGINEERING",recipeID=3973,outputItemID=4404,outputName="Silver Contact",outputQuantity=6},
        {professionKey="ENGINEERING",recipeID=3945,outputItemID=4377,outputName="Heavy Blasting Powder",outputQuantity=2},
        {professionKey="ENGINEERING",recipeID=12591,outputItemID=10560,outputName="Unstable Trigger",outputQuantity=2},
        {professionKey="ENGINEERING",recipeID=12599,outputItemID=10561,outputName="Mithril Casing",outputQuantity=1},
        {professionKey="LEATHERWORKING",recipeID=3817,outputItemID=4233,outputName="Cured Medium Hide",outputQuantity=2},
        {professionKey="TAILORING",recipeID=3865,outputItemID=4339,outputName="Bolt of Mageweave",outputQuantity=1,outputAuthority="USER_FIXED_TAILORING_OUTPUT_2026_10_25"},
        {professionKey="TAILORING",recipeID=18401,outputItemID=14048,outputName="Bolt of Runecloth",outputQuantity=1,outputAuthority="USER_FIXED_TAILORING_OUTPUT_2026_10_25"},
        -- P0-205: First Aid high-confidence public spell + exact 70450 output and reagents.
        {professionKey="FIRST_AID",recipeID=3276,outputItemID=2581,outputName="Heavy Linen Bandage",outputQuantity=2},
        {professionKey="FIRST_AID",recipeID=3278,outputItemID=3531,outputName="Heavy Wool Bandage",outputQuantity=2},
        {professionKey="FIRST_AID",recipeID=7928,outputItemID=6450,outputName="Silk Bandage",outputQuantity=2},
        {professionKey="FIRST_AID",recipeID=7929,outputItemID=6451,outputName="Heavy Silk Bandage",outputQuantity=2},
        {professionKey="FIRST_AID",recipeID=10840,outputItemID=8544,outputName="Mageweave Bandage",outputQuantity=2},
        {professionKey="FIRST_AID",recipeID=18629,outputItemID=14529,outputName="Runecloth Bandage",outputQuantity=2},
        {professionKey="FIRST_AID",recipeID=18630,outputItemID=14530,outputName="Heavy Runecloth Bandage",outputQuantity=2},
        {professionKey="FIRST_AID",recipeID=1244431,outputItemID=118,outputName="Minor Healing Potion",outputQuantity=2},
        {professionKey="FIRST_AID",recipeID=1244432,outputItemID=858,outputName="Lesser Healing Potion",outputQuantity=2},
        {professionKey="FIRST_AID",recipeID=1244433,outputItemID=929,outputName="Healing Potion",outputQuantity=2},
        -- P0-216: four current individual Forever spell pages, strict field parity.
        {professionKey="ALCHEMY",recipeID=11449,outputItemID=8949,outputName="Elixir of Agility",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="ENGINEERING",recipeID=19788,outputItemID=15992,outputName="Dense Blasting Powder",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="LEATHERWORKING",recipeID=3818,outputItemID=4236,outputName="Cured Heavy Hide",outputQuantity=2,requiresPrimarySourceParity=true},
        -- P0-212: SpellID + exact Forever recipe name + source reagents are
        -- independently checked against DB70450 by CrossProfessionDependencyPlanner.
        {professionKey="ALCHEMY",recipeID=2331,outputItemID=2455,outputName="Minor Mana Potion",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="ALCHEMY",recipeID=2334,outputItemID=2458,outputName="Elixir of Minor Fortitude",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="ALCHEMY",recipeID=3170,outputItemID=3382,outputName="Minor Troll's Blood Elixir",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="BLACKSMITHING",recipeID=3328,outputItemID=3480,outputName="Rough Bronze Shoulders",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="ENGINEERING",recipeID=3953,outputItemID=4382,outputName="Bronze Framework",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="LEATHERWORKING",recipeID=2152,outputItemID=2304,outputName="Light Armor Kit",outputQuantity=2,requiresPrimarySourceParity=true},
        -- P0-213: source-pinned producer output; every field is independently joined to DB70450.
        {professionKey="ALCHEMY",recipeID=3171,outputItemID=3383,outputName="Elixir of Wisdom",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="BLACKSMITHING",recipeID=2661,outputItemID=2851,outputName="Copper Chain Belt",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="ENGINEERING",recipeID=3923,outputItemID=4360,outputName="Rough Copper Bomb",outputQuantity=3,requiresPrimarySourceParity=true},
        {professionKey="ENGINEERING",recipeID=3950,outputItemID=4380,outputName="Big Bronze Bomb",outputQuantity=4,requiresPrimarySourceParity=true},
        {professionKey="ENGINEERING",recipeID=3930,outputItemID=8068,outputName="Crafted Heavy Shot",outputQuantity=201,requiresPrimarySourceParity=true},
        {professionKey="LEATHERWORKING",recipeID=2149,outputItemID=2302,outputName="Handstitched Leather Boots",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="LEATHERWORKING",recipeID=3756,outputItemID=4239,outputName="Embossed Leather Gloves",outputQuantity=2,requiresPrimarySourceParity=true},
        -- P0-215: Forever output counts (not historical DB70450 effect bases),
        -- precise SpellID/output ID/reagents. Strict external parity required.
        {professionKey="ALCHEMY",recipeID=7836,outputItemID=6370,outputName="Blackmouth Oil",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="BLACKSMITHING",recipeID=2668,outputItemID=2865,outputName="Rough Bronze Leggings",outputQuantity=2,requiresPrimarySourceParity=true},
        {professionKey="ENGINEERING",recipeID=3941,outputItemID=4374,outputName="Small Bronze Bomb",outputQuantity=3,requiresPrimarySourceParity=true},
        {professionKey="LEATHERWORKING",recipeID=3759,outputItemID=4242,outputName="Embossed Leather Pants",outputQuantity=2,requiresPrimarySourceParity=true},
        -- Additional conditional source-pinned products; these include final
        -- consumables, not only reusable intermediate components.
        {professionKey="TAILORING",recipeID=2963,outputItemID=2996,outputName="Bolt of Linen Cloth",outputQuantity=1,outputAuthority="USER_FIXED_TAILORING_OUTPUT_2026_10_25"},
        {professionKey="TAILORING",recipeID=2964,outputItemID=2997,outputName="Bolt of Woolen Cloth",outputQuantity=1,outputAuthority="USER_FIXED_TAILORING_OUTPUT_2026_10_25"},
        {professionKey="TAILORING",recipeID=3839,outputItemID=4305,outputName="Bolt of Silk Cloth",outputQuantity=1,outputAuthority="USER_FIXED_TAILORING_OUTPUT_2026_10_25"},
        {professionKey="FIRST_AID",recipeID=3275,outputItemID=1251,outputName="Linen Bandage",outputQuantity=2},
        {professionKey="COOKING",recipeID=2539,outputItemID=2680,outputName="Spiced Wolf Meat",outputQuantity=2},
        {professionKey="BLACKSMITHING",recipeID=2665,outputItemID=2863,outputName="Coarse Sharpening Stone",outputQuantity=2},
    },
}
