local _, JLP = ...

-- External acquisition classifications for reagents used by the Horde profession
-- research routes. These records describe acquisition semantics, not guaranteed
-- market availability. `plannerSource` is the conservative source token used by
-- the existing Planner-compatible staging contract; `sourceClass` preserves the
-- richer origin (herbalism, mining, skinning, disenchanting, etc.).
-- External references are deliberately not build-pinned: after a Forever client
-- build change they must be revalidated before they can complete staging data.
local CAPTURED_BUILD = 70009
local MATERIALS = {}

local function key(name)
    local text = tostring(name or ""):lower()
    text = text:gsub("[%c%p%s]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function add(names, spec)
    for _, name in ipairs(names or {}) do
        local row = {}
        for k, v in pairs(spec or {}) do row[k] = v end
        row.name = name
        row.referenceEligible = spec and spec.referenceEligible ~= false or true
        MATERIALS[key(name)] = row
    end
end

-- Direct trade/vendor reagents. Exact vendor observations can later upgrade
-- these references to live current-build evidence.
add({
    "Black Dye", "Bleach", "Blue Dye", "Coarse Thread", "Crystal Vial",
    "Empty Vial", "Fine Thread", "Gray Dye", "Green Dye", "Heavy Silken Thread",
    "Leaded Vial", "Imbued Vial", "Mote of Magic", "Orange Dye", "Red Dye", "Rune Thread",
    "Salt", "Silken Thread", "Simple Wood", "Weak Flux", "Wooden Stock", "Copper Rod",
}, {
    sourceClass = "vendor",
    plannerSource = "vendor",
    acquisitionKinds = {"vendor", "auction"},
    evidence = "wowhead-forever-vendor-reference-2026-10-06",
    evidenceQuality = "external-forever-reference",
    plannerMapping = "direct-vendor",
})

-- Herbs have an explicit gathering origin. The Planner-compatible staging token
-- Exact Alchemy70532 reagent names/IDs are supplied by the existing material
-- catalogue. Fishing is an advisory option, never an assumed learned profession,
-- catch probability, coordinates, availability or credited future supply.
add({"Firefin Snapper", "Oily Blackmouth", "Stonescale Eel"}, {
    sourceClass="fishing-or-auction",plannerSource="auction",
    acquisitionKinds={"farm","auction"},gatheringProfession="Fishing",
    evidence="https://www.wow-professions.com/forever/alchemy-leveling-guide",
    evidenceQuality="FOREVER_FISH_REAGENT_REFERENCE_NOT_CATCH_DISTRIBUTION",
    plannerMapping="external-market-fallback",
})

-- Herbs have an explicit gathering origin. The Planner-compatible staging token
-- remains `auction` because the production Planner currently models external
-- market acquisition as auction; the richer farm origin is retained separately.
add({
    "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn",
    "Stranglekelp", "Bruiseweed", "Wild Steelbloom", "Goldthorn", "Purple Lotus",
    "Arthas' Tears", "Sungrass", "Blindweed",
}, {
    sourceClass = "herbalism-or-auction",
    plannerSource = "auction",
    acquisitionKinds = {"farm", "auction"},
    gatheringProfession = "Herbalism",
    evidence = "wowhead-forever-herbalism-overview-2026-10-06",
    evidenceQuality = "external-forever-reference",
    plannerMapping = "external-market-fallback",
})

add({"Rough Stone", "Coarse Stone", "Heavy Stone", "Solid Stone", "Dense Stone"}, {
    sourceClass = "mining-or-auction",
    plannerSource = "auction",
    acquisitionKinds = {"farm", "auction"},
    gatheringProfession = "Mining",
    evidence = "wowhead-forever-mining-reference-2026-10-06",
    evidenceQuality = "external-forever-reference",
    plannerMapping = "external-market-fallback",
})

add({"Copper Bar", "Bronze Bar", "Silver Bar", "Iron Bar", "Steel Bar", "Mithril Bar", "Thorium Bar"}, {
    sourceClass = "smelting-or-auction",
    plannerSource = "auction",
    acquisitionKinds = {"crafted", "farm", "auction"},
    productionProfession = "Mining",
    evidence = "wowhead-forever-mining-smelting-reference-2026-10-06",
    evidenceQuality = "external-forever-reference",
    plannerMapping = "external-market-fallback",
})

add({"Linen Cloth", "Wool Cloth", "Silk Cloth", "Mageweave Cloth", "Runecloth"}, {
    sourceClass = "drop-or-auction",
    plannerSource = "auction",
    acquisitionKinds = {"farm", "auction"},
    evidence = "wowhead-forever-cloth-source-reference-2026-10-06",
    evidenceQuality = "external-forever-reference",
    plannerMapping = "external-market-fallback",
})

add({
    "Ruined Leather Scraps", "Light Hide", "Medium Hide", "Heavy Hide",
    "Medium Leather", "Heavy Leather", "Thick Leather", "Rugged Leather",
}, {
    sourceClass = "skinning-or-auction",
    plannerSource = "auction",
    acquisitionKinds = {"farm", "auction"},
    gatheringProfession = "Skinning",
    evidence = "wowhead-forever-skinning-source-reference-2026-10-06",
    evidenceQuality = "external-forever-reference",
    plannerMapping = "external-market-fallback",
})

add({
    "Dream Dust", "Greater Astral Essence", "Greater Mystic Essence", "Illusion Dust",
    "Lesser Astral Essence", "Lesser Magic Essence", "Lesser Mystic Essence",
    "Lesser Nether Essence", "Soul Dust", "Strange Dust", "Vision Dust",
}, {
    sourceClass = "disenchant-or-auction",
    plannerSource = "disenchant-or-auction",
    acquisitionKinds = {"disenchant", "auction"},
    productionProfession = "Enchanting",
    evidence = "wowhead-forever-disenchant-reference-2026-10-06",
    evidenceQuality = "external-forever-reference",
    plannerMapping = "native-planner-source",
})

add({"Aquamarine", "Black Pearl", "Iridescent Pearl", "Shadowgem", "Star Ruby"}, {
    sourceClass = "world-source-or-auction",
    plannerSource = "auction",
    acquisitionKinds = {"farm", "auction"},
    evidence = "wowhead-forever-world-material-reference-2026-10-06",
    evidenceQuality = "external-forever-reference",
    plannerMapping = "external-market-fallback",
})

add({"Coarse Grinding Stone", "Heavy Grinding Stone", "Silver Rod", "Golden Rod", "Truesilver Rod"}, {
    sourceClass = "blacksmithing-or-auction",
    plannerSource = "auction",
    acquisitionKinds = {"crafted", "auction"},
    productionProfession = "Blacksmithing",
    evidence = "wowhead-forever-blacksmithing-component-reference-2026-10-06",
    evidenceQuality = "external-forever-reference",
    plannerMapping = "external-market-fallback",
})

-- The user-provided Tailoring research route lists Inscribed Leather Bracers as
-- a Crimson Silk Pantaloons reagent, while current Forever recipe data lists
-- Bolt of Silk Cloth, Red Dye and Silken Thread. Preserve the research source,
-- but explicitly refuse to classify this material until the route discrepancy is
-- reconciled instead of silently replacing the supplied route data.
MATERIALS[key("Inscribed Leather Bracers")] = {
    name = "Inscribed Leather Bracers",
    sourceClass = "research-reagent-conflict",
    plannerSource = nil,
    acquisitionKinds = {},
    evidence = "wowhead-forever-crimson-silk-pantaloons-reagent-conflict-2026-10-06",
    evidenceQuality = "external-forever-conflict",
    referenceEligible = false,
    conflict = true,
    conflictReason = "Horde Profession Information v2 lists Inscribed Leather Bracers; Forever Crimson Silk Pantaloons data lists Bolt of Silk Cloth, Red Dye and Silken Thread.",
}

-- Item IDs are supplied only where this layer needs direct merchant observation
-- and the Forever identity is explicit. Other item identities continue to come
-- from current-build material reconciliation/KnowledgeCache.
local ITEM_IDS = {
    ["black dye"] = 2325,
    ["blue dye"] = 6260,
    ["coarse thread"] = 2320,
    ["copper rod"] = 6217,
    ["crystal vial"] = 8925,
    ["empty vial"] = 3371,
    ["fine thread"] = 2321,
    ["heavy silken thread"] = 8343,
    ["leaded vial"] = 3372,
    ["mote of magic"] = 247786,
    ["red dye"] = 2604,
    ["rune thread"] = 14341,
    ["silken thread"] = 4291,
    ["simple wood"] = 4470,
    ["weak flux"] = 2880,
    ["wooden stock"] = 4399,
}
for normalized, itemID in pairs(ITEM_IDS) do
    if MATERIALS[normalized] then MATERIALS[normalized].itemID = itemID end
end

JLP.data.materialAcquisitionSources = {
    contract = "forever-material-acquisition-source-reference-v1",
    sourceMetadata = {
        id = "wowhead-forever-material-acquisition-2026-10-06",
        capturedAgainstBuild = CAPTURED_BUILD,
        buildPinned = false,
        authority = "external-reference-not-live-client-proof",
        references = {
            vendor = "Wowhead Forever item vendor locations",
            herbalism = "Wowhead Forever Herbalism profession overview",
            mining = "Wowhead Forever Mining/smelting profession overview",
            cloth = "Wowhead Forever cloth source catalogue",
            skinning = "Wowhead Forever item source records",
            disenchant = "Wowhead Forever Disenchant spell/material bands",
            crafted = "Wowhead Forever profession spell/item records",
        },
    },
    policy = {
        liveCurrentBuildWins = true,
        externalReferencesAreBuildScoped = true,
        unknownSourcesRemainUnresolved = true,
        plannerMarketFallbackDoesNotAssertAHStock = true,
    },
    materials = MATERIALS,
}

-- Compact field-qualified Forever vendor references, not current stock/prices or transport proof.
-- Full development provenance: Tools/SHARED_SUPPLY_VENDOR_FIELDS.json.
JLP.data.materialAcquisitionSources.vendors = {
 {["id"]="SUP_BORYA",["npcID"]=3364,["name"]="Borya",["faction"]="Horde",["zone"]="Orgrimmar",["mapID"]=1454,["x"]=0.631,["y"]=0.512,["mapDomain"]="UI_MAP_ID",["items"]={2325,2324,6260,2320,2321,4340,2605,8343,6261,10290,4342,2604,14341,4291,4341},["recipeItems"]={},["url"]="https://www.wow-professions.com/forever/npc/borya",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=3364",["fieldSHA256"]="9188e33c0f0687c8be331169561deadda4cd2e22b8b92a4d5d63e209a7ac6fd8"},
 {["id"]="SUP_SUMI",["npcID"]=3356,["name"]="Sumi",["faction"]="Horde",["zone"]="Orgrimmar",["mapID"]=1454,["x"]=0.825,["y"]=0.238,["mapDomain"]="UI_MAP_ID",["items"]={5956,3857,18567,2901,3466,2880},["recipeItems"]={},["url"]="https://www.wow-professions.com/forever/npc/sumi",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=3356",["fieldSHA256"]="9061a1919e62bcbba3b1a110abb14e12749a148b506feea92288ac0f2da058ad"},
 {["id"]="SUP_KITHAS",["npcID"]=3346,["name"]="Kithas",["faction"]="Horde",["zone"]="Orgrimmar",["mapID"]=1454,["x"]=0.537,["y"]=0.381,["mapDomain"]="UI_MAP_ID",["items"]={6217,247786,4470,11291},["recipeItems"]={20758,6342,6349,20752,20753,22307},["url"]="https://www.wow-professions.com/forever/npc/kithas",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=3346",["fieldSHA256"]="da4976d511ffc62a8b0fbb9569ea26c16779d439cb14c3c5a49f75f700854898"},
 {["id"]="SUP_SOVIK",["npcID"]=3413,["name"]="Sovik",["faction"]="Horde",["zone"]="Orgrimmar",["mapID"]=1454,["x"]=0.756,["y"]=0.252,["mapDomain"]="UI_MAP_ID",["items"]={5956,4400,2901,3466,2880,4399},["recipeItems"]={16042},["url"]="https://www.wow-professions.com/forever/npc/sovik",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=3413",["fieldSHA256"]="3f060e14715c71a9286cd8c3d248f85a2a791c87ce0f6a24135c5e190053efcb"},
 {["id"]="SUP_QIA",["npcID"]=11189,["name"]="Qia",["faction"]="Neutral",["zone"]="Winterspring",["mapID"]=1452,["x"]=0.612,["y"]=0.372,["mapDomain"]="UI_MAP_ID",["items"]={2325,3857,2320,6217,8925,3371,2321,4340,8343,4400,3372,2901,4342,2604,4289,4291,7005,3466,2880,4399,4341},["recipeItems"]={14481},["url"]="https://www.wow-professions.com/forever/npc/qia",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=11189",["externalPositionVariant"]={["x"]=0.612,["y"]=0.372,["url"]="https://www.wow-professions.com/forever/npc/qia",["evidence"]="EXTERNAL_FOREVER_REFERENCE_CORROBORATES_USER_POSITION"},["geographyOrigin"]="USER_PROJECT_POSITION_2026_10_26_REV2",["fieldSHA256"]="936a85e8193b3d6fd6014c3110da12f715a8fed36389e12082c93b9859178ccf"},
 {["id"]="SUP_DARNALL",["npcID"]=7940,["name"]="Darnall",["faction"]="Neutral",["zone"]="Moonglade",["mapID"]=1450,["x"]=0.516,["y"]=0.336,["mapDomain"]="UI_MAP_ID",["items"]={2325,2324,6260,2320,2321,4340,2605,8343,6261,10290,4342,2604,14341,4291,4341},["recipeItems"]={14488,14480,14484},["url"]="https://www.wow-professions.com/forever/npc/darnall",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=7940/darnall",["identityEvidence"]="BROWSER_H1_DARNALL_TAILORING_SUPPLIES_2026_10_26_PLUS_EXISTING_70532_PATTERN_SOURCE",["externalPositionVariant"]={["x"]=0.515,["y"]=0.332,["url"]="https://www.wow-professions.com/forever/npc/darnall",["evidence"]="EXTERNAL_FOREVER_REFERENCE_NOT_CANONICAL_USER_POSITION"},["geographyOrigin"]="USER_PROJECT_POSITION_2026_10_26_REV2",["fieldSHA256"]="165d90e1443f4186eaac880c557492d54b306e999d10dec1efa58353f38aaadc"},
 {["id"]="SUP_ALGERNON",["npcID"]=4610,["name"]="Algernon",["faction"]="Horde",["zone"]="Undercity",["mapID"]=1458,["x"]=0.517,["y"]=0.747,["mapDomain"]="UI_MAP_ID",["items"]={8925,3371,18256,3372},["recipeItems"]={9301,13477},["url"]="https://www.wow-professions.com/forever/npc/algernon",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=4610",["fieldSHA256"]="9216b9d632dbd0cdbd8481886b409cbf7573127e7235ec5cf7b1caf25bab9290"},
 {["id"]="SUP_LORELAE",["npcID"]=12022,["name"]="Lorelae Wintersong",["faction"]="Neutral",["zone"]="Moonglade",["mapID"]=1450,["x"]=0.483,["y"]=0.401,["mapDomain"]="UI_MAP_ID",["items"]={6217,3371,3372,4289,5956,3857,2320,2321,8343,4291,3466,2880,4399},["recipeItems"]={16243,14483},["url"]="https://www.wow-professions.com/forever/npc/lorelae-wintersong",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=12022",["fieldSHA256"]="241d104b5bb9520e7aa609e8dae8063a5ebb7919fa544fa7897fa67126854a18"},
 {["id"]="SUP_XIZZER",["npcID"]=11185,["name"]="Xizzer Fizzbolt",["faction"]="Neutral",["zone"]="Winterspring",["mapID"]=1452,["x"]=0.608,["y"]=0.386,["mapDomain"]="UI_MAP_ID",["items"]={5956,4400,2901,3466,2880,4399},["recipeItems"]={16047,16046,16050},["url"]="https://www.wow-professions.com/forever/npc/xizzer-fizzbolt",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=11185",["fieldSHA256"]="b129a14f96fc8b10c0eeecc8a9f172db09b23d9a15f41e95c023c9db968718c1"},
 {["id"]="SUP_DANIEL",["npcID"]=4561,["name"]="Daniel Bartlett",["faction"]="Horde",["zone"]="Undercity",["mapID"]=1458,["x"]=0.642,["y"]=0.376,["mapDomain"]="UI_MAP_ID",["items"]={2325,5956,2324,6260,3857,2320,6217,3371,2321,4340,2605,8343,4400,3372,2901,4342,2604,4289,4291,7005,3466,2880,4399,4341},["recipeItems"]={16217},["url"]="https://www.wow-professions.com/forever/npc/daniel-bartlett",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=4561",["fieldSHA256"]="9700c65c412734e4e4396683ac941f182f2c286661ea8cf4ced084252f42325c"},
 {["id"]="SUP_KANIA",["npcID"]=15419,["name"]="Kania",["faction"]="Neutral",["zone"]="Silithus",["mapID"]=1451,["x"]=0.52,["y"]=0.396,["mapDomain"]="UI_MAP_ID",["items"]={6217,247786,4470,11291},["recipeItems"]={20758,6342,20752,20753,20754,20755,22307,22308},["url"]="https://www.wow-professions.com/forever/npc/kania",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=15419",["fieldSHA256"]="637ee067a1475efb8975d600c245e06e14b9be1ca362256be59f94634d9f6f29"},
 {["id"]="SUP_MAGNUS",["npcID"]=11278,["name"]="Magnus Frostwake",["faction"]="Neutral",["zone"]="Western Plaguelands",["mapID"]=1422,["x"]=0.681,["y"]=0.776,["mapDomain"]="UI_MAP_ID",["items"]={},["recipeItems"]={13485,13501,8030,12819,12823,12703},["url"]="https://www.wow-professions.com/forever/npc/magnus-frostwake",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=11278",["accessNote"]="Spectral Essence from the Scholomance quest chain must be equipped to see this ghost; verify access before travelling. Geography is not quest completion or access.",["accessStatus"]="VERIFY_EQUIPPED_TRINKET_AND_QUEST_ACCESS",["fieldSHA256"]="7d9d7ebeee96a754c2d4111909e57d43ad7d757210ad7555e3224096480d761e"},
 {["id"]="SUP_GLYX",["npcID"]=2848,["name"]="Glyx Brewright",["faction"]="Neutral",["zone"]="Stranglethorn Vale",["mapID"]=1434,["x"]=0.281,["y"]=0.78,["mapDomain"]="UI_MAP_ID",["items"]={8925,3371,18256,3372},["recipeItems"]={6056,6057},["url"]="https://www.wow-professions.com/forever/npc/glyx-brewright",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=2848",["fieldSHA256"]="773862f1fd8cd7e311d2e5c6a286c08547db77e259a62b9704f216e170bfb7b5"},
 {["id"]="SUP_PESTLEZUGG",["npcID"]=5594,["name"]="Alchemist Pestlezugg",["faction"]="Neutral",["zone"]="Tanaris",["mapID"]=1446,["x"]=0.509,["y"]=0.27,["mapDomain"]="UI_MAP_ID",["items"]={8925,3371,18256,3372},["recipeItems"]={6057,9303,9304,9305,12958},["url"]="https://www.wow-professions.com/forever/npc/alchemist-pestlezugg",["accessed"]="2026-10-26",["evidence"]="FOREVER_EXTERNAL_PAGE_DOM_ITEM_LINKS_AND_INGAME_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=5594",["fieldSHA256"]="6536e72d2daf6896c131814c51469738825b998702ac865269a742fc8adbb5b0"},
 {["id"]="SUP_WERG",["npcID"]=12943,["name"]="Werg Thickblade",["faction"]="Horde",["zone"]="Tirisfal Glades",["mapID"]=1420,["x"]=0.832,["y"]=0.696,["mapDomain"]="UI_MAP_ID",["items"]={2320,2321,2325,2604,2605,4289,4291,4340,4341,4342,6260,6261,7005,8343,10290,14341},["recipeItems"]={15725},["url"]="https://www.wowhead.com/forever/npc=12943/werg-thickblade",["accessed"]="2026-10-26",["evidence"]="FOREVER_NPC_PAGE_RENDERED_SELLS_AND_MAP_PIN_NOT_LIVE",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["identityURL"]="https://www.wowhead.com/forever/npc=12943/werg-thickblade",["sourceAreaTableID"]=85,["mapAssignment70532"]=46730,["sourceMapID"]=0,["limitedSupplyReference"]={["itemID"]=15725,["displayedCount"]=1,["notCurrentStock"]=true},["mapProvenance"]="DOM map background Area85, pin83.2/69.6; DB2 UiMapAssignment46730 maps Area85 to UIMap1420",["fieldSHA256"]="6984a821491f05f4f83463a07e41d730f09cc27e18b78f6795dccd37d5a94422"}
}

-- BEGIN QUALIFIED CLOTH SUPPLY
JLP.data.materialAcquisitionSources.clothSupplies={{["id"]="CLOTH:3112:1",["npcID"]=3112,["name"]="Razormane Scout",["zone"]="Durotar",["mapID"]=1411,["x"]=0.4329,["y"]=0.5075999999999999,["itemIDs"]={2589},["relationURL"]="https://www.wowhead.com/forever/npc=3112/razormane-scout",["relationEvidence"]="FOREVER_INDEXED_DROP_RELATION_NOT_RATE",["positionURL"]="https://classicdb.ch/?npc=3112",["positionEvidence"]="CLASSIC_NORMALIZED_ZONE_REFERENCE_NOT_FOREVER_SPAWN",["positionAreaID"]=14,["mapBinding"]="EXPLICIT_ORIGINAL_70532_UI_MAP_ZONE_NAME_NOT_AREA_AS_UI",["sourceBuild"]=70532,["sourceQualifiedForAdvisory"]=true,["nativeDispatchAllowed"]=false,["notLiveSpawn"]=true,["notGuaranteedLoot"]=true},{["id"]="CLOTH:3112:2",["npcID"]=3112,["name"]="Razormane Scout",["zone"]="Durotar",["mapID"]=1411,["x"]=0.4449,["y"]=0.5067,["itemIDs"]={2589},["relationURL"]="https://www.wowhead.com/forever/npc=3112/razormane-scout",["relationEvidence"]="FOREVER_INDEXED_DROP_RELATION_NOT_RATE",["positionURL"]="https://classicdb.ch/?npc=3112",["positionEvidence"]="CLASSIC_NORMALIZED_ZONE_REFERENCE_NOT_FOREVER_SPAWN",["positionAreaID"]=14,["mapBinding"]="EXPLICIT_ORIGINAL_70532_UI_MAP_ZONE_NAME_NOT_AREA_AS_UI",["sourceBuild"]=70532,["sourceQualifiedForAdvisory"]=true,["nativeDispatchAllowed"]=false,["notLiveSpawn"]=true,["notGuaranteedLoot"]=true},{["id"]="CLOTH:3993:1",["npcID"]=3993,["name"]="Venture Co. Machine Smith",["zone"]="Stonetalon Mountains",["mapID"]=1442,["x"]=0.6275999999999999,["y"]=0.4032,["itemIDs"]={2592,4306},["relationURL"]="https://www.wowhead.com/forever/npc=3993/venture-co-machine-smith",["relationEvidence"]="FOREVER_INDEXED_DROP_RELATION_NOT_RATE",["positionURL"]="https://classicdb.ch/?npc=3993",["positionEvidence"]="CLASSIC_NORMALIZED_ZONE_REFERENCE_NOT_FOREVER_SPAWN",["positionAreaID"]=406,["mapBinding"]="EXPLICIT_ORIGINAL_70532_UI_MAP_ZONE_NAME_NOT_AREA_AS_UI",["sourceBuild"]=70532,["sourceQualifiedForAdvisory"]=true,["nativeDispatchAllowed"]=false,["notLiveSpawn"]=true,["notGuaranteedLoot"]=true},{["id"]="CLOTH:3993:2",["npcID"]=3993,["name"]="Venture Co. Machine Smith",["zone"]="Stonetalon Mountains",["mapID"]=1442,["x"]=0.6451,["y"]=0.3997,["itemIDs"]={2592,4306},["relationURL"]="https://www.wowhead.com/forever/npc=3993/venture-co-machine-smith",["relationEvidence"]="FOREVER_INDEXED_DROP_RELATION_NOT_RATE",["positionURL"]="https://classicdb.ch/?npc=3993",["positionEvidence"]="CLASSIC_NORMALIZED_ZONE_REFERENCE_NOT_FOREVER_SPAWN",["positionAreaID"]=406,["mapBinding"]="EXPLICIT_ORIGINAL_70532_UI_MAP_ZONE_NAME_NOT_AREA_AS_UI",["sourceBuild"]=70532,["sourceQualifiedForAdvisory"]=true,["nativeDispatchAllowed"]=false,["notLiveSpawn"]=true,["notGuaranteedLoot"]=true},{["id"]="CLOTH:5471:1",["npcID"]=5471,["name"]="Dunemaul Ogre",["zone"]="Tanaris",["mapID"]=1446,["x"]=0.396,["y"]=0.7489,["itemIDs"]={4338},["relationURL"]="https://metaforge.app/wow-forever/database/creatures/dunemaul-ogre",["relationEvidence"]="VMANGOS_REFERENCE_RELATION_NOT_FOREVER_TRANSACTION",["positionURL"]="https://classicdb.ch/?npc=5471",["positionEvidence"]="CLASSIC_NORMALIZED_ZONE_REFERENCE_NOT_FOREVER_SPAWN",["positionAreaID"]=440,["mapBinding"]="EXPLICIT_ORIGINAL_70532_UI_MAP_ZONE_NAME_NOT_AREA_AS_UI",["sourceBuild"]=70532,["sourceQualifiedForAdvisory"]=true,["nativeDispatchAllowed"]=false,["notLiveSpawn"]=true,["notGuaranteedLoot"]=true},{["id"]="CLOTH:5471:2",["npcID"]=5471,["name"]="Dunemaul Ogre",["zone"]="Tanaris",["mapID"]=1446,["x"]=0.3948,["y"]=0.7482,["itemIDs"]={4338},["relationURL"]="https://metaforge.app/wow-forever/database/creatures/dunemaul-ogre",["relationEvidence"]="VMANGOS_REFERENCE_RELATION_NOT_FOREVER_TRANSACTION",["positionURL"]="https://classicdb.ch/?npc=5471",["positionEvidence"]="CLASSIC_NORMALIZED_ZONE_REFERENCE_NOT_FOREVER_SPAWN",["positionAreaID"]=440,["mapBinding"]="EXPLICIT_ORIGINAL_70532_UI_MAP_ZONE_NAME_NOT_AREA_AS_UI",["sourceBuild"]=70532,["sourceQualifiedForAdvisory"]=true,["nativeDispatchAllowed"]=false,["notLiveSpawn"]=true,["notGuaranteedLoot"]=true},{["id"]="CLOTH:11880:1",["npcID"]=11880,["name"]="Twilight Avenger",["zone"]="Silithus",["mapID"]=1451,["x"]=0.41090000000000004,["y"]=0.449,["itemIDs"]={14047},["relationURL"]="https://metaforge.app/wow-forever/database/creatures/twilight-avenger",["relationEvidence"]="VMANGOS_REFERENCE_RELATION_NOT_FOREVER_TRANSACTION",["positionURL"]="https://wowbuddyguides.com/classic/database/zones/1377",["positionEvidence"]="CLASSIC_NORMALIZED_ZONE_REFERENCE_NOT_FOREVER_SPAWN",["positionAreaID"]=1377,["mapBinding"]="EXPLICIT_ORIGINAL_70532_UI_MAP_ZONE_NAME_NOT_AREA_AS_UI",["sourceBuild"]=70532,["sourceQualifiedForAdvisory"]=true,["nativeDispatchAllowed"]=false,["notLiveSpawn"]=true,["notGuaranteedLoot"]=true},{["id"]="CLOTH:11880:2",["npcID"]=11880,["name"]="Twilight Avenger",["zone"]="Silithus",["mapID"]=1451,["x"]=0.39880000000000004,["y"]=0.4416,["itemIDs"]={14047},["relationURL"]="https://metaforge.app/wow-forever/database/creatures/twilight-avenger",["relationEvidence"]="VMANGOS_REFERENCE_RELATION_NOT_FOREVER_TRANSACTION",["positionURL"]="https://wowbuddyguides.com/classic/database/zones/1377",["positionEvidence"]="CLASSIC_NORMALIZED_ZONE_REFERENCE_NOT_FOREVER_SPAWN",["positionAreaID"]=1377,["mapBinding"]="EXPLICIT_ORIGINAL_70532_UI_MAP_ZONE_NAME_NOT_AREA_AS_UI",["sourceBuild"]=70532,["sourceQualifiedForAdvisory"]=true,["nativeDispatchAllowed"]=false,["notLiveSpawn"]=true,["notGuaranteedLoot"]=true}}
-- END QUALIFIED CLOTH SUPPLY

-- BEGIN QUALIFIED SECONDARY SUPPLY
for _,r in ipairs({{["id"]="SUP_COOK_WULAN",["npcID"]=12033,["name"]="Wulan",["faction"]="Horde",["zone"]="Desolace",["mapID"]=1443,["x"]=0.262,["y"]=0.698,["items"]={159,2678,2692,3713},["recipeItems"]={16072,17062,6369},["url"]="https://www.wow-professions.com/forever/npc/wulan",["geographyOrigin"]="EXISTING_FOREVER_GUIDE_ADVISORY_GEOGRAPHY_NOT_LIVE_ACCESS",["mapDomain"]="UI_MAP_ID",["accessed"]="2026-10-26",["evidence"]="FOREVER_NPC_PAGE_EXACT_ITEM_RELATION_NOT_LIVE_STOCK",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["fieldSHA256"]="b7f631efd1bd04d43e752e5aa6ebe112f86902184894a99525630d2af096843b"},{["id"]="SUP_COOK_GIKKIX",["npcID"]=8137,["name"]="Gikkix",["faction"]="Neutral",["zone"]="Tanaris",["mapID"]=1446,["x"]=0.6664,["y"]=0.2208,["items"]={159,6289,6303,6308,6362,4603},["recipeItems"]={13939,13945,13946},["url"]="https://www.wow-professions.com/forever/npc/gikkix",["geographyOrigin"]="FOREVER_VENDOR_RELATION_CLASSIC_ZONE_NORMALIZED_GEOGRAPHY_NOT_LIVE_ACCESS",["mapDomain"]="UI_MAP_ID",["accessed"]="2026-10-26",["evidence"]="FOREVER_NPC_PAGE_EXACT_ITEM_RELATION_NOT_LIVE_STOCK",["stock"]="UNKNOWN",["transport"]="NOT_PROVEN_BY_PIN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["fieldSHA256"]="fe1c2e43583ce15c67bf4f2e47aa2d118d594afa85c9f94ac196e6433c0b9b01"}})do JLP.data.materialAcquisitionSources.vendors[#JLP.data.materialAcquisitionSources.vendors+1]=r end
-- END QUALIFIED SECONDARY SUPPLY

-- BEGIN QUALIFIED STATION MATERIAL SOURCE70532
JLP.data.materialAcquisitionSources.vendors[#JLP.data.materialAcquisitionSources.vendors+1]={["id"]="SUP_COOK_NAAL_WOOD",["npcID"]=3027,["name"]="Naal Mistrunner",["faction"]="Horde",["zone"]="Thunder Bluff",["mapID"]=1456,["x"]=0.5099,["y"]=0.5245,["items"]={4470},["recipeItems"]={},["url"]="https://www.wow-professions.com/forever/cooking-leveling-guide",["geographyOrigin"]="EXISTING_CLASSIC_ZONE_NORMALIZED_EXPLICIT_70532_UI1456_JOIN_NOT_LIVE_ACCESS",["evidence"]="FOREVER_COOKING_GUIDE_EXPLICIT_SIMPLE_WOOD_VENDOR_NAAL",["mapDomain"]="UI_MAP_ID",["stock"]="UNKNOWN",["price"]="NOT_IMPORTED",["purchaseUnit"]="CURRENT_API_REQUIRED",["accessed"]="2026-10-27",["fieldSHA256"]="d3676a30ddb3d316359da152a44daacacf2092e2b12a6b7160ee37395e0587fa"}
-- END QUALIFIED STATION MATERIAL SOURCE70532
