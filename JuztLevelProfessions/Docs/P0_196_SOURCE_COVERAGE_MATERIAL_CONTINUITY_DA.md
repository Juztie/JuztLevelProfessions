# P0 fase 35 – v0.34.196: kildekatalog, materialekontinuitet og gathering-milepæle

**Dato:** 24. oktober 2026. **Baseline/rollback:** v0.34.195; aktuel kode **0.34.196-p0-source-coverage-material-continuity**. **Ingame-status: IKKE TESTET**. Release-klarhedsmål 3. november 2026; 4. november er spilledag, ikke testdag.

## Gennemført

1. `Data/ForeverEngineeringGuideFacts196.lua` indeholder 38 publicerede Engineering guide-skillkrav fra Wowhead Forever (guide opdateret 15. oktober 2026), koblet til **entydige, eksakte navne i DB70450** og DB70450 SpellID. Kilden forbinder IKKE selv alle SpellID'er med skillkravet. Derfor klassificeres samtlige poster som `FOREVER_GUIDE_NAME_JOIN_ONLY` og **IKKE selvstændig ID-/lærings-/NPC-autoritet**. Seks krav overlapper v194 eksakte kontroller og har lavere autoritet; 32 øvrige poster er nye svagere kildefelter. Ingen NPC/coords/nav blev tilføjet. Alle kilder og kvalitetsgrænser findes i `QA/ENGINEERING_GUIDE_NAME_JOIN_196.csv`. Primær ekstern kilde: https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes.
2. `ProfessionRecipeMinimumGate`: specialiseret navne-/sourceBuild-/SpellID-/URL-kontrol; direkte SpellID-evidens fra 192/193/194 har altid forrang. Uenighed med guidefaktum markeres `guideMinimumConflict`. Navnejoin kan give read-only skillforecasts og påvirker aldrig `LEARN_RECIPE`-oprettelse som eksakt recipebevis, source-NPC, craftingrettigheder eller destination. Foreløbigt kildekrav er ikke bevis for, at opskriften er lært, at den kan findes hos en bestemt trainer eller at spillets live skillkrav er uændret.
3. `UniversalCurrentStep:Apply` kopierer `required/perCraft/missing/bagsKnown/bags/priceStatus` fra den aktuelle anbefaling til samme read-only Planner-step. Tidligere forsvandt disse felter under planprojektion, og downstream services kunne genklassificere et kendt lager som UNKNOWN. Feltet `inventoryObservationType=CURRENT_RECOMMENDATION_ADVISORY` gør kopien eksplicit ikke-native. Ny planopbygning bruger altid en ny kopi – gammel current step ændres ikke ved bags/skill-replan.
4. `UniversalCurrentStep:PlanTo300` for **HERBALISM/MINING/SKINNING/FISHING** publicerer 1–300-projektionsmilepæle i de konventionelle foreløbige bånd 1–75, 75–150, 150–225, 225–300, men alle med `GATHER_REFERENCE`, `VERIFY_ACTUAL_SKILL_CAP`, `nodeConfirmed=false`, `routeUnqualified=true`, `navigationQualified=false`, `nativeDispatchAllowed=false`. Faktiske nodes, fishing catches, mob eligibility, rank trainers og transport kan ikke antages og skal verificeres; det er IKKE komplet 1–300 rute.

## Kvalitetssikring

- **62/62 Lua-regressionstests** inklusive alle 60 tidligere, og **369/369 TOC-Lua syntax-PASS**. Ingen beskyttede native API-kald udført.
- 38/38 DB70450-navnejoin kontrolleres. Negative cases: spoofed name/SpellID, autoritetskonflikt, manglende inventory, KNOWN(0), fuld beholdning, AH med/uden priser, isolation af kopierede planer, ingen illegitim native/canonical nav.
- 32 noncraft gathering-milestone-preview cases og **216** rådgivende scenarier for alle 12 professioner: 3 skillstates × 3 strategier × AH/no-AH. I denne tests særskilte sparse-learned model er der **9.204 udækkede hypotetiske crafting-skill-overgange**. Det er IKKE direkte sammenligneligt med v193's 855.
- Ingame acceptance **0**; recipes/trainer/teaching-item/actual yield/skill-up/receipt/reload er ikke klientverificeret i denne version. Eksisterende navigation, native dispatch, ledger og SavedVariables er uændrede.

## Fortsat kritisk P0

- Komplet og troværdig **1–300** pr. alle 12 professioner mangler fortsat. Kvalificér præcis SpellID→required skill→teaching item→vendor/trainer/NPC/drop/quest→faction for faktisk valgte recipes. Publicer UNKNOWN frem for fiktivt waypoint.
- Test live client APIs og nøjagtig Current Step→material/bank/AH→owner/JuztTravel/JuztTom→manual/native-kontrol→kvittering→replan med stateful scenarios, /reload og zoneskift. Status her forbliver offline simulation.
- AH er valgfri; UNKNOWN er ikke 0; native-dispatch kan kun få selvstændigt aktuelt sikkerhedsbevis, aldrig fra guide/forecast/named actor.

**Rollback:** Den uændrede v195-installations-ZIP i `ROLLBACK/INSTALL_v0.34.195.zip`, SHA-256 i manifest. Fuld autonom overdragelse med `READ_ME_FIRST.md` i rod, alle originale referencefiler, kumulativ audit, historik, testfixtures, manifests og kilde-delta. 
