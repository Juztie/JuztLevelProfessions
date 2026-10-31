local _, JLP = ...

-- External WoW Forever acquisition-source references for research-route recipe
-- gates. These references are deliberately separated from live client evidence:
-- a later Forever build must re-corroborate a source before the reference can
-- regain promotion authority. Ambiguous or conflicting references remain
-- diagnostic-only until the client observes an exact source.
local CAPTURED_BUILD = 70009

JLP.data.recipeAccessSources = {
    contract = "forever-recipe-access-source-reference-v1",
    sourceMetadata = {
        authority = "external-reference-only",
        capturedAgainstBuild = CAPTURED_BUILD,
        buildPinned = false,
        source = "Wowhead Forever database + named Forever source references",
        capturedForAddonVersion = "0.31.0-alpha127",
    },
    requirements = {
        ["recipe:superior mana potion"] = {
            kind = "recipe",
            name = "Superior Mana Potion",
            accessItemName = "Recipe: Superior Mana Potion",
            itemID = 13477,
            capturedBuild = 70245,
            sources = {
                {
                    sourceType = "vendor",
                    npc = "Algernon",
                    npcID = 4610,
                    zone = "Undercity",
                    faction = "Horde",
                    limitedSupply = true,
                    evidenceQuality = "forever-direct+named-reference",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=13477 + wowhead-forever:npc=4610",
                },
                {
                    sourceType = "vendor",
                    npc = "Ulthir",
                    npcID = 4226,
                    zone = "Darnassus",
                    faction = "Alliance",
                    limitedSupply = true,
                    evidenceQuality = "forever-item+named-reference",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=13477 vendor location + named vendor reference",
                },
            },
        },
        ["pattern:azure silk cloak"] = {
            kind = "pattern", name = "Azure Silk Cloak", accessItemName = "Pattern: Azure Silk Cloak", itemID = 7089, capturedBuild = 70245,
            sources = {
                {sourceType="vendor", npc="Jun'ha", zone="Hammerfall, Arathi Highlands", faction="Horde", limitedSupply=true, evidenceQuality="forever-direct-vendor-location", referenceEligible=true, evidence="wowhead-forever:item=7089"},
                {sourceType="vendor", npc="Brienna Starglow", zone="Feralas", faction="Alliance", limitedSupply=true, evidenceQuality="forever-named-reference", referenceEligible=true, evidence="wowhead-forever:item=7089 vendor locations + named reference"},
            },
        },
        ["pattern:brightcloth cloak"] = {
            kind = "pattern", name = "Brightcloth Cloak", accessItemName = "Pattern: Brightcloth Cloak", itemID = 14484, capturedBuild = 70245,
            sources = {
                {sourceType="drop", npc="Balzaphon", npcID=14684, zone="Stratholme", faction="Neutral", evidenceQuality="forever-direct-npc-drop", referenceEligible=true, evidence="wowhead-forever:npc=14684 lists Pattern: Brightcloth Cloak"},
            },
        },
        ["pattern:runecloth pants"] = {
            kind = "pattern", name = "Runecloth Pants", accessItemName = "Pattern: Runecloth Pants", itemID = 14491, capturedBuild = 70245,
            sources = {
                {sourceType="drop", npc="Houndmaster Grebmar", npcID=9319, zone="Blackrock Depths", faction="Neutral", evidenceQuality="forever-direct-npc-drop", referenceEligible=true, evidence="wowhead-forever:npc=9319 lists Pattern: Runecloth Pants"},
            },
        },
        ["pattern:mooncloth"] = {
            kind = "pattern", name = "Mooncloth", accessItemName = "Pattern: Mooncloth", itemID = 14526, capturedBuild = 70245,
            sources = {
                {sourceType="vendor", npc="Qia", npcID=11189, zone="Everlook, Winterspring", faction="Neutral", evidenceQuality="forever-spell+named-reference", referenceEligible=true, evidence="wowhead-forever:spell=18560 + pattern item identity"},
            },
        },
        ["pattern:mooncloth robe"] = {
            kind = "pattern", name = "Mooncloth Robe", accessItemName = "Pattern: Mooncloth Robe", itemID = 18487, capturedBuild = 70245,
            sources = {
                {sourceType="vendor", npc="Shen'dralar Provisioner", npcID=14371, zone="Dire Maul", faction="Neutral", evidenceQuality="forever-direct-vendor-location", referenceEligible=true, evidence="wowhead-forever:item=18487 + wowhead-forever:npc=14371"},
            },
        },
        ["formula:enchant cloak minor agility"] = {
            kind = "formula",
            name = "Enchant Cloak - Minor Agility",
            accessItemName = "Formula: Enchant Cloak - Minor Agility",
            itemID = 11039,
            sources = {
                {
                    sourceType = "vendor",
                    npc = "Kulwia",
                    npcID = 12043,
                    zone = "Stonetalon Mountains",
                    faction = "Horde",
                    limitedSupply = true,
                    evidenceQuality = "forever-location+npc-corroborated",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=11039 + wowhead-forever:npc=12043",
                },
            },
        },
        ["formula:enchant bracer lesser strength"] = {
            kind = "formula",
            name = "Enchant Bracer - Lesser Strength",
            accessItemName = "Formula: Enchant Bracer - Lesser Strength",
            itemID = 11101,
            sources = {
                {
                    sourceType = "vendor",
                    npc = "Kulwia",
                    npcID = 12043,
                    zone = "Stonetalon Mountains",
                    faction = "Horde",
                    limitedSupply = true,
                    evidenceQuality = "forever-location+npc-corroborated",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=11101 + wowhead-forever:npc=12043",
                },
            },
        },
        ["formula:enchant shield greater stamina"] = {
            kind = "formula",
            name = "Enchant Shield - Greater Stamina",
            accessItemName = "Formula: Enchant Shield - Greater Stamina",
            itemID = 16217,
            capturedBuild = 70245,
            sources = {
                {
                    sourceType = "vendor",
                    npc = "Daniel Bartlett",
                    npcID = 4561,
                    zone = "Undercity",
                    faction = "Horde",
                    limitedSupply = true,
                    bindsOnPickup = true,
                    evidenceQuality = "forever-direct+named-reference",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=16217",
                },
                {
                    sourceType = "vendor",
                    npc = "Mythrin'dir",
                    npcID = 4229,
                    zone = "Darnassus",
                    faction = "Alliance",
                    limitedSupply = true,
                    bindsOnPickup = true,
                    evidenceQuality = "forever-direct+named-reference",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=16217 + wowhead-forever:npc=4229",
                },
            },
        },
        ["formula:enchant cloak superior defense"] = {
            kind = "formula",
            name = "Enchant Cloak - Superior Defense",
            accessItemName = "Formula: Enchant Cloak - Superior Defense",
            itemID = 16224,
            sources = {
                {
                    sourceType = "vendor",
                    npc = "Lorelae Wintersong",
                    npcID = 12022,
                    zone = "Moonglade",
                    faction = "Neutral",
                    limitedSupply = true,
                    evidenceQuality = "forever-direct+named-reference",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=16224 + wowhead-forever:npc=12022",
                },
            },
        },
        ["schematic:thorium widget"] = {
            kind = "schematic",
            name = "Thorium Widget",
            accessItemName = "Schematic: Thorium Widget",
            itemID = 16042,
            conflict = true,
            conflictReason = "Forever item data lists Orgrimmar/Ironforge vendors while historical comments also describe trainer acquisition; exact current-build Horde source is not treated as settled.",
            sources = {
                {
                    sourceType = "vendor",
                    zone = "Orgrimmar",
                    faction = "Horde",
                    unresolvedIdentity = true,
                    evidenceQuality = "forever-direct-location-only",
                    referenceEligible = false,
                    evidence = "wowhead-forever:item=16042",
                },
                {
                    sourceType = "trainer",
                    npc = "Buzzek Bracketswing",
                    zone = "Gadgetzan, Tanaris",
                    faction = "Neutral",
                    evidenceQuality = "forever-commentary-conflict",
                    referenceEligible = false,
                    evidence = "wowhead-forever:item=16042 comments",
                },
            },
        },
        ["pattern:wicked leather bracers"] = {
            kind = "pattern",
            name = "Wicked Leather Bracers",
            accessItemName = "Pattern: Wicked Leather Bracers",
            itemID = 15728,
            sources = {
                {
                    sourceType = "drop",
                    npc = "Legashi Rogue",
                    zone = "Azshara",
                    faction = "Neutral",
                    evidenceQuality = "forever-direct-drop",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=15728",
                },
            },
        },
        ["pattern:wicked leather headband"] = {
            kind = "pattern",
            name = "Wicked Leather Headband",
            accessItemName = "Pattern: Wicked Leather Headband",
            itemID = 15744,
            sources = {
                {
                    sourceType = "drop",
                    npc = "Jadefire Trickster",
                    zone = "Felwood",
                    faction = "Neutral",
                    evidenceQuality = "forever-direct-drop",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=15744",
                },
            },
        },
        ["pattern:runecloth bag"] = {
            kind = "pattern",
            name = "Runecloth Bag",
            accessItemName = "Pattern: Runecloth Bag",
            itemID = 14468,
            sources = {
                {
                    sourceType = "vendor",
                    npc = "Qia",
                    npcID = 11189,
                    zone = "Everlook, Winterspring",
                    faction = "Neutral",
                    limitedSupply = true,
                    evidenceQuality = "forever-direct+named-reference",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=14468 + forever tailoring pattern catalogue + wowhead-forever:npc=11189",
                },
            },
        },
        ["pattern:runecloth gloves"] = {
            kind = "pattern",
            name = "Runecloth Gloves",
            accessItemName = "Pattern: Runecloth Gloves",
            itemID = 14481,
            sources = {
                {
                    sourceType = "vendor",
                    npc = "Qia",
                    npcID = 11189,
                    zone = "Everlook, Winterspring",
                    faction = "Neutral",
                    limitedSupply = true,
                    bindsOnPickup = true,
                    evidenceQuality = "forever-direct+named-reference",
                    referenceEligible = true,
                    evidence = "wowhead-forever:item=14481 + wowhead-forever:npc=11189",
                },
            },
        },
    },
}

-- Current-task exact70532 teaching-item joins. These supplement the existing
-- requirements, never guarantee live stock or supply owner waypoint authority.
local req=JLP.data.recipeAccessSources.requirements
local guide="https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes"
req["pattern:runecloth boots"]={kind="pattern",name="Runecloth Boots",accessItemName="Pattern: Runecloth Boots",
 itemID=14488,recipeID=18423,professionKey="TAILORING",capturedBuild=70532,
 sources={{sourceType="vendor",npc="Darnall",npcID=7940,zone="Moonglade",faction="Neutral",
  referenceEligible=true,acquisitionPlanningQualified=true,limitedSupply=true,
  stockEvidence="VMANGOS_HISTORICAL_LIMIT1_NOT_LIVE",
  factionEvidence="HISTORICAL_NEUTRAL_REFERENCE_VERIFY_CURRENT_PURCHASABILITY",evidenceQuality="FOREVER_NAMED_GUIDE_PLUS_DB2_70532",
  evidence=guide,identityURL="https://www.wowhead.com/forever/npc=7940/darnall",
  accessStatus="VERIFY_CURRENT_MERCHANT",coordinatesStatus="UNKNOWN"}}}
local gloves=req["pattern:runecloth gloves"]
gloves.recipeID=18417;gloves.professionKey="TAILORING";gloves.capturedBuild=70532
local qia=gloves.sources[1]
qia.acquisitionPlanningQualified=true;qia.documentedStock=1
qia.stockEvidence="WOWHEAD_FOREVER_ITEM14481_SOLD_BY_STOCK1_NOT_CURRENT_STOCK"
qia.factionEvidence="WOWHEAD_FOREVER_ITEM14481_SOLD_BY_REACT_A_H"
qia.evidenceQuality="FOREVER_ITEM_SOLD_BY_PLUS_DB2_70532"
qia.identityURL="https://www.wowhead.com/forever/npc=11189/qia"
qia.accessStatus="VERIFY_CURRENT_MERCHANT";qia.coordinatesStatus="LEGACY_ONLY_NOT_OWNER_QUALIFIED"
req["pattern:enchanted runecloth bag"]={kind="pattern",name="Enchanted Runecloth Bag",accessItemName="Pattern: Enchanted Runecloth Bag",
 itemID=22308,recipeID=27659,professionKey="TAILORING",capturedBuild=70532,
 sources={{sourceType="vendor",npc="Kania",npcID=15419,zone="Silithus",faction="Neutral",
  referenceEligible=true,acquisitionPlanningQualified=false,
  evidenceQuality="FOREVER_ITEM_VENDOR_CATEGORY_PLUS_VMANGOS_NAMED_FALLBACK",
  factionEvidence="HISTORICAL_NEUTRAL_REFERENCE_VERIFY_CURRENT_PURCHASABILITY",
  evidence="https://metaforge.app/wow-forever/database/recipes/pattern-enchanted-runecloth-bag",
  identityURL="https://www.wowhead.com/forever/npc=15419/kania",
  accessStatus="UNKNOWN_UNTIL_CURRENT_MERCHANT",coordinatesStatus="LEGACY_ONLY_NOT_OWNER_QUALIFIED"}}}
