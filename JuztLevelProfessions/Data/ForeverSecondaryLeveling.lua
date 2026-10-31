local _, JLP = ...
-- Guide quantities are Wowhead Forever *estimated purchases/crafts*, not guaranteed skill-ups.
-- Recipe labels below are guide recommendations; no independent spell-ID proof is implied.
-- Potion vial/spice quantities are not specified by the source shopping-list table.
local root="https://www.wowhead.com/forever/"
local function ingredient(id,name,count,source)
    return {itemID=id,name=name,quantity=count,source=source,
        evidenceURL=root.."item="..id}
end
local function step(from,to,name,crafts,materials,gate)
    return {skillMin=from,skillMax=to,recipe=name,estimatedCrafts=crafts,
        materials=materials,accessGate=gate,countsAreGuideEstimates=true}
end
JLP.data.foreverSecondaryLeveling={
    contract="forever-secondary-guide-plans-v1",basis="WOWHEAD_FOREVER_GUIDE",capturedAt="2026-10-08",
    nativeDispatchAllowed=false,requiresLiveQA=false,
    professions={
        COOKING={skillLineID=185,guideURL=root.."guide/professions/cooking/overview-leveling",
            coverageEnd=225,unknownBeyond=225,shoppingListCompleteForListedRoute=true,
            -- Wowhead Forever Cooking guide names/minimums joined by exact SpellID
            -- to the existing Build70450RecipeCatalogue at runtime. This is NOT
            -- a full leveling route and specifies no estimated craft counts.
            advancedCookingReferences={
                {spellID=1250153,name="Raptor Rouladen",guideMinimumSkill=225,publicBaseOutputQuantity=2,publicOutputItemID=250076,publicOutputURL=root.."spell=1250153/raptor-rouladen"},
                {spellID=1250142,name="Savory Stag Sliders",guideMinimumSkill=225,publicBaseOutputQuantity=2,publicOutputItemID=250065,publicOutputURL=root.."spell=1250142/savory-stag-sliders"},
                {spellID=1319313,name="Plated Armorfish",guideMinimumSkill=225},
                {spellID=1249968,name="Wicked Smoothie",guideMinimumSkill=250,publicBaseOutputQuantity=2,publicOutputItemID=249876,publicOutputURL=root.."spell=1249968/wicked-smoothie"},
                {spellID=1249962,name="Sage's Tea",guideMinimumSkill=250},
                {spellID=1250150,name="Raging Raptor Ribs",guideMinimumSkill=275},
                {spellID=1250149,name="Swiftstrike Steak",guideMinimumSkill=275},
                {spellID=1250158,name="Clam Linguine",guideMinimumSkill=275},
                {spellID=1250152,name="Prehistoric Pulled Raptor",guideMinimumSkill=275,publicBaseOutputQuantity=2,publicOutputItemID=250075,publicOutputURL=root.."spell=1250152/prehistoric-pulled-raptor"},
                {spellID=1250145,name="Savory Turtle Stew",guideMinimumSkill=275,publicBaseOutputQuantity=2,publicOutputItemID=250068,publicOutputURL=root.."spell=1250145/savory-turtle-stew"},
                {spellID=1250148,name="Steaming Stag Steak",guideMinimumSkill=275,publicBaseOutputQuantity=2,publicOutputItemID=250071,publicOutputURL=root.."spell=1250148/steaming-stag-steak"},
                {spellID=1250147,name="Bear Bruscitti",guideMinimumSkill=275,publicBaseOutputQuantity=2,publicOutputItemID=250070,publicOutputURL=root.."spell=1250147/bear-bruscitti"},
                {spellID=1250143,name="Soaring Pamplona",guideMinimumSkill=275,publicBaseOutputQuantity=2,publicOutputItemID=250066,publicOutputURL=root.."spell=1250143/soaring-pamplona"},
                {spellID=1294014,name="Sweetpaw Jam",guideMinimumSkill=275,publicBaseOutputQuantity=2,publicOutputItemID=267341,publicOutputURL=root.."spell=1294014/sweetpaw-jam"},
                {spellID=1250144,name="Bat Hachee",guideMinimumSkill=275,publicBaseOutputQuantity=2,publicOutputItemID=250067,publicOutputURL=root.."spell=1250144/bat-hachee"},
                {spellID=1250146,name="Flank au Poivre",guideMinimumSkill=275,publicBaseOutputQuantity=2,publicOutputItemID=250069,publicOutputURL=root.."spell=1250146/flank-au-poivre"},
            },
            notes="Fish route only; exact skill-up counts and vendor availability are not guaranteed.",
            gates={
                {skill=150,name="Expert Cookbook",kind="VENDOR_BOOK",itemID=16072,
                    requiredCookingSkillToUse=125,
                    itemSourceURL=root.."item=16072/expert-cookbook",
                    factionVendors={ALLIANCE="Shandrina · Ashenvale",HORDE="Wulan · Desolace"},
                    verifiedVendors={
                        ALLIANCE={npcID=3955,npcName="Shandrina",zone="Ashenvale",x=49.6,y=67.0,
                            npcSourceURL=root.."npc=3955/shandrina",faction="Alliance"},
                        HORDE={npcID=12033,npcName="Wulan",zone="Desolace",x=26.2,y=69.8,
                            npcSourceURL=root.."npc=12033/wulan",faction="Horde"}},
                    vendorStock="UNKNOWN",actualLearned="UNKNOWN",routeEligible=false},
                {skill=225,name="Clamlette Surprise",kind="ARTISAN_QUEST",questID=6610,
                    npcID=8125,npcName="Dirge Quikcleave",characterLevel=35,
                    questSourceURL=root.."quest=6610/clamlette-surprise",
                    npcSourceURL=root.."npc=8125/dirge-quikcleave",
                    zone="Tanaris",x=52.6,y=28.0,
                    requirementQuantitiesEvidence="FOREVER_NPC_PUBLIC_COMMENTS_NOT_SERVER_ATTESTED",
                    requirements={{itemID=12207,name="Giant Egg",quantity=12},
                        {itemID=7974,name="Zesty Clam Meat",quantity=10},
                        {itemID=8932,name="Alterac Swiss",quantity=20}},
                    source="Dirge Quikcleave · Gadgetzan",completion="UNVERIFIED",
                    actualQuestAvailable="UNKNOWN",routeEligible=false}},
            steps={
                step(1,50,"Brilliant Smallfish",52,{ingredient(6291,"Raw Brilliant Smallfish",52,"FISH_OR_AH")}),
                step(50,100,"Longjaw Mud Snapper",55,{ingredient(6289,"Raw Longjaw Mud Snapper",55,"FISH_OR_AH")}),
                step(100,150,"Bristle Whisker Catfish",55,{ingredient(6308,"Raw Bristle Whisker Catfish",55,"FISH_OR_AH")}),
                step(150,175,"Bristle Whisker Catfish",65,{ingredient(6308,"Raw Bristle Whisker Catfish",65,"FISH_OR_AH")},"Expert Cookbook"),
                step(175,225,"Mithril Head Trout",55,{ingredient(8365,"Raw Mithril Head Trout",55,"FISH_OR_AH")})}},
        FIRST_AID={skillLineID=129,guideURL=root.."guide/professions/first-aid/overview",
            coverageEnd=225,unknownBeyond=225,shoppingListCompleteForListedRoute=true,
            sourceGuideUpdated="2026-10-23",
            notes="Forever guide 1-225 BANDAGE route; craft counts are estimated; 225-300 source options are conditional, not complete skill-up guarantees.",
            gates={
                {skill=150,name="Expert First Aid - Under Wraps",kind="VENDOR_BOOK",itemID=16084,
                 itemSourceURL=root.."item=16084/expert-first-aid-under-wraps",requiredSkillToUse=125,
                 npcID=13476,npcName="Balai Lok'Wein",zone="Dustwallow Marsh",faction="Horde",
                 guideX=36.4,guideY=30.4,coordinateAuthority="PUBLIC_GUIDE_ONLY_NOT_CANONICAL",
                 npcSourceURL=root.."npc=13476/balai-lokwein",vendorStock="UNKNOWN",routeEligible=false},
                {skill=180,name="Manual: Heavy Silk Bandage",kind="VENDOR_MANUAL",itemID=16112,
                 itemSourceURL=root.."item=16112/manual-heavy-silk-bandage",
                 npcID=13476,npcName="Balai Lok'Wein",faction="Horde",vendorStock="UNKNOWN",routeEligible=false},
                {skill=210,name="Manual: Mageweave Bandage",kind="VENDOR_MANUAL",itemID=16113,
                 itemSourceURL=root.."item=16113/manual-mageweave-bandage",
                 npcID=13476,npcName="Balai Lok'Wein",faction="Horde",vendorStock="UNKNOWN",routeEligible=false},
                {skill=225,name="Triage",kind="ARTISAN_QUEST",questID=6622,
                 questSourceURL=root.."quest=6622/triage",characterLevel=35,
                 npcID=12920,npcName="Doctor Gregory Victor",npcSourceURL=root.."npc=12920/doctor-gregory-victor",
                 zone="Arathi Highlands",faction="Horde",guideX=73.4,guideY=36.8,
                 coordinateAuthority="PUBLIC_GUIDE_ONLY_NOT_CANONICAL",completion="UNVERIFIED",routeEligible=false}},
            -- 225-300 guidance: individual Forever spell pages plus NPC 12920
            -- comments give these possible learning windows. They are NOT
            -- validated skill-up probabilities or promised craft counts.
            advancedFirstAidReferences={
                {spellID=10840,name="Mageweave Bandage",guideMinimumSkill=225,sourceWindowEnd=240,
                    learningSource="PUBLIC_GUIDE_INFERENCE",yieldFromForever=2},
                {spellID=10841,name="Heavy Mageweave Bandage",guideMinimumSkill=240,sourceWindowEnd=260,
                    learningSource="NPC_COMMENT_REFERENCE",yieldFromForever=nil},
                {spellID=18629,name="Runecloth Bandage",guideMinimumSkill=260,sourceWindowEnd=290,
                    learningSource="NPC_COMMENT_REFERENCE",yieldFromForever=2},
                {spellID=18630,name="Heavy Runecloth Bandage",guideMinimumSkill=290,sourceWindowEnd=300,
                    learningSource="NPC_COMMENT_REFERENCE",yieldFromForever=2}},
            steps={
                step(1,40,"Linen Bandage",45,{ingredient(2589,"Linen Cloth",45,"DROP_OR_AH")}),
                step(40,80,"Heavy Linen Bandage",65,{ingredient(2589,"Linen Cloth",130,"DROP_OR_AH")}),
                step(80,115,"Wool Bandage",50,{ingredient(2592,"Wool Cloth",50,"DROP_OR_AH")}),
                step(115,150,"Heavy Wool Bandage",50,{ingredient(2592,"Wool Cloth",100,"DROP_OR_AH")}),
                step(150,180,"Silk Bandage",45,{ingredient(4306,"Silk Cloth",45,"DROP_OR_AH")},"Expert First Aid - Under Wraps"),
                step(180,210,"Heavy Silk Bandage",45,{ingredient(4306,"Silk Cloth",90,"DROP_OR_AH")},"Manual: Heavy Silk Bandage"),
                step(210,225,"Mageweave Bandage",20,{ingredient(4338,"Mageweave Cloth",20,"DROP_OR_AH")},"Manual: Mageweave Bandage")}},
    },
    fishing={guideURL=root.."guide/professions/fishing/overview-leveling",coverageEnd=300,
        note="Zone skill minima and 100% catch thresholds are effective fishing-skill guidance, not coordinates, catch probabilities or fishing skill-up guarantees.",
        tiers={
            {zone="Starter zones",minSkill=1,guaranteedCatchSkill=25,skillMin=1,skillMax=75},
            {zone="Capital cities",minSkill=1,guaranteedCatchSkill=75,skillMin=75,skillMax=150},
            {zone="Dustwallow Marsh",minSkill=130,guaranteedCatchSkill=225,skillMin=150,skillMax=225},
            {zone="Stranglethorn Vale (excluding Jaguero Isle)",minSkill=130,guaranteedCatchSkill=225,skillMin=150,skillMax=225},
            -- Wowhead Forever guide updated 2026-10-24: a suggested 225-300
            -- FISHING AREA, NOT a validated catch/skill-up or transport route.
            {zone="Tanaris",minSkill=205,guaranteedCatchSkill=300,skillMin=225,skillMax=300,
             advisorySource="WOWHEAD_FOREVER_GUIDE_2026_10_24",realPoolSpawnVerified=false,
             skillGainGuaranteed=false,ownerWaypointQualified=false},
        },
        expert={skill=150,name="Expert Fishing - The Bass and You",source="Old Man Heming · Booty Bay",vendorStock="UNKNOWN"},
        artisanQuest={questID=6607,name="Nat Pagle, Angler Extreme",npcID=12919,
          npcName="Nat Pagle",zone="Dustwallow Marsh",minimumCharacterLevel=35,
          requiredFishingSkill=225,sourceURL=root.."guide/professions/fishing/overview-leveling",
          questURL=root.."quest=6607/nat-pagle-angler-extreme",
          researchCoordinates={x=58.6,y=60.0,mapName="Dustwallow Marsh"},
          requiredFishNames={"Feralas Ahi","Misty Reed Mahi Mahi",
            "Sar'theris Striker","Savage Coast Blue Sailfin"},
          npcIdentitySource="WOWHEAD_FOREVER_NPC_PAGE_LINK_FROM_GUIDE",
          questCompleted="UNKNOWN",questAvailable="UNKNOWN",npcSpawnVerified=false,
          coordinateAuthority=false,navigationQualified=false,readOnly=true,
          nativeDispatchAllowed=false},
        starterLure={untilSkill=25,name="Shiny Bauble"},
    },
}

-- BEGIN QUALIFIED RELEASE CLOSURE70532
-- Indexed primary fields and explicit legacy fallback, never current client proof.
local closure=JLP.data.foreverSecondaryLeveling
closure.professions.COOKING.kitUseReference={["itemID"]=279981,["useSpellID"]=1307227,["minimumCooking"]=1,["referenceCooldownSeconds"]=300,["maxStack"]=20,["allowsCooking"]=true,["sourceURL"]="https://www.wowhead.com/forever/item=279981/basic-campfire-kit",["evidence"]="INDEXED_FOREVER_PRIMARY_FIELDS_NOT_LIVE_VERIFIED",["consumerMETFromUse"]=false,["spawnedObjectIDStatus"]="UNKNOWN",["radiusStatus"]="UNKNOWN",["durationStatus"]="UNKNOWN"}
closure.professions.COOKING.artisanQuestReference={["questID"]=6610,["sourceURL"]="https://www.wowhead.com/forever/quest=6610/clamlette-surprise",["evidence"]="INDEXED_FOREVER_PRIMARY_FIELDS_NOT_LIVE_VERIFIED",["rewardProfession"]="COOKING",["observedCapRequired"]=true,["currentObjectiveItemJoinQualified"]=false,["referenceObjectives"]={{["name"]="Giant Egg",["referenceItemID"]=12207,["referenceCount"]=12},{["name"]="Zesty Clam Meat",["referenceItemID"]=7974,["referenceCount"]=10},{["name"]="Alterac Swiss",["referenceItemID"]=8932,["referenceCount"]=20}},["conflict"]="Non-Forever MoP/Retail10eggs/FineAgedCheddar is not this Forever-indexed12eggs/AlteracSwiss reference; current API remains authority"}
closure.fishing.speciesZoneReferences={[8365]={["itemID"]=8365,["name"]="Raw Mithril Head Trout",["sourceURL"]="https://www.wowhead.com/forever/item=8365/raw-mithril-head-trout",["mapIDs"]={1422,1445,1450,1416,1434,1444,1417,1425,1443,1435,1447,1441,1449,1448,1440,1423,1424},["evidence"]="INDEXED_FOREVER_PRIMARY_FIELDS_NOT_LIVE_VERIFIED",["operationalAreaQualified"]=true,["catchRateStatus"]="UNKNOWN",["skillUpChanceStatus"]="UNKNOWN",["minimumCommentOnly"]=130},[6359]={["itemID"]=6359,["name"]="Firefin Snapper",["sourceURL"]="https://www.wowhead.com/forever/item=6359/firefin-snapper",["mapIDs"]={1434,1447,1445,1437,1446,1444,1424,1443,1425,1442,1435,1417,1440,1413},["evidence"]="INDEXED_FOREVER_PRIMARY_FIELDS_NOT_LIVE_VERIFIED",["operationalAreaQualified"]=true,["catchRateStatus"]="UNKNOWN",["skillUpChanceStatus"]="UNKNOWN",["minimumCommentOnly"]=55},[13422]={["itemID"]=13422,["name"]="Stonescale Eel",["sourceURL"]="https://www.wowhead.com/forever/item=13422/stonescale-eel",["mapIDs"]={1447,1434,1446,1444,1425,1423},["evidence"]="INDEXED_FOREVER_PRIMARY_FIELDS_NOT_LIVE_VERIFIED",["operationalAreaQualified"]=true,["catchRateStatus"]="UNKNOWN",["skillUpChanceStatus"]="UNKNOWN",["minimumCommentOnly"]=nil},[4603]={["itemID"]=4603,["name"]="Raw Spotted Yellowtail",["sourceURL"]="https://www.wowhead.com/forever/item=4603/raw-spotted-yellowtail",["mapIDs"]={1444},["evidence"]="LEGACY_COMMENT_ONLY_NOT_QUALIFIED_FOREVER_FISHING_LOCATION_TABLE",["operationalAreaQualified"]=false,["catchRateStatus"]="UNKNOWN",["skillUpChanceStatus"]="UNKNOWN",["minimumCommentOnly"]=205}}
closure.fishing.zoneApproachReferences={[1434]={["provider"]="OWNER_SERVICE",["category"]="BANK",["serviceID"]="S035",["zone"]="Stranglethorn Vale"},[1435]={["provider"]="OWNER_SERVICE",["category"]="TRAINER",["serviceID"]="TR066",["zone"]="Swamp of Sorrows"},[1443]={["provider"]="SECONDARY_ACTOR",["actor"]="WULAN",["zone"]="Desolace"},[1444]={["provider"]="OWNER_SERVICE",["category"]="TRAINER",["serviceID"]="TR083",["zone"]="Feralas"},[1445]={["provider"]="SECONDARY_ACTOR",["actor"]="NAT",["zone"]="Dustwallow Marsh"},[1446]={["provider"]="SECONDARY_ACTOR",["actor"]="GIKKIX",["zone"]="Tanaris"}}
closure.fishing.artisanQuest.objectiveReference={["questID"]=6607,["sourceURL"]="https://www.wowhead.com/forever/quest=6607/nat-pagle-angler-extreme",["evidence"]="INDEXED_FOREVER_PRIMARY_FIELDS_NOT_LIVE_VERIFIED",["rewardProfession"]="FISHING",["observedCapRequired"]=true,["objectives"]={{["key"]="MISTY_REED",["name"]="Misty Reed Mahi Mahi",["area"]="Misty Reed Strand",["zone"]="Swamp of Sorrows",["mapID"]=1435,["referenceItemID"]=16970},{["key"]="SARTHERIS",["name"]="Sar'theris Striker",["area"]="Sar'theris Strand",["zone"]="Desolace",["mapID"]=1443,["referenceItemID"]=16968},{["key"]="FERALAS_AHI",["name"]="Feralas Ahi",["area"]="Verdantis River",["zone"]="Feralas",["mapID"]=1444,["referenceItemID"]=16967},{["key"]="SAVAGE_COAST",["name"]="Savage Coast Blue Sailfin",["area"]="Savage Coast",["zone"]="Stranglethorn Vale",["mapID"]=1434,["referenceItemID"]=16969}}}
-- END QUALIFIED RELEASE CLOSURE70532
