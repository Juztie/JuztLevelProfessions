local _, JLP = ...
-- Explicit Forever Wowhead spell references, curated against the original
-- user-supplied Horde Profession Infomation v2 research candidate routes.
-- An observed recipe/reagent match is not a 1-300 route or efficiency proof.
-- All rows are read-only; player or NPC snapshots are OPTIONAL.
local root="https://www.wowhead.com/forever/spell="
local function recipe(id,name,skill,reagents,opts)
    opts=opts or {}
    return {
        recipeID=id, name=name, requiredSkill=skill,
        reagents=reagents, sourceURL=root..id, sourceBuild=70245,
        evidenceClass="PUBLIC_FOREVER_RECIPE_REAGENTS", status="REFERENCE_VERIFIED",
        outputPerCraft=opts.outputPerCraft, researchRoute=opts.researchRoute,
        enforceDB70450Parity=opts.enforceDB70450Parity==true,
        skillBasis=opts.skillBasis or "RESEARCH_OR_SOURCE_BAND",
        tools=opts.tools or {}, notes=opts.notes,
    }
end
local function mat(id,name,qty) return {itemID=id,name=name,quantity=qty} end
JLP.data.publicCraftingRouteEvidence={
    contract="public-forever-crafting-route-evidence-v3",
    source="wowhead-forever", build=70245,
    nativeDispatchAllowed=false, optionalClientObservation=true,
    professions={
        BLACKSMITHING={
            skillLineID=164,
            recipes={
                recipe(2660,"Rough Sharpening Stone",1,{mat(2835,"Rough Stone",1)},{researchRoute=true,outputPerCraft=2,notes="Research 1-25 estimate remains unqualified as an optimal band."}),
                recipe(3320,"Rough Grinding Stone",25,{mat(2835,"Rough Stone",2)},{researchRoute=true,outputPerCraft=2}),
                recipe(2661,"Copper Chain Belt",35,{mat(2840,"Copper Bar",6)},{researchRoute=true,outputPerCraft=2,tools={"Blacksmith Hammer"}}),
                -- Additional Forever spell pages, exact DIRECT reagent slot only (not expanded sub-recipe tree).
                -- P0-222: exact 7408 spell, Blacksmithing 65 and three direct
                -- reagents independently corroborated by DB70450. The Forever
                -- output count (2) differs from historical effect base (1).
                -- Teacher names on the public page are reference only; no NPC
                -- stock, waypoint, or progression/craft authority is granted.
                recipe(7408,"Heavy Copper Maul",65,{mat(2840,"Copper Bar",12),mat(2880,"Weak Flux",2),mat(2318,"Light Leather",2)},
                    {researchRoute=false,outputPerCraft=2,skillBasis="WOWHEAD_FOREVER",enforceDB70450Parity=true,tools={"Blacksmith Hammer","Anvil"},
                    notes="Spell-page minimum 65, orange/yellow/green/gray shown as public reference; no live observed color or assured skill-up."}),
                recipe(2666,"Runed Copper Belt",70,{mat(2840,"Copper Bar",10)},{researchRoute=true,tools={"Blacksmith Hammer"}}),
                recipe(2664,"Runed Copper Bracers",80,{mat(2840,"Copper Bar",10),mat(3470,"Rough Grinding Stone",3)},{researchRoute=true,tools={"Blacksmith Hammer"}}),
                recipe(3331,"Silvered Bronze Boots",105,{mat(2841,"Bronze Bar",6),mat(2842,"Silver Bar",1),mat(3478,"Coarse Grinding Stone",2)},{researchRoute=true,tools={"Blacksmith Hammer"}}),
                recipe(3501,"Green Iron Bracers",165,{mat(3575,"Iron Bar",6),mat(2605,"Green Dye",1)},{researchRoute=true,tools={"Blacksmith Hammer"}}),
                recipe(7223,"Golden Scale Bracers",185,{mat(3859,"Steel Bar",5),mat(3486,"Heavy Grinding Stone",2)},{researchRoute=true,tools={"Blacksmith Hammer"},skillBasis="WOWHEAD_FOREVER"}),
                recipe(9920,"Solid Grinding Stone",200,{mat(7912,"Solid Stone",4)},{researchRoute=true}),
                recipe(16641,"Dense Sharpening Stone",250,{mat(12365,"Dense Stone",1)},{researchRoute=true}),
                recipe(16647,"Imperial Plate Belt",265,{mat(12359,"Thorium Bar",22),mat(8170,"Rugged Leather",6),mat(7909,"Aquamarine",1)},{researchRoute=true,tools={"Blacksmith Hammer"}}),
                recipe(16649,"Imperial Plate Bracers",270,{mat(12359,"Thorium Bar",20),mat(7910,"Star Ruby",1)},{researchRoute=true,tools={"Blacksmith Hammer"}}),
                recipe(3328,"Rough Bronze Shoulders",nil,{mat(2841,"Bronze Bar",5),mat(1210,"Shadowgem",1),mat(3478,"Coarse Grinding Stone",1)},{researchRoute=true,tools={"Blacksmith Hammer"},skillBasis="FOREVER_REAGENTS_ONLY",notes="Forever spell verifies ingredients; required profession skill not asserted from historical guide."}),
                recipe(16657,"Imperial Plate Boots",295,{mat(12359,"Thorium Bar",34),mat(7910,"Star Ruby",1),mat(7909,"Aquamarine",1)},{researchRoute=true,tools={"Blacksmith Hammer"},skillBasis="WOWHEAD_FOREVER",notes="Forever-specific 34 Thorium, Star Ruby, Aquamarine; not Retail ingredients."}),
                recipe(3326,"Coarse Grinding Stone",75,{mat(2836,"Coarse Stone",2)},{researchRoute=false,skillBasis="WOWHEAD_FOREVER",notes="Forever spell 3326 creates two coarse grinding stones per cast; intermediate for Runed Copper Bracers and Silvered Bronze Boots."}),
                recipe(3337,"Heavy Grinding Stone",125,{mat(2838,"Heavy Stone",3)},{researchRoute=false,skillBasis="WOWHEAD_FOREVER",notes="Additional intermediate for Golden Scale Bracers; not a Normal route step."}),

            },
        },
        ENGINEERING={
            skillLineID=202,
            recipes={
                recipe(3918,"Rough Blasting Powder",1,{mat(2835,"Rough Stone",1)},{researchRoute=true}),
                recipe(3922,"Handful of Copper Bolts",30,{mat(2840,"Copper Bar",1)},{researchRoute=true,outputPerCraft=2,tools={"Blacksmith Hammer"}}),
                recipe(3923,"Rough Copper Bomb",30,{
                    mat(2840,"Copper Bar",1),mat(4359,"Handful of Copper Bolts",1),
                    mat(4357,"Rough Blasting Powder",2),mat(2589,"Linen Cloth",1),
                },{researchRoute=false,outputPerCraft=3,tools={"Blacksmith Hammer"},notes="Additional supported craft/buy comparison option; absent from the Normal research route."}),
                recipe(3919,"Rough Dynamite",1,{mat(4357,"Rough Blasting Powder",1),mat(2589,"Linen Cloth",1)},{researchRoute=true,outputPerCraft=3,skillBasis="WOWHEAD_FOREVER",notes="Wowhead Forever spell 3919 checked 2026-10-08: ONE Rough Blasting Powder and ONE Linen Cloth per craft, output 3. Previous alpha134 evidence of two powders was incorrect."}),
                recipe(7430,"Arclight Spanner",50,{mat(2840,"Copper Bar",6)},{researchRoute=true,tools={"Blacksmith Hammer"},skillBasis="WOWHEAD_FOREVER",notes="Forever spell 7430; per craft 6 copper bars."}),
                recipe(3931,"Coarse Dynamite",75,{mat(4364,"Coarse Blasting Powder",3),mat(2589,"Linen Cloth",1)},{researchRoute=true,skillBasis="WOWHEAD_FOREVER",notes="Forever spell 3931 uses 3 coarse blasting powders per cast."}),
                recipe(3924,"Copper Tube",50,{mat(2840,"Copper Bar",2),mat(2880,"Weak Flux",1)},{researchRoute=true,tools={"Blacksmith Hammer"}}),
                recipe(3929,"Coarse Blasting Powder",81,{mat(2836,"Coarse Stone",1)},{researchRoute=true}),
                recipe(3973,"Silver Contact",91,{mat(2842,"Silver Bar",1)},{researchRoute=true}),
                recipe(3938,"Bronze Tube",111,{mat(2841,"Bronze Bar",2),mat(2880,"Weak Flux",1)},{researchRoute=true,tools={"Blacksmith Hammer"}}),
                recipe(3945,"Heavy Blasting Powder",125,{mat(2838,"Heavy Stone",1)},{researchRoute=true}),
                recipe(12599,"Mithril Casing",215,{mat(3860,"Mithril Bar",3)},{researchRoute=true,tools={"Blacksmith Hammer","Arclight Spanner"}}),

            },
        },
        LEATHERWORKING={
            skillLineID=165,
            recipes={
                recipe(2881,"Light Leather",1,{mat(2934,"Ruined Leather Scraps",3)},{researchRoute=true,outputPerCraft=2}),
                recipe(9058,"Handstitched Leather Cloak",1,{mat(2318,"Light Leather",2),mat(2320,"Coarse Thread",1)},{researchRoute=true,outputPerCraft=2}),
                recipe(9059,"Handstitched Leather Bracers",1,{mat(2318,"Light Leather",2),mat(2320,"Coarse Thread",3)},{researchRoute=false,outputPerCraft=2,notes="An alternative; not in the Normal research route."}),
                recipe(2152,"Light Armor Kit",1,{mat(2318,"Light Leather",1)},{researchRoute=false,outputPerCraft=2,notes="An alternative; not in the Normal research route."}),
                recipe(3816,"Cured Light Hide",nil,{mat(783,"Light Hide",1),mat(4289,"Salt",1)},{researchRoute=true,skillBasis="FOREVER_REAGENTS_ONLY",notes="Forever spell 3816 verifies direct reagent IDs/amounts; level gate not asserted."}),
                recipe(2165,"Medium Armor Kit",75,{mat(2319,"Medium Leather",4),mat(2320,"Coarse Thread",1)},{researchRoute=true}),
                recipe(3780,"Heavy Armor Kit",125,{mat(4234,"Heavy Leather",5),mat(2321,"Fine Thread",1)},{researchRoute=true}),
                recipe(3818,"Cured Heavy Hide",151,{mat(4235,"Heavy Hide",1),mat(4289,"Salt",3)},{researchRoute=true}),
                recipe(10487,"Thick Armor Kit",200,{mat(4304,"Thick Leather",5),mat(4291,"Silken Thread",1)},{researchRoute=true,skillBasis="WOWHEAD_FOREVER",notes="Forever quick facts require Leatherworking 200; historical route positions step 211-221."}),
                recipe(19058,"Rugged Armor Kit",250,{mat(8170,"Rugged Leather",5)},{researchRoute=true,skillBasis="WOWHEAD_FOREVER"}),
                recipe(10507,"Nightscape Headband",221,{mat(4304,"Thick Leather",5),mat(4291,"Silken Thread",2)},{researchRoute=true}),
                recipe(10548,"Nightscape Pants",230,{mat(4304,"Thick Leather",14),mat(4291,"Silken Thread",4)},{researchRoute=true}),
                recipe(19071,"Wicked Leather Headband",280,{mat(8170,"Rugged Leather",12),mat(2325,"Black Dye",1),mat(14341,"Rune Thread",1)},{researchRoute=true,skillBasis="WOWHEAD_FOREVER",notes="Exact Forever minimum 280; historical route placement 286 is not a learning minimum."}),

            },
        },
    },
}
