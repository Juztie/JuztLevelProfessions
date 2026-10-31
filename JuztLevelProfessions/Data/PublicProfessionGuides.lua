local _, JLP = ...

-- Public Wowhead Forever guides, cross-referenced against the project's historical
-- profession review documents. Research-level advisory data, never native authority.
-- Skill bands are included only where the cited Wowhead guide actually specifies them.
-- No invented node positions, probabilities, recipe IDs or 225-300 routes.
local root = "https://www.wowhead.com/forever/"
local skill = function(id,slug) return root.."skill="..id.."/"..slug end
local function band(from,to,action,zones,resources,notes)
    return {skillMin=from,skillMax=to,action=action,zones=zones or {},resources=resources or {},notes=notes}
end
JLP.data.publicProfessionGuides = {
    contract="forever-public-profession-guide-catalog-v1",
    validationBasis="WOWHEAD_FOREVER",
    capturedAt="2026-10-08",
    optionalClientObservation=true,
    nativeDispatchAllowed=false,
    comparisonGuides={
        TAILORING="https://www.wow-professions.com/forever/tailoring-leveling-guide",
        ALCHEMY="https://www.wow-professions.com/forever/alchemy-leveling-guide",
        ENCHANTING="https://www.wow-professions.com/forever/enchanting-leveling-guide",
        LEATHERWORKING="https://www.wow-professions.com/forever/leatherworking-leveling-guide",
        BLACKSMITHING="https://wowprofs.com/forever/",
        ENGINEERING="https://wowprofs.com/forever/",
    },
    professions={
        TAILORING={skillLineID=197,source=skill(197,"tailoring"),routeSource="Data/Tailoring.lua",levelingType="RECIPE_CRAFTING",coverage="CURATED_21_STEP_ROUTE",note="21-step internal route; compare recipes, reagents, skill thresholds and trainer gates with Forever references."},
        ENCHANTING={skillLineID=333,source=skill(333,"enchanting"),routeSource="Data/Enchanting.lua",levelingType="TARGETED_CRAFTING",coverage="CURATED_8_STEP_ROUTE",note="8-step internal targeted enchanting route; preserve rod hierarchy and explicit targets."},
        ALCHEMY={skillLineID=171,source=skill(171,"alchemy"),routeSource="Data/Alchemy.lua",levelingType="RECIPE_CRAFTING",coverage="FOREVER_13_RECIPE_REFERENCE_ROUTE",note="Normal/Aggressive historic guide strategies use the same current Forever recipe/material authority as other crafting professions. Herb gathering is optional, not a prerequisite; skill progression is not certified optimal."},
        BLACKSMITHING={skillLineID=164,source=skill(164,"blacksmithing"),levelingType="RECIPE_CRAFTING",coverage="PUBLIC_13_RECIPE_SAMPLES",note="13 Forever spell/reagent references cross-checked against Normal/Aggressive. Route costs, skill-up and complete 1–300 readiness not yet established."},
        ENGINEERING={skillLineID=202,source=skill(202,"engineering"),levelingType="RECIPE_CRAFTING",coverage="PUBLIC_10_RECIPE_SAMPLES",note="10 Forever spell/reagent references cross-checked against Normal/Aggressive; Rough Dynamite research has documented Forever reagent drift."},
        LEATHERWORKING={skillLineID=165,source=skill(165,"leatherworking"),levelingType="RECIPE_CRAFTING",coverage="PUBLIC_12_RECIPE_SAMPLES",note="12 Forever spell/reagent references across multiple bands; research craft estimates and 1–300 optimization are not validated."},
        HERBALISM={skillLineID=182,source=skill(182,"herbalism"),guideURL=root.."guide/professions/herbalism/overview-leveling",levelingType="NODE_GATHERING",utilityType="RECIPE_CRAFTING",coverage="PUBLIC_1_225_BANDS",note="Camping crafts are utility, not presumed leveling actions. Find Herbs is advisory; no node spawn guarantee.",bands={
            band(1,70,"GATHER",{"Starter zones"},{"Peacebloom","Silverleaf","Earthroot"}),
            band(70,115,"GATHER",{"Darkshore","Loch Modan","Silverpine Forest"},{"Mageroyal","Briarthorn","Stranglekelp"}),
            band(115,170,"GATHER",{"Hillsbrad Foothills","Wetlands","Stonetalon Mountains"},{"Bruiseweed","Wild Steelbloom","Kingsblood","Liferoot"}),
            band(170,205,"GATHER",{"Stranglethorn Vale","Arathi Highlands"},{"Fadeleaf","Goldthorn","Khadgar's Whisker"}),
            band(205,225,"GATHER",{"Alterac Mountains","Tanaris","Searing Gorge"},{"Wintersbite","Firebloom","Purple Lotus"})}},
        MINING={skillLineID=186,source=skill(186,"mining"),guideURL=root.."guide/professions/mining/overview-leveling",levelingType="NODE_GATHERING",utilityType="SMELTING",coverage="PUBLIC_1_225_GATHER_AND_1_185_SMELT",note="Wowhead lists smelting through skill 185, but no smelt skillups in 140-155. Never present smelting as a universal 1-300 path.",bands={
            band(1,65,"MINE",{"Starter zones"},{"Copper Vein"}),
            band(65,125,"MINE",{"Ashenvale","Redridge Mountains","The Barrens","Thousand Needles"},{"Copper Vein","Tin Vein","Silver Vein"}),
            band(125,175,"MINE",{"Arathi Highlands","Desolace","Stranglethorn Vale","Thousand Needles"},{"Iron Deposit","Gold Vein"}),
            band(175,225,"MINE",{"Azshara","Tanaris","The Hinterlands"},{"Mithril Deposit","Truesilver Deposit"})},alternatives={
            band(1,65,"SMELT",{}, {"Copper Ore"}),band(65,75,"SMELT",{}, {"Tin Ore"}),
            band(75,100,"SMELT",{}, {"Copper Bar","Tin Bar"}),band(100,125,"SMELT",{}, {"Silver Ore"}),
            band(125,140,"SMELT",{}, {"Iron Ore"}),band(155,185,"SMELT",{}, {"Gold Ore"})}},
        SKINNING={skillLineID=393,source=skill(393,"skinning"),levelingType="AREA_GATHERING",utilityType="RECIPE_CRAFTING",coverage="SOURCE_INDEX_ONLY",note="Leveling is animal skinning in eligible areas; camping crafts are utility. Zone/polygon data needs separate public evidence."},
        COOKING={skillLineID=185,source=skill(185,"cooking"),guideURL=root.."guide/professions/cooking/overview-leveling",levelingType="RECIPE_CRAFTING",coverage="PUBLIC_1_225_FISH_RECIPE_GUIDE",note="Five documented fish-cooking bands; craft quantities are guide estimates. Expert cookbook at 150; Artisan quest at 225. Not a verified 225-300 route."},
        FIRST_AID={skillLineID=129,source=skill(129,"first-aid"),guideURL=root.."guide/professions/first-aid/overview",levelingType="RECIPE_CRAFTING",coverage="PUBLIC_1_225_BANDS",note="Forever transfers healing potions to First Aid. Expert rank requires a vendor book; Artisan via Triage quest at skill 225 and character level 35.",bands={
            band(1,75,"CRAFT",{}, {"Minor Healing Potion","Peacebloom"}),
            band(75,110,"CRAFT",{}, {"Lesser Healing Potion","Briarthorn"}),
            band(110,150,"CRAFT",{}, {"Healing Potion","Bruiseweed"}),
            band(150,180,"CRAFT",{}, {"Silk Bandage","Silk Cloth"}),
            band(180,210,"CRAFT",{}, {"Heavy Silk Bandage","Silk Cloth"}),
            band(210,225,"CRAFT",{}, {"Mageweave Bandage","Mageweave Cloth"})}},
        FISHING={skillLineID=356,source=skill(356,"fishing"),guideURL=root.."guide/professions/fishing/overview-leveling",levelingType="FISHING_AREA",utilityType="RECIPE_CRAFTING",coverage="PUBLIC_1_225_BANDS",note="Fishing skill is gained by catches, not region difficulty. Expert book at 150; Nat Pagle quest at 225 and character level 35. Camping recipes are utility.",bands={
            band(1,75,"FISH",{"Starter zones"}),
            band(75,150,"FISH",{"Major faction capital cities"}),
            band(150,225,"FISH",{"Dustwallow Marsh","Stranglethorn Vale"})}},
    }
}
