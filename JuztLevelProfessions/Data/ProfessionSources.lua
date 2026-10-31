local _, JLP = ...

-- Central profession source catalogue. Locations here are deliberately human-readable
-- until the standalone addon receives its own audited map/navigation layer.
-- Evidence labels distinguish Forever-specific verification, Classic continuity, and
-- user-supplied research provenance. v1 trainer data and v2 leveling research are
-- source evidence only, not live-client verification claims.
JLP.data.professionSources = {
    sourceMetadata = {
        hordeTrainerDataset = {
            id = "horde-profession-information-v1",
            source = "Horde Profession Infomation v1.docx",
            evidence = "user-research-horde-v1",
            scope = "Horde profession rank requirements and trainer coordinates",
        },
        hordeLevelingDataset = {
            id = "horde-profession-information-v2",
            source = "Horde Profession Infomation v2.docx",
            evidence = "user-research-horde-v2",
            scope = "Normal/Aggressive 1-300 route candidates, materials, keep markers, and recipe/formula/pattern/schematic requirements",
            authority = "research-reference-only",
        },
    },

    rankRequirements = {
        TAILORING = {
            { rank="Apprentice Tailoring", tier="Apprentice", skillCap=75, requiredSkill=0, minCharacterLevel=0, evidence="user-research-horde-v1" },
            { rank="Journeyman Tailoring", tier="Journeyman", skillCap=150, requiredSkill=50, minCharacterLevel=10, evidence="user-research-horde-v1" },
            { rank="Expert Tailoring", tier="Expert", skillCap=225, requiredSkill=125, minCharacterLevel=20, evidence="user-research-horde-v1" },
            { rank="Artisan Tailoring", tier="Artisan", skillCap=300, requiredSkill=200, minCharacterLevel=35, evidence="user-research-horde-v1" },
        },
        ENCHANTING = {
            { rank="Apprentice Enchanting", tier="Apprentice", skillCap=75, requiredSkill=0, minCharacterLevel=0, evidence="user-research-horde-v1" },
            { rank="Journeyman Enchanting", tier="Journeyman", skillCap=150, requiredSkill=50, minCharacterLevel=10, evidence="user-research-horde-v1" },
            { rank="Expert Enchanting", tier="Expert", skillCap=225, requiredSkill=125, minCharacterLevel=20, evidence="user-research-horde-v1" },
            { rank="Artisan Enchanting", tier="Artisan", skillCap=300, requiredSkill=200, minCharacterLevel=35, evidence="user-research-horde-v1" },
        },
        BLACKSMITHING = {
            { rank="Apprentice Blacksmithing", tier="Apprentice", skillCap=75, requiredSkill=0, minCharacterLevel=0, evidence="user-research-horde-v1" },
            { rank="Journeyman Blacksmithing", tier="Journeyman", skillCap=150, requiredSkill=50, minCharacterLevel=10, evidence="user-research-horde-v1" },
            { rank="Expert Blacksmithing", tier="Expert", skillCap=225, requiredSkill=125, minCharacterLevel=20, evidence="user-research-horde-v1" },
            { rank="Artisan Blacksmithing", tier="Artisan", skillCap=300, requiredSkill=200, minCharacterLevel=35, evidence="user-research-horde-v1" },
        },
        ENGINEERING = {
            { rank="Apprentice Engineering", tier="Apprentice", skillCap=75, requiredSkill=0, minCharacterLevel=0, evidence="user-research-horde-v1" },
            { rank="Journeyman Engineering", tier="Journeyman", skillCap=150, requiredSkill=50, minCharacterLevel=10, evidence="user-research-horde-v1" },
            { rank="Expert Engineering", tier="Expert", skillCap=225, requiredSkill=125, minCharacterLevel=20, evidence="user-research-horde-v1" },
            { rank="Artisan Engineering", tier="Artisan", skillCap=300, requiredSkill=200, minCharacterLevel=35, evidence="user-research-horde-v1" },
        },
        ALCHEMY = {
            { rank="Apprentice Alchemy", tier="Apprentice", skillCap=75, requiredSkill=0, minCharacterLevel=0, evidence="user-research-horde-v1" },
            { rank="Journeyman Alchemy", tier="Journeyman", skillCap=150, requiredSkill=50, minCharacterLevel=10, evidence="user-research-horde-v1" },
            { rank="Expert Alchemy", tier="Expert", skillCap=225, requiredSkill=125, minCharacterLevel=20, evidence="user-research-horde-v1" },
            { rank="Artisan Alchemy", tier="Artisan", skillCap=300, requiredSkill=200, minCharacterLevel=35, evidence="user-research-horde-v1" },
        },
        LEATHERWORKING = {
            { rank="Apprentice Leatherworking", tier="Apprentice", skillCap=75, requiredSkill=0, minCharacterLevel=0, evidence="user-research-horde-v1" },
            { rank="Journeyman Leatherworking", tier="Journeyman", skillCap=150, requiredSkill=50, minCharacterLevel=10, evidence="user-research-horde-v1" },
            { rank="Expert Leatherworking", tier="Expert", skillCap=225, requiredSkill=125, minCharacterLevel=20, evidence="user-research-horde-v1" },
            { rank="Artisan Leatherworking", tier="Artisan", skillCap=300, requiredSkill=200, minCharacterLevel=35, evidence="user-research-horde-v1" },
        },
    },

    trainers = {
        TAILORING = {
            ["Apprentice Tailoring"] = {
                Horde = {
                    { name="Snang", zone="Orgrimmar", area="The Drag", evidence="user-research-horde-v1", nav={mapID=1454,x=0.630,y=0.496,evidence="user-research-horde-v1"} },
                    { name="Victor Ward", zone="Undercity", area="Magic Quarter", evidence="user-research-horde-v1", nav={mapID=1458,x=0.702,y=0.296,evidence="user-research-horde-v1"} },
                    { name="Vhan", zone="Thunder Bluff", area="Central Bluff", evidence="user-research-horde-v1", nav={mapID=1456,x=0.440,y=0.446,evidence="user-research-horde-v1"} },
                    { name="Bowen Brisboise", zone="Tirisfal Glades", area="Cold Hearth Manor", evidence="user-research-horde-v1", nav={mapID=1420,x=0.526,y=0.556,evidence="user-research-horde-v1"} },
                    { name="Kil'hala", zone="The Barrens", area="The Crossroads", evidence="user-research-horde-v1", nav={mapID=1413,x=0.522,y=0.316,evidence="user-research-horde-v1"} },
                },
            },
            ["Journeyman Tailoring"] = {
                Horde = {
                    { name="Magar", zone="Orgrimmar", area="The Drag", evidence="user-research-horde-v1", nav={mapID=1454,x=0.634,y=0.500,evidence="user-research-horde-v1"} },
                    { name="Rhiannon Davis", zone="Undercity", area="Magic Quarter", evidence="user-research-horde-v1", nav={mapID=1458,x=0.706,y=0.296,evidence="user-research-horde-v1"} },
                    { name="Tepa", zone="Thunder Bluff", area="Central Bluff", evidence="user-research-horde-v1", nav={mapID=1456,x=0.442,y=0.450,evidence="user-research-horde-v1"} },
                    { name="Mahani", zone="The Barrens", area="Camp Taurajo", evidence="user-research-horde-v1", nav={mapID=1413,x=0.448,y=0.594,evidence="user-research-horde-v1"} },
                    { name="Grarnik Goodstitch", zone="Stranglethorn Vale", area="Booty Bay", evidence="user-research-horde-v1", nav={mapID=1434,x=0.286,y=0.768,evidence="user-research-horde-v1"} },
                    { name="Taleen Shimmerthread", zone="Zephras Isle", area="Shen'dar Village", evidence="user-research-horde-v1", nav={mapID=2521,x=0.448,y=0.442,evidence="user-research-horde-v1"} },
                    { name="Othesia Evengale", zone="Zephras Isle", area="Valanaar", evidence="user-research-horde-v1", nav={mapID=2521,x=0.644,y=0.810,evidence="user-research-horde-v1"} },
                },
                Alliance = {
                    { name="Sellandus", zone="Stormwind City", area="Mage Quarter", evidence="forever-verified", nav={mapID=1453,x=0.420,y=0.762,evidence="classic-coordinate"} },
                    { name="Jormund Stonebrow", zone="Ironforge", area="The Great Forge", evidence="forever-verified", nav={mapID=1455,x=0.432,y=0.290,evidence="classic-coordinate"} },
                    { name="Me'lynn", zone="Darnassus", area="Craftsmen's Terrace", evidence="forever-verified", nav={mapID=1457,x=0.626,y=0.226,evidence="classic-coordinate"} },
                },
            },
            ["Expert Tailoring"] = {
                Horde = {
                    { name="Josef Gregorian", zone="Undercity", area="Magic Quarter", evidence="user-research-horde-v1", nav={mapID=1458,x=0.706,y=0.306,evidence="user-research-horde-v1"} },
                },
                Alliance = {
                    { name="Georgio Bolero", zone="Stormwind City", area="Duncan's Textiles, Mage Quarter", evidence="forever-verified", nav={mapID=1453,x=0.432,y=0.736,evidence="classic-coordinate"} },
                },
            },
            ["Artisan Tailoring"] = {
                Horde = {
                    { name="Daryl Stack", zone="Hillsbrad Foothills", area="Tarren Mill", evidence="user-research-horde-v1", nav={mapID=1424,x=0.636,y=0.208,evidence="user-research-horde-v1"} },
                },
                Alliance = {
                    { name="Timothy Worthington", zone="Dustwallow Marsh", area="Theramore Isle - upstairs near the docks", evidence="forever-verified", nav={mapID=1445,x=0.662,y=0.516,evidence="classic-coordinate"} },
                },
            },
        },
        ENCHANTING = {
            ["Apprentice Enchanting"] = {
                Horde = {
                    { name="Jhag", zone="Orgrimmar", area="The Drag", evidence="user-research-horde-v1", nav={mapID=1454,x=0.536,y=0.382,evidence="user-research-horde-v1"} },
                    { name="Malcomb Wynn", zone="Undercity", area="The Apothecarium", evidence="user-research-horde-v1", nav={mapID=1458,x=0.626,y=0.604,evidence="user-research-horde-v1"} },
                    { name="Mot Dawnstrider", zone="Thunder Bluff", evidence="user-research-horde-v1", nav={mapID=1456,x=0.450,y=0.384,evidence="user-research-horde-v1"} },
                    { name="Vance Undergloom", zone="Tirisfal Glades", area="Brill", evidence="user-research-horde-v1", nav={mapID=1420,x=0.616,y=0.516,evidence="user-research-horde-v1"} },
                    { name="Pa'zula", zone="Durotar", area="Sen'jin Village", evidence="user-research-horde-v1", nav={mapID=1411,x=0.564,y=0.736,evidence="user-research-horde-v1"} },
                    { name="Nasalanna Windsinger", zone="Zephras Isle", area="Shen'dar Village", evidence="user-research-horde-v1", nav={mapID=2521,x=0.432,y=0.432,evidence="user-research-horde-v1"} },
                    { name="Eaysaa Brightgust", zone="Zephras Isle", area="Valanaar", evidence="user-research-horde-v1", nav={mapID=2521,x=0.592,y=0.762,evidence="user-research-horde-v1"} },
                },
            },
            ["Journeyman Enchanting"] = {
                Horde = {
                    { name="Godan", zone="Orgrimmar", area="The Drag", evidence="user-research-horde-v1", nav={mapID=1454,x=0.538,y=0.384,evidence="user-research-horde-v1"} },
                    { name="Lavinia Crowe", zone="Undercity", area="The Apothecarium", evidence="user-research-horde-v1", nav={mapID=1458,x=0.626,y=0.614,evidence="user-research-horde-v1"} },
                    { name="Teg Dawnstrider", zone="Thunder Bluff", evidence="user-research-horde-v1", nav={mapID=1456,x=0.450,y=0.380,evidence="user-research-horde-v1"} },
                },
                Alliance = {
                    { name="Gimble Thistlefuzz", zone="Ironforge", area="The Great Forge", evidence="forever-verified", nav={mapID=1455,x=0.600,y=0.453,evidence="classic-coordinate"} },
                    { name="Lucan Cordell", zone="Stormwind City", area="Mage Quarter", evidence="forever-verified", nav={mapID=1453,x=0.430,y=0.644,evidence="classic-coordinate"} },
                    { name="Taladan", zone="Darnassus", area="Craftsmen's Terrace", evidence="forever-verified", nav={mapID=1457,x=0.586,y=0.136,evidence="classic-coordinate"} },
                },
            },
            ["Expert Enchanting"] = {
                Horde = {
                    { name="Hgarth", zone="Stonetalon Mountains", area="Sun Rock Retreat", evidence="user-research-horde-v1", nav={mapID=1442,x=0.492,y=0.572,evidence="user-research-horde-v1"} },
                },
                Alliance = {
                    { name="Kitta Firewind", zone="Elwynn Forest", area="Top floor of the Tower of Azora", evidence="forever-verified", nav={mapID=1429,x=0.648,y=0.704,evidence="classic-coordinate"} },
                },
            },
            ["Artisan Enchanting"] = {
                Horde = {
                    { name="Annora", zone="Uldaman", area="Inside Uldaman", evidence="user-research-horde-v1", nav={mapID=1418,x=0.660,y=0.430,evidence="user-research-horde-v1"}, note="Rear entrance", dungeon=true },
                },
                Neutral = {
                    { name="Annora", zone="Uldaman", area="Inside the dungeon", evidence="forever-verified", nav={mapID=1418,x=0.660,y=0.430,evidence="user-research-horde-v1"}, note="Rear entrance", dungeon=true },
                },
            },
        },
        BLACKSMITHING = {
            ["Apprentice Blacksmithing"] = {
                Horde = {
                    { name="Ug'thok", zone="Orgrimmar", area="Valley of Honor", evidence="user-research-horde-v1", nav={mapID=1454,x=0.808,y=0.237,evidence="user-research-horde-v1"} },
                    { name="Basil Frye", zone="Undercity", area="War Quarter", evidence="user-research-horde-v1", nav={mapID=1458,x=0.602,y=0.291,evidence="user-research-horde-v1"} },
                    { name="Thrag Stonehoof", zone="Thunder Bluff", area="Lower Rise", evidence="user-research-horde-v1", nav={mapID=1456,x=0.394,y=0.567,evidence="user-research-horde-v1"} },
                    { name="Dwukk", zone="Durotar", area="Razor Hill", evidence="user-research-horde-v1", nav={mapID=1411,x=0.520,y=0.407,evidence="user-research-horde-v1"} },
                    { name="Guillaume Sorouy", zone="Silverpine Forest", area="The Sepulcher", evidence="user-research-horde-v1", nav={mapID=1421,x=0.432,y=0.411,evidence="user-research-horde-v1"} },
                    { name="Aedi Thriceforged", zone="Zephras Isle", area="Shen'dar Village", evidence="user-research-horde-v1", nav={mapID=2991,x=0.448,y=0.444,evidence="user-research-horde-v1"} },
                },
            },
            ["Journeyman Blacksmithing"] = {
                Horde = {
                    { name="Snarl", zone="Orgrimmar", area="Valley of Honor", evidence="user-research-horde-v1", nav={mapID=1454,x=0.796,y=0.233,evidence="user-research-horde-v1"} },
                    { name="James Van Brunt", zone="Undercity", area="War Quarter", evidence="user-research-horde-v1", nav={mapID=1458,x=0.613,y=0.306,evidence="user-research-horde-v1"} },
                    { name="Karn Stonehoof", zone="Thunder Bluff", area="Lower Rise", evidence="user-research-horde-v1", nav={mapID=1456,x=0.394,y=0.551,evidence="user-research-horde-v1"} },
                    { name="Traugh", zone="The Barrens", area="The Crossroads", evidence="user-research-horde-v1", nav={mapID=1413,x=0.513,y=0.289,evidence="user-research-horde-v1"} },
                    { name="Angus Hammerhand", zone="Tirisfal Glades", area="Bandarion Keep", evidence="user-research-horde-v1", nav={mapID=1420,x=0.211,y=0.462,evidence="user-research-horde-v1"} },
                    { name="Daeann Steelwind", zone="Zephras Isle", area="Valanaar", evidence="user-research-horde-v1", nav={mapID=2991,x=0.654,y=0.802,evidence="user-research-horde-v1"} },
                },
            },
            ["Expert Blacksmithing"] = {
                Horde = {
                    { name="Saru Steelfury", zone="Orgrimmar", area="Valley of Honor", evidence="user-research-horde-v1", nav={mapID=1454,x=0.823,y=0.230,evidence="user-research-horde-v1"} },
                },
            },
            ["Artisan Blacksmithing"] = {
                Horde = {
                    { name="Brikk Keencraft", zone="Stranglethorn Vale", area="Booty Bay", evidence="user-research-horde-v1", nav={mapID=1434,x=0.290,y=0.756,evidence="user-research-horde-v1"} },
                },
            },
        },
        ENGINEERING = {
            ["Apprentice Engineering"] = {
                Horde = {
                    { name="Graham Van Talen", zone="Undercity", area="Rogues' Quarter", evidence="user-research-horde-v1", nav={mapID=1458,x=0.756,y=0.732,evidence="user-research-horde-v1"} },
                    { name="Mukdrak", zone="Durotar", area="Razor Hill", evidence="user-research-horde-v1", nav={mapID=1411,x=0.522,y=0.408,evidence="user-research-horde-v1"} },
                    { name="Thund", zone="Orgrimmar", area="Valley of Honor", evidence="user-research-horde-v1", nav={mapID=1454,x=0.758,y=0.246,evidence="user-research-horde-v1"} },
                    { name="Twizwick Sprocketgrind", zone="Mulgore", area="Venture Co. Mine", evidence="user-research-horde-v1", nav={mapID=1412,x=0.618,y=0.314,evidence="user-research-horde-v1"} },
                    { name="Tinkerwiz", zone="The Barrens", area="Ratchet", evidence="user-research-horde-v1", nav={mapID=1413,x=0.626,y=0.362,evidence="user-research-horde-v1"} },
                    { name="Strange Hermit", zone="Zephras Isle", area="Shadowgale Forest", evidence="user-research-horde-v1", nav={mapID=2521,x=0.540,y=0.390,evidence="user-research-horde-v1"} },
                },
            },
            ["Journeyman Engineering"] = {
                Horde = {
                    { name="Franklin Lloyd", zone="Undercity", area="Rogues' Quarter", evidence="user-research-horde-v1", nav={mapID=1458,x=0.760,y=0.734,evidence="user-research-horde-v1"} },
                    { name="Nogg", zone="Orgrimmar", area="Valley of Honor", evidence="user-research-horde-v1", nav={mapID=1454,x=0.758,y=0.252,evidence="user-research-horde-v1"} },
                },
            },
            ["Expert Engineering"] = {
                Horde = {
                    { name="Roxxik", zone="Orgrimmar", area="Valley of Honor", evidence="user-research-horde-v1", nav={mapID=1454,x=0.760,y=0.250,evidence="user-research-horde-v1"} },
                },
            },
            ["Artisan Engineering"] = {
                Horde = {
                    { name="Buzzek Bracketswing", zone="Tanaris", area="Gadgetzan", evidence="user-research-horde-v1", nav={mapID=1446,x=0.522,y=0.276,evidence="user-research-horde-v1"} },
                    { name="Kaylaena Springwhisper", zone="Mount Hyjal", evidence="user-research-horde-v1", nav={mapID=2482,x=0.602,y=0.614,evidence="user-research-horde-v1"} },
                },
            },
        },
        ALCHEMY = {
            ["Apprentice Alchemy"] = {
                Horde = {
                    { name="Whuut", zone="Orgrimmar", area="The Drag", evidence="user-research-horde-v1", nav={mapID=1454,x=0.558,y=0.329,evidence="user-research-horde-v1"} },
                    { name="Doctor Martin Felben", zone="Undercity", area="The Apothecarium", evidence="user-research-horde-v1", nav={mapID=1458,x=0.466,y=0.741,evidence="user-research-horde-v1"} },
                    { name="Kray", zone="Thunder Bluff", area="Middle Rise", evidence="user-research-horde-v1", nav={mapID=1456,x=0.470,y=0.346,evidence="user-research-horde-v1"} },
                    { name="Carolai Anise", zone="Tirisfal Glades", area="Brill", evidence="user-research-horde-v1", nav={mapID=1420,x=0.594,y=0.522,evidence="user-research-horde-v1"} },
                    { name="Miao'zan", zone="Durotar", area="Sen'jin Village", evidence="user-research-horde-v1", nav={mapID=1411,x=0.554,y=0.740,evidence="user-research-horde-v1"} },
                    { name="Nyassa Swiftdraught", zone="Zephras Isle", area="Shen'dar Village", evidence="user-research-horde-v1", nav={mapID=2991,x=0.438,y=0.436,evidence="user-research-horde-v1"} },
                    { name="Valiena Swiftgale", zone="Zephras Isle", area="Valanaar", evidence="user-research-horde-v1", nav={mapID=2991,x=0.592,y=0.762,evidence="user-research-horde-v1"} },
                },
            },
            ["Journeyman Alchemy"] = {
                Horde = {
                    { name="Yelmak", zone="Orgrimmar", area="The Drag", evidence="user-research-horde-v1", nav={mapID=1454,x=0.568,y=0.330,evidence="user-research-horde-v1"} },
                    { name="Doctor Marsh", zone="Undercity", area="The Apothecarium", evidence="user-research-horde-v1", nav={mapID=1458,x=0.509,y=0.746,evidence="user-research-horde-v1"} },
                    { name="Bena Winterhoof", zone="Thunder Bluff", area="Middle Rise", evidence="user-research-horde-v1", nav={mapID=1456,x=0.466,y=0.332,evidence="user-research-horde-v1"} },
                    { name="Serge Hinott", zone="Hillsbrad Foothills", area="Tarren Mill", evidence="user-research-horde-v1", nav={mapID=1424,x=0.616,y=0.192,evidence="user-research-horde-v1"} },
                    { name="Kylanna", zone="Ashenvale", area="Silverwind Refuge", evidence="user-research-horde-v1", nav={mapID=1440,x=0.509,y=0.671,evidence="user-research-horde-v1"} },
                    { name="Jaxin Chong", zone="Stranglethorn Vale", area="Booty Bay", evidence="user-research-horde-v1", nav={mapID=1434,x=0.280,y=0.780,evidence="user-research-horde-v1"} },
                },
            },
            ["Expert Alchemy"] = {
                Horde = {
                    { name="Doctor Herbert Halsey", zone="Undercity", area="The Apothecarium", evidence="user-research-horde-v1", nav={mapID=1458,x=0.478,y=0.733,evidence="user-research-horde-v1"} },
                },
            },
            ["Artisan Alchemy"] = {
                Horde = {
                    { name="Rogvar", zone="Swamp of Sorrows", area="Stonard", evidence="user-research-horde-v1", nav={mapID=1435,x=0.485,y=0.558,evidence="user-research-horde-v1"} },
                    { name="Master Mycologist Shurome", zone="Felwood", area="Emerald Sanctuary", evidence="user-research-horde-v1", nav={mapID=1448,x=0.514,y=0.820,evidence="user-research-horde-v1"} },
                },
            },
        },
        LEATHERWORKING = {
            ["Apprentice Leatherworking"] = {
                Horde = {
                    { name="Kamari", zone="Orgrimmar", area="The Drag", evidence="user-research-horde-v1", nav={mapID=1454,x=0.630,y=0.450,evidence="user-research-horde-v1"} },
                    { name="Thuwd", zone="Orgrimmar", area="The Drag", evidence="user-research-horde-v1", nav={mapID=1454,x=0.632,y=0.452,evidence="user-research-horde-v1"} },
                    { name="Dan Golthas", zone="Undercity", area="Rogues' Quarter", evidence="user-research-horde-v1", nav={mapID=1458,x=0.704,y=0.584,evidence="user-research-horde-v1"} },
                    { name="Mak", zone="Thunder Bluff", evidence="user-research-horde-v1", nav={mapID=1456,x=0.422,y=0.432,evidence="user-research-horde-v1"} },
                    { name="Chaw Stronghide", zone="Mulgore", area="Bloodhoof Village", evidence="user-research-horde-v1", nav={mapID=1412,x=0.450,y=0.614,evidence="user-research-horde-v1"} },
                    { name="Shelene Rhobart", zone="Tirisfal Glades", area="Brill", evidence="user-research-horde-v1", nav={mapID=1420,x=0.654,y=0.600,evidence="user-research-horde-v1"} },
                    { name="Waldor", zone="The Barrens", area="Cave above Wailing Caverns", evidence="user-research-horde-v1", nav={mapID=1414,x=0.518,y=0.554,evidence="user-research-horde-v1"} },
                    { name="Indari Sunseam", zone="Zephras Isle", evidence="user-research-horde-v1", nav={mapID=2521,x=0.446,y=0.444,evidence="user-research-horde-v1"} },
                },
            },
            ["Journeyman Leatherworking"] = {
                Horde = {
                    { name="Karolek", zone="Orgrimmar", area="The Drag", evidence="user-research-horde-v1", nav={mapID=1454,x=0.628,y=0.444,evidence="user-research-horde-v1"} },
                    { name="Arthur Moore", zone="Undercity", area="Rogues' Quarter", evidence="user-research-horde-v1", nav={mapID=1458,x=0.706,y=0.578,evidence="user-research-horde-v1"} },
                    { name="Tarn", zone="Thunder Bluff", evidence="user-research-horde-v1", nav={mapID=1456,x=0.424,y=0.430,evidence="user-research-horde-v1"} },
                    { name="Brawn", zone="Stranglethorn Vale", area="Grom'gol Base Camp", evidence="user-research-horde-v1", nav={mapID=1434,x=0.316,y=0.288,evidence="user-research-horde-v1"} },
                    { name="Krulmoo Fullmoon", zone="The Barrens", area="Camp Taurajo", evidence="user-research-horde-v1", nav={mapID=1413,x=0.448,y=0.594,evidence="user-research-horde-v1"} },
                    { name="Emerii Tallgust", zone="Zephras Isle", evidence="user-research-horde-v1", nav={mapID=2521,x=0.638,y=0.804,evidence="user-research-horde-v1"} },
                },
            },
            ["Expert Leatherworking"] = {
                Horde = {
                    { name="Una", zone="Thunder Bluff", evidence="user-research-horde-v1", nav={mapID=1456,x=0.414,y=0.426,evidence="user-research-horde-v1"} },
                },
            },
            ["Artisan Leatherworking"] = {
                Horde = {
                    { name="Hahrana Ironhide", zone="Feralas", area="Camp Mojache", evidence="user-research-horde-v1", nav={mapID=1444,x=0.744,y=0.430,evidence="user-research-horde-v1"} },
                },
            },
        },
    },

    recipes = {
        TAILORING = {
            ["Azure Silk Cloak"] = {
                kind="vendor-pattern",
                evidence="classic-continuity",
                options={
                    Alliance={ { name="Brienna Starglow", zone="Feralas", area="Near the Thousand Needles border", evidence="classic-continuity" } },
                    Horde={ { name="Jun'ha", zone="Arathi Highlands", area="Hammerfall", evidence="classic-continuity" } },
                },
            },
            ["Brightcloth Cloak"] = {
                kind="drop-pattern",
                evidence="classic-continuity",
                note="World/drop pattern; use Auction House or obtain the pattern before this route step.",
            },
            ["Runecloth Pants"] = {
                kind="drop-pattern",
                evidence="classic-continuity",
                note="World/drop pattern; use Auction House or obtain the pattern before this route step.",
            },
            ["Mooncloth"] = {
                kind="vendor-pattern",
                itemID=14526,
                evidence="classic-continuity",
                options={
                    Neutral={ { name="Qia", zone="Winterspring", area="Everlook", evidence="classic-continuity", nav={mapID=1452,x=0.612,y=0.372,evidence="foreverdb-classic-coordinate"} } },
                },
            },
            ["Mooncloth Robe"] = {
                kind="vendor-pattern",
                itemID=18487,
                evidence="classic-continuity",
                options={
                    Neutral={ { name="Shen'dralar Provisioner", zone="Dire Maul", area="The Athenaeum / library", evidence="classic-continuity", dungeon=true } },
                },
            },
        },
        ENCHANTING = {
            ["Lesser Mana Oil"] = {
                kind="vendor-formula",
                evidence="forever-verified",
                options={
                    Neutral={ { name="Kania", zone="Silithus", area="Cenarion Hold - upstairs in the inn", evidence="forever-verified", nav={mapID=1451,x=0.520,y=0.396,evidence="classic-coordinate"} } },
                },
            },
            ["Enchant Shield - Greater Stamina"] = {
                kind="vendor-formula",
                itemID=16217,
                bind="BOP",
                limited=true,
                evidence="forever-verified",
                options={
                    Horde={ { name="Daniel Bartlett", zone="Undercity", area="Trade Quarter", evidence="forever-verified", nav={mapID=1458,x=0.643,y=0.374,evidence="classic-coordinate"} } },
                    Alliance={ { name="Mythrin'dir", zone="Darnassus", area="Craftsmen's Terrace", evidence="forever-verified", nav={mapID=1457,x=0.610,y=0.174,evidence="classic-coordinate"} } },
                },
                note="Bind on Pickup and limited supply.",
            },
            ["Runed Arcanite Rod"] = {
                kind="vendor-formula",
                evidence="forever-verified",
                options={
                    Neutral={ { name="Lorelae Wintersong", zone="Moonglade", area="Nighthaven", evidence="forever-verified", nav={mapID=1450,x=0.482,y=0.401,evidence="classic-coordinate"} } },
                },
            },
            ["Enchant Cloak - Superior Defense"] = {
                kind="vendor-formula",
                evidence="forever-verified",
                options={
                    Neutral={ { name="Lorelae Wintersong", zone="Moonglade", area="Nighthaven", evidence="forever-verified", nav={mapID=1450,x=0.482,y=0.401,evidence="classic-coordinate"} } },
                },
            },
        },
    },

    vendors = {
        ENCHANTING = {
            ["Crystal Vial"] = {
                options={ Neutral={ { name="Mishta", zone="Silithus", area="Cenarion Hold", evidence="forever-verified", nav={mapID=1451,x=0.498,y=0.364,evidence="classic-coordinate"} } } },
                note="Also sold by many trade-supply vendors.",
            },
        },
    },
}
