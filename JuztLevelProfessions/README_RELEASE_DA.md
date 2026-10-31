# AKTUEL INSTALLER v0.34.236 — P0-236

Dette er en installerbar udviklingsversion, **ikke** en fuldt klientaccepteret 1–300-release. Ny First Aid-kontinuitet kombinerer 1–225 og 225–300 med read-only learned-, material-, rank- og source-metadata. JuztTravel/JuztTom er offline-modultestet med mock C_Map; faktiske WoW-klientrammer og rigtig transport er ikke gennemført. Udviklingsmål 3. november, release/play 4. november. Tidligere historik følger.

--- HISTORISK DOKUMENTATION ---

# AKTUEL RELEASE v0.34.235 – P0-235

**Aktiv:** `0.34.235-p0-profession-exact-windows-route-integration`. Nye source-validated read-only alternative opskriftsvinduer for seks primære professioner (9 kvalificerede, 3 på HOLD), source-revocation, strategibaseret kilde-sammenligning og eksisterende Current Step/PlanTo300-integration. Den hidtidige Source/BOM/Owner/Travel/Tom/native dispatch og alle tidligere P0-231–234-fix er bevaret. **149/149 offline-regressioner og 398/398 TOC Lua5.4-syntaks**; Lua5.1 og reel WoW Forever-klient er ikke verificeret. **0/12** komplette klientgodkendte 1–300-ruter. Deadline 03-11-2026; 04-11 er releasedag, ikke testdag.

---


# AKTUEL RELEASE v0.34.233 – P0-233

**Aktiv:** `0.34.233-p0-primary-six-forever-source-windows`. 15 curated Forever spellreferencer for Alchemy, Blacksmithing, Engineering, Leatherworking, Tailoring og Enchanting; 14 felter med reagens/navneparitet mod DB70450 (13 også med dokumenterede skillfarvegrænser). En Alchemy-kilde har ufuldstændig DB-record; UNKNOWN bevares. `UniversalCurrentStep` bevarer tidligere Planner-beslutninger og bruger kun det nye kildebevis som read-only supplement/fallback. Eksisterende Materialer, AH, Owner, JuztTravel/JuztTom og NativeDispatchService er bevaret. **143/143 offline-regressioner; 396/396 Lua5.4 syntaks**. Fuldt klientverificerede 1–300-ruter: **0/12**. Udviklingsmål 03-11-2026; 04-11 er spilledag, ikke testdag.

--- TIDLIGERE VERSIONER / HISTORISK STATUS ---

# AKTUEL RELEASE v0.34.232 – First Aid Artisan-kildeløb 225–300

**Aktiv 0.34.232-p0-forever-first-aid-artisan-source-route.** Fire kildeunderbyggede recipe-/materialebånd integreret i read-only Current Step og PlanTo300, med faction quest/NPC-reference, eksplicit unknown inventory, sikre outputkonflikter og manuel handling. 140/140 OFFLINE-regressioner, 395/395 Lua 5.4-syntax. 0/12 fuldt klientverificerede 1–300, ingen ændring i protected/native handlinger. Tidligere auditrettelser bevaret.

--- HISTORISK STATUS v0.34.231 ---

# AKTUEL RELEASE v0.34.231 – Uafhængig audit: P0/P1 kodefund

**Aktiv kode:** `0.34.231-p0-independent-audit-remediation`. Direkte videreført fra verificeret v0.34.230.

- F01: Tidligere positiv native-plan tilbagekaldes i advisory Apply ved negativ/ukendt learned eller live difficulty; native dispatcher uændret.
- F02: Kilde-merge afviser recipe-name-konflikt ved fælles SpellID.
- F03: Minimum-skill og cross-profession producentindekser er tilføjet, men kvitteringer genvalideres ved hvert opslag.
- F04: Ukendt bag/bank er UNKNOWN og må ikke omdannes til pris, 0-stock eller konkret eksternt køb.
- F05: Real-modul harness udvidet med faktisk IntegratedDestinationOwner og event-/completionkæde. World-walkability og faktisk JuztTom frame verificeres ikke her.
- F06: 96 læseprioritet udvides betinget med højst 384 ved ingen lært kandidat. En større receptliste kan fortsat kræve næste opslag; ingen rettighed skabes.
- F07: Aktuel live difficulty får forrang over historisk gray; live GRAY giver eksplicit VERIFY.

Alle professioner og brugerens mål 1–300 består fortsat. 0/12 er fuldt klientverificeret. Native CraftRecipe/CraftEnchant og owner-sikkerhed er ikke ændret.

Deadline: 3. november 2026; 4. november er releasedag uden planlagt test.

---

## HISTORISK v0.34.230 (uændret dokumentation)

# AKTUEL RELEASE v0.34.230 – Source-bounded Skinning/BOM/current chain

**Aktiv kode:** `0.34.230-p0-skinning-eligibility-source-budget-replay`. Ny `ForeverSkinningEligibility230` beregner dokumenterede mob-skillgrænser og forskningsområde-hints; `ProfessionSourceBudget230` revurderer hver kilde og producerer en betinget, read-only 1–300 materialeregistrering for faktisk valgte forecast-trin. Ingen verificeret fuld professionsrute, ingen automatisk waypoint, ingen ændringer i beskyttet CraftRecipe/CraftEnchant. 135/135 OFFLINE regressioner, 394/394 Lua syntaks. Fuld audit og instruktion i separat overdragelses-ZIP. 3. november prelaunch-deadline, 4. november release og ikke testdag.

---

# AKTUEL RELEASE v0.34.230 – Source-bounded Skinning/BOM/current chain

**Aktiv kode:** `0.34.230-p0-skinning-eligibility-source-budget-replay`. Ny `ForeverSkinningEligibility230` beregner dokumenterede mob-skillgrænser og forskningsområde-hints; `ProfessionSourceBudget230` revurderer hver kilde og producerer en betinget, read-only 1–300 materialeregistrering for faktisk valgte forecast-trin. Ingen verificeret fuld professionsrute, ingen automatisk waypoint, ingen ændringer i beskyttet CraftRecipe/CraftEnchant. 134/134 OFFLINE regressioner, 394/394 Lua syntaks. Fuld audit og instruktion i separat overdragelses-ZIP. 3. november prelaunch-deadline, 4. november release og ikke testdag.

---

# AKTUEL RELEASE v0.34.229 – P0 konkret kilde-, Artisan- og Current Step-kæde

**Aktiv kode:** `0.34.229-p0-exact-minimum-learning-bom-currentchain`. Ny `ProfessionFieldChain229` kvalificerer præcist recipeID/navn/reagensparitet, kilde-output, undervisnings- og faction-hints samt kendt/ukendt inventory og betinget BOM for ét craft. Eksakte skillminimummer uden progressionstøtte bliver kun read-only research-leads; konflikt blokkerer en advisory manuel craftanbefaling uden at ændre native dispatch. Fishing 225–300 Tanaris fra Wowhead Forever, Artisan-quest ved 225 for Fishing/Cooking/First Aid (Faction-kontrol). 130/130 OFFLINE regressioner og 392/392 TOC Lua syntaks PASS; 0/12 fuldt klientverificerede 1–300. Se selvstændig kompakt QA-/overdragelses-ZIP for detaljer. Historiske versionsnoter nedenfor er bevaret.

---

# AKTUEL RELEASE v0.34.228 – P0 12-professions kildecoverage og sessionskvitteringer

**Aktiv kode:** `0.34.228-p0-twelve-source-coverage-stateful-chain`. `PlanTo300` publicerer nyt felt `progressionSourceCoverage228` med dokumenterede skillreferencer, huller og separate source/skill/receipt-gates. En `/reload` i samme sekund genbruger ikke længere diagnostic correlation sessionID. 124/124 OFFLINE regressioner, 391/391 Lua-syntaks PASS; 0/12 komplet klientverificeret 1–300. Se QA-overdragelsesarkivet for fuld revision og begrænsninger. Historiske versionstekster nedenfor er bevaret.

---

# AKTUEL RELEASE v0.34.227 – P0 Source Current Step material/navigation review

**Aktiv kode:** `0.34.227-p0-stitched-current-step-material-nav-review`; installerbar addon i en ZIP med denne mappe i roden. Ny source-only Current Step-review for Blacksmithing/Leatherworking, 121/121 offline QA og 390/390 syntakskontrol. 0/12 klientverificerede 1–300. Beskrivelser nedenfor er tidligere revisionshistorik. Den komplette handoff-/QA-ZIP har versionsmanifest, kumulativ hovedaudit og originalreferencer.

---

# Aktuel release v0.34.208 – 0.34.208-p0-secondary-live-context-and-inventory-integrity

**Dato:** 24. oktober 2026. **Baseline/rollback:** v0.34.207. **Ingame:** IKKE TESTET. **Offline:** 85/85 regressioner, 375/375 Lua-syntaks PASS.

P0-208: Cooking/First Aid avanceret read-only Current Step kan bruge genkontrolleret aktuel professionspanel- og recipe-læringsstatus (LEARNED/NOT_LEARNED/UNKNOWN), flygtigt outputinterval med output-ID-paritet og sikker handlingstekst. Ingen native autorisation. Guidebeholdning med ukendt bags/bank giver ingen falsk indkøbsmangel. Fire præcise Cooking teaching-item-relationer uden tidligere dubletter. Ingen komplet 1–300 eller ingame-accept. Næste P0: dokumenterede 1–300 dataruter for alle 12 med kildesikre lærer-NPCer og realistiske hændelsesforløb.

## Historisk status (bevarede revisioner)

# Aktuel release v0.34.205 – 0.34.205-p0-first-aid-source-route-correction

**Dato:** 24. oktober 2026. **Baseline/rollback:** v0.34.204. **Ingame-status:** IKKE TESTET. **Offline:** 81/81 regressioner, 373/373 Lua-syntakskontroller PASS.

P0-205: First Aid 1–225 bandageguide (7 kildeintervalrækker), ti nye eksakte, betingede First Aid output-/reagenskrydsninger (samlet 35), rådgivende læringsreferencer for 225–300. Materialemængder og crafttal bygger på guideestimat, IKKE live kvittering. NPC-/guidekoordinater giver ikke kanonisk JuztTravel/JuztTom navigation. Native sikkerhed uændret. Måldato 3. november; releasedag 4. november uden planlagt test.

## Ældre versionshistorik

# Aktuel status v0.34.196 – 0.34.196-p0-source-coverage-material-continuity

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

---

## Historisk arkivtekst følger

# Aktuel v0.34.195 — kildebaseret læringsadgang og live Current Step-konsistens

Opgraderet fra v0.34.194. Ny version indeholder konsistent read-only LEARN/VERIFY for seks source-backed craftprofessioner, strengere provenienskonflikter, 60/60 offline tests, 368/368 syntaks; ingen produktions-/native tilladelser udvidet. Ikke fuldt 1–300-produktionsgodkendt; ingen WoW Forever ingame-tests. Rollback er v0.34.194. Deadline 03.11.2026; 04.11.2026 er spilledag uden tests. Se `Docs/P0_195_EXACT_ACCESS_AND_LIVE_PARITY_DA.md`.

# v0.34.194 – Seven-crafting selected source facts and simulator

# P0 Phase 33 / v0.34.194 – Seven-crafting recipe data and replan simulation

- This is a source-backed increment, NOT a claim of complete 1–300 guides or an ingame test.
- 14 selected precise minimumskill references from Forever spell/guide pages in six professions; Cooking Charred Wolf Meat is handled as a **starter/source/workstation hint**, NOT assigned a fabricated skill minimum. Cross-version corroborated min 1 facts for Enchanting 7421 and Blacksmithing 2660 are flagged in `referenceKind`.
- New public acquisition hints include Alchemy named drop mobs, generic First Aid trainer and Cooking Fire. None is an exact teaching-item-to-NPC join; no faction, coordinate or waypoint is synthesized.
- Recipe/SPELLID relation verified against existing DB70450 packed catalogue before adding facts.
- AH/no-AH and remembered/updated learned-state/inventory paths are advisory and must replan after material receipt or skill observation. Native execution gates, canonical JuztTravel/JuztTom and `/reload` persistence unchanged.
- Cooking Fire is a normal station; **Camp** workstations are excluded.
- Server offline: 0 WoW Forever ingame tests. Hard target 2026-11-03, 2026-11-04 is play/release day, no testing.

# v0.34.193 – Selected recipe facts and source hints

# P0 Fase 32 – Selected Recipe Access & Acquisition v0.34.193

Baseline v0.34.192. **Targeted, exact SpellID facts from selected AH/no-AH routes**.

- Added 22 Tailoring recipe minimum-skill entries from https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes (public Forever guide dated 2026-10-12), and Enchanting 13882 from its Forever spell page.
- Important conflict: earlier Mooncloth spell reference stated 230, current guide gives 250; earlier Mooncloth Robe 275, guide lists 300. Treat pattern access and actual crafting requirement as different facts; the stricter 250/300 gate is **advisory conservative** and reports `minimumSourceConflict=true`.
- Public acquisition modes: Bright Yellow Shirt vendor Danielle Zipstitch (Duskwood), Dark Silk Shirt generic vendor, Lesser Agility formula drop category. None gives a verified NPC-to-item DB join or canonical navigable waypoint. No automated route is created.
- Learned != accessible; exact skill minima do not certify NPC stock, faction access, source availability, skill-up results, native execution, or all-profession completeness.
- API panel observations and SavedVariables continue to be advisory for planning. Existing owner/gated navigation and ledger unchanged.
- WoW Forever server unavailable for ingame QA; release readiness due 2026-11-03, 2026-11-04 is play day.

# P0 Fase 31 – 0.34.192-p0-recipe-minimum-access-gates

**Udviklingsbaseline:** v0.34.191; **aktuel:** v0.34.192; **rollback:** v0.34.191. **Releaseklarhed senest 3. november 2026; den 4. november er spilledag uden planlagte ingame-tests.**

## Implementeret

- `ProfessionRecipeMinimumGate`: Adskil faktiske recipe-minimumskills og guidevinduer fra DB70450 SkillLineAbility MinRank, som står `1` for 2.636 af de udlæste spellrækker og derfor IKKE repræsenterer et recipe learning-minimum.
- Eksakte Forever-referencer: Bolt of Linen Cloth skill 1, Bolt of Woolen Cloth skill 75, Mooncloth pattern skill 230, Mooncloth Robe pattern skill 275 og Transmute: Iron to Gold skill 225. Gemte source-URL'er og spell-/item-ID'er følger datamodulerne.
- **Konservativ fallback** når eksakt minimum mangler: DOKUMENTERET gult difficulty-skillpoint kan anvendes som en senere sikker planlægningsgrænse, KUN når opskriften er angivet lært. Dette er aldrig en påstand om recipeets faktiske læringsminimum, trainer- eller adgangsstatus. Aktuelt stabilt åbent professionsvindue kan rådgive om en lært opskrift uden fuldt kvalificeret minimum; ikke i syntetisk 1–300-forecast.
- Grey 0 % => recipe afvises før `ceil(1/p)`; undgår uendelige craftestimater.
- Recipe 11479 → teaching item 9304 → Alchemist Pestlezugg, Tanaris, public Forever kildehenvisning. Ingen koordinat opfundet, ingen vendor-stock- eller waypoint-godkendelse.
- 55/55 regressions-PASS, 366/366 TOC Lua-syntaks-PASS, 24/24 12-professions × AH/no-AH syntetiske prognoser PASS. De 24 prognoser har tilsammen **278 udækkede skill-overgange**; ikke komplet live 1–300-validering. 428 planlagte segments i samme scenarier, 410 uden navngiven kildereference. Modellen bruger en bevidst urealistisk "alle learned"-fixture for adgangsfuzzing, ingen egentlig bruger-karakter.

## Åbne P0-opgaver

1. Kvalificér faktisk minimumskill for flere valgte recipes mod eksakt Forever-id og item/Spell-læring; farvegrænse er midlertidig sen adgangsvurdering, ikke reelt minimum. Undgå samtidige spamrequests; prioriter `QA/SELECTED_ROUTE_SOURCE_GAPS_192.csv`.
2. Udfyld faktisk NPC/vendor/trainer/drop/quest-kæde for de valgte recipes og map kun nav tilladelser til `OwnerAuthorizedNavigation`.
3. End-to-end instrumentér reel UI data binding og hele Current Step/materialer/navigation/handling/progression med mockede C_TradeSkillUI, inventory, AH events, professionsskill events, SavedVariables, transport, reload, disconnect, unexpected native receipt; ingen nye native rettigheder.
4. Reducér modeldækningshuller og test realistisk learned-state per skillinterval. 4 gather-professioner har separat referenceplan, ikke en craft-forecaster.

Kilde-evidens: `https://www.wowhead.com/forever/spell=11479/transmute-iron-to-gold`, `https://www.wowhead.com/forever/spell=2963/bolt-of-linen-cloth`, `https://www.wowhead.com/forever/spell=2964/bolt-of-woolen-cloth`, `https://www.wowhead.com/forever/item=18487/pattern-mooncloth-robe`, `https://foreverdiff.com/recipes/mooncloth-10487/`. Fremmede kilder er rådgivende og aldrig native tilladelser.

**Fast handoff:** To ZIPs – standalone installabel addon + komplet kompakt handoff med READ_ME_FIRST.md direkte i roden, hele nye addon, én rollback, rapport, komplet QA, referenceoriginaler, provenance, samt dette udviklingstrin.

---

# Aktiv version 0.34.191 – P0 udvalgte recipe-kilder og navigation/genberegning

**Baseline:** 0.34.190. **Aktuel:** 0.34.191. **Rollback:** 0.34.190. **Deadline:** 3. november 2026. 4. november er spilledag, ikke testdag.

- `RecipeSourcePlanningBridge` bevarer dokumenteret Merchant's Favor/skillkrav og viser et eksakt Horde-questeksempel for Wild Leather Boots (spell 10566, item 8406, quest 2858) uden falsk loot-/NPC-navigationsautoritet.
- Ny `Data/ForeverQuestAcquisition191.lua` angiver 2 x Nightscape Pants, 2 x Nightscape Boots og 2 x Wildvine som dokumenterede questmål; dette er IKKE craftingreagenter og item-ID/bagantal er ikke opfundet.
- `CurrentStepTravelBridge` bruger fortsat kun owner-godkendte waypoints, native crafting- og reloadledger forbliver uændrede.
- **53/53 regressioner og 363/363 TOC Lua-syntakskontroller** bestået offline. 12 professions gennemgået med 24 fulde kildebaserede 1–300-scenarier. 128 route-segmenter på tværs af AH/no AH, 122 uden eksakt navngiven source NPC i kilde-laget. Modelscenariet antog alle recipes lært; ingen påstand om real-life gennemførlighed eller 299 verificerede skillups.
- `/reload` og zoneskift simuleret: checkpoint er ubetroet hensigt; ny position, ændret plan, anden karakter og manipuleret destination afprøvet.
- **Fortsat P0:** lært/ulært i realistiske klientnære scenarier, recipe minimum skill og adgangsgates, verificerede trainer-/vendor-/dropdata for faktisk anbefalede recipes samt egentlig 12×1–300 fuld operationel accept.
- Fast leverance: en komplet installativ ZIP plus én kompakt selvstændig handoff ZIP med `READ_ME_FIRST.md`, QA og relevante originalreferencer.

# JuztLevel Professions — aktiv version 0.34.190-p0-exact-acquisition-crosschecks

**Baseline:** v0.34.189. **Aktuel version:** v0.34.190. **Rollback:** v0.34.189. **Deadline:** 3. november 2026. **4. november er spilledag – ingen ingame-tests.**

**P0 Fase 29 (færdiggjort delopgave):** Katalogkrydscheck via eksakt DB70450 recipe-ID → teaching-item-ID → `RecipeAccessSources` NPC-kilde, suppleret med eksakt recipe-name research fra `ProfessionSources` som tydeligt svagere advisories. En ny lille Wowhead Forever-itemkilde beskriver anskaffelsestyper for Elixir of Minor Agility (item 2553) uden at udpege en opdigtet NPC. En trainer kan kun få et aktivt waypoint ved unik identitetsmatch mod kanonisk `OwnerAuthorizedNavigation`, efterfulgt af `SourceResolver:VerifyNavigationWaypoint`. Intet vendor/drop-waypoint opfindes. Faction, build-neutral planlægning og native gates bevares.

**QA:** 51/51 Lua-regressionstests PASS og 362/362 TOC Lua-syntakskontroller PASS. 24/24 fulde skill 1–300 *scenarieprognoser* på 12 professioner med/uden simuleret AH PASS. Det er ikke bevist, at alle disse prognoser har komplet rutedækning. Faktisk normaliseret aktørresearch er 33/2664, 2631 uden actor i det undersøgte kildelag; ingen WoW Forever-klient er testet.

**Overdragelse:** `READ_ME_FIRST.md` i roden af det kompakte overdragelsesarkiv, fuld installativ addon, v0.34.189 rollback, API- og produktreferencer, kumulativ Word-rapport, QA/testkilder og præcis næste P0. Ingen historiske mega-ZIP-kæder.

---
# JuztLevel Professions — aktiv version 0.34.189-p0-recipe-source-currentstep-bridge

**Udviklingsbaseline:** v0.34.188. **Aktuel version:** v0.34.189. **Rollback:** v0.34.188. **Releaseklarhedsmål:** 3. november 2026. **Releasedag 4. november:** Ingen planlagte ingame-tests.

**QA:** Offline Lua-simulation. Ingen aktuelt tilgængelige spilservere. Alle 12 professioner skal færdiggøres med bedste mulige klientnære simulering inden release. Guide/Current Step må fungere uden AH-scanning og klient-evidence-logfiler.

**Overdragelse:** Læs `READ_ME_FIRST.md` i overdragelses-ZIP'ens rod eller `Docs/READ_ME_FIRST.md` inde i addonen. Hver aflevering skal indeholde en komplet overdragelsespakke med read-me, addon, rollback, rapporter, QA, datahuller og kildemanifest.

**Fase 27:** `CurrentStepCompletionChain.lua` er et nyt read-only end-to-end-oversigtsmodul (handling, lager, navigation, progresstjek). `CurrentStepTravelBridge.lua` beskriver gathering som Gathering Map-reference uden opfundet waypoint, og materialetrin kan bruge kvalificerede bank/AH-ownerpositioner. `ActionQueue.lua` bevarer konkrete gatheringhandlinger. Ingen native crafting-/recovery-kald ændret. Åbne 1–300-datahuller og faktisk klientevent-korrelation er ikke løst af denne fase.

---

# JuztLevel Professions — aktiv version 0.34.187-p1-skillup-currentstep-travel

Aktuel udviklingsversion: v0.34.187; rollback: v0.34.186. Dette er offline-godkendt advisory-planlægning, IKKE ingame-godkendt native crafting.
Den bindende fremtidige produktkontrakt står i `Docs/DEVELOPER_PRODUCT_CONTRACT_DA.md`.
Ny read-only planlægningskilde: `ProfessionPlanningFacts` (aktuel difficulty, learned-status, output min/max og kildeopslag), uden krav om historiske klient-evidence logs.
Yellow/Green klientpræcision er ukendt; brugerautoriserede scenarier 0.60/0.25 (Green justerbar 0.20–0.30) er antagelser og eksisterende RecipeTelemetry er valgfri.
Camp-workstation-forudsætninger er udelukket i den nye planlægningsvej. Native sikkerhedsgates er uændrede.
Den kumulative QA-leverance er fra denne version FLAD uden indlejrede gamle kumulative arkiver; historiske originaler bevares separat med referencer og SHA.

---

# Aktuel installationsvejledning – v0.34.185-p1-multi-step-route-economy-optimizer

**Gældende udviklingsversion:** `0.34.185-p1-multi-step-route-economy-optimizer`. Installer den selvstændige `JuztLevelProfessions_0.34.185-p1-multi-step-route-economy-optimizer.zip` i `D:\Battle.net - Games\World of Warcraft\_classic_beta_\Interface\AddOns\` med spillet lukket. Sikkerhedskopiér SavedVariables. **Rollback:** `0.34.184-p1-universal-current-step-catalogue`.

## P1 Fase 24 – Fremsynet 1–300-optimering

- `UniversalRouteOptimizer.lua`: rådgivende flere-skill-trin-plan, 20 fremtidige skillpoints for Current Step, eksplicit fuld 1–300-kildescenarie på anmodning (`Planner:GetProfessionRouteForecast`).
- Tre strategier og valgfri AH-priser; estimerede craftantal bygger på **ikke-verificerede** orange/gul/grøn-scenarieantagelser, ikke på garanterede skill-ups.
- Recipe-katalog og lærte recipe-ID'er prioriteres, read-only trainer/pattern-kildehenvisninger tilføjes; ulærte recipes giver aldrig native craftingret.
- `materialAcquisitionPlan`: flerstegsbeholdning, genbrug af output og opdeling af craft versus køb, kun for eksternt kildebelagte faste yields. Ukendt pris og beholdning markeret særskilt.
- Herbalism, Mining, Skinning og Fishing får fortsat gathering-/områdeplan frem for falske craftingruter.
- Datakataloget er **ikke** verificeret som en fuld eksekverbar 1–300-rute; utilstrækkelig recipe-adgang, trainer-/NPC-kvalificering, reelle skill-ups og ufuldstændige AH-priser er åbne. Ikke testet ingame.
- Ingen native dispatch-, policy-, transaction-ledger- eller historiske kildefiler er ophøjet til produktionsautoritet.

Tidligere installations-/releaseafsnit nedenfor er historiske og er IKKE gældende for v0.34.185.

---

# Aktuel installationsvejledning – v0.34.184-p1-universal-current-step-catalogue

**Denne er gældende version.** Installer `JuztLevelProfessions_0.34.184-p1-universal-current-step-catalogue.zip` i `D:\Battle.net - Games\World of Warcraft\_classic_beta_\Interface\AddOns\` med spillet lukket. Bevar dine SavedVariables og lav en backup inden opdatering. Rollback er v0.34.183-p1-tailoring-progression-evidence-integration.

**Guidefunktion:** Alle 12 professioner kan benytte den nye Current Step-rådgivning. Learned-status ved åbent professionspanel har forrang; uden panel bruges eventuelt eksisterende læringscache som uverificeret anbefaling. Manglende priser eller AH-scan blokerer ikke trin; alle viste priser er vejledende. Skill-up og maksimalt antal crafts er ikke garanteret. Native crafting kræver fortsat klientens egne beskyttede autorisations- og transaktionskontroller.

**Test:** Åbn Tailoring og en anden craftingprofession, prøv med og uden AH-scan, test både kendt og ukendt lager, Trainer ved skill cap og Gathering. Se `Docs/CurrentStep184/INGAME_ACCEPT_DA.md`. Ikke ingame-certificeret.

Historiske releaseafsnit nedenfor gælder tidligere versioner og må ikke bruges som installationsvejledning.

---

## Tailoring P1 Fase 22 – dokumenteret progression og skill-observationer

- `TailoringProgressionEvidence.lua` leverer read-only 1–300-dækning og en *eksplicit* live/skillhistorik-inspektion. Ingen automatisk craftbatch, antaget skillrate eller SavedVariables-opskrivning.
- De første tre opskrifter 1–75 er kvalificeret som historiske DB70450-referencer, men learned-status, faktisk traineradgang, output-yield og nødvendigt craftantal kan kun godkendes i klienten.
- De fire sene kildeintervaller 270–300 angiver mønstergodkendelse og kildekrav om Moonwell (883) henholdsvis Spinning Wheel (2250) konsistent. Krav er referencer, ikke aktuel stationadgang.
- Historiske skill-ups fra `CraftObservationJournal70450` vises kun som afgrænsede, read-only prøver, ikke som autoritet til at planlægge flere crafts.
- Rollback er v0.34.182. Alle 11 andre professioner og native dispatch-kontrakter forbliver uændrede. Faktisk WoW Forever-test udestår.

# JuztLevel Professions – Aktuel releasevejledning

**Aktuel udviklingsversion:** `0.34.183-p1-tailoring-progression-evidence-integration`  
**Udviklingsbaseline og rollback:** `0.34.181-p1-tailoring-1-300-live-guidance`  
**Status:** Kode- og offline-testet, **Tailoring 1–300 IKKE ingame-kvalificeret**.

## P1 Fase 21 – recipe- og progressionsevidens

- Nyt `TailoringRecipeQualification` auditmodul: alle 31 kildetrin fordelt på fem skillbands, med separate værdier for recipeidentitet, learned, difficulty, craftability, materialer, output og skill-up-beviser.
- Eksplicit `Planner:GetTailoringRecipeQualification(skill, true)` er en kortlivet READ-ONLY-klientinspektion; kaldet foretages ikke automatisk i hvert UI-frame. Ingen SavedVariables, native tilladelse eller build-allowlist.
- 13 trin med potentielt genanvendte historiske craftantal og 10 med modstridende eksterne yield-kilder markeres som QA-risici, ikke produktionsberegninger.
- Eksisterende `Data/Tailoring.lua` er uændret. Der er fortsat 0/299 fuldt ingame-kvalificerede skillovergange og ingen garanteret 1–300-rute.
- Kildedokumentation, 31-rækkers matrix og reel in-game-evidensopsamling findes i den kumulative QA-pakke.

## P1 – Tailoring 1–300: live-adgang og dækningsanalyse

- Det eksisterende 31-trins referencerutekatalog dækker 299/299 overgangspunkter (skill 1 til 300). **Det dokumenterer ikke** lærte opskrifter, faktiske skill-ups, tilgængelige trainers/patterns eller indkøbsbudgetter.
- Planner foretrækker en **aktuel, learned, ikke-grå og craftable** manuel ONE-instruktion frem for historisk antal crafts, også ved skill 1–136. Når den historiske opskrift ikke er brugbar, kontrolleres højst fem **tidligere registrerede** recipe-identiteter; live-klienten skal godkende dem individuelt.
- `TailoringLevelingCoverage` oplyser kildepositionsdækning og åbne evidensfelter; det giver hverken native permission, persistente kvitteringer eller reelle craftestimater. Guide markerer den observerede manuelle handling særskilt fra den historiske rute.
- Native Craft One/All, transaktionsledger, yield, bank/AH og progression kræver fortsat deres **egen** live-autorisation og ingame-test. Ingen gættede vendor-, trainer-, pattern-, cooldown- eller Moonwell-lokationer.

## Installation

1. Luk World of Warcraft: Forever og sikkerhedskopiér din AddOns-mappe og SavedVariables.
2. Historisk eksempel (IKKE GÆLDENDE): Udpak `JuztLevelProfessions_0.34.182-p1-tailoring-recipe-progression-qualification.zip` i `D:\Battle.net - Games\World of Warcraft\_classic_beta_\Interface\AddOns\`.
3. Kontrollér TOC og Bootstrap-versionen og at addonfolderen kun er ét niveau under AddOns.
4. Start spillet; vælg Tailoring, kontrollér guide ved skill 1, 31, 75, 137, 225, 270 og 299 efterhånden som din karakter opnår adgang, og gem `/jlpaudit release` med klientens faktiske build.
5. Udfør klientaccept i `TESTPLAN_DA.md`. Ved regression: gendan **v0.34.181** og den gemte SavedVariables-sikkerhedskopi.

## Historisk v0.34.180-releasebeskrivelse (ikke den aktuelle installation)

# JuztLevel Professions – Release- og installationsvejledning

**Aktuel version:** `0.34.180-p2-release-documentation-consistency`  
**Tidligere baseline / rollback:** `0.34.179-p1-toc-interface-compatibility`  
**Status:** Udviklingsbuild, offline-regressionstestet. **Ikke produktions-/ingame-godkendt.**

## Formål med denne revision (P2)

Vigtigste rettelse: tidligere aktive dokumenter pegede fejlagtigt på `0.34.156-rc1`. Den version er en **historisk releasekandidat**, ikke den aktuelle addon. Den oprindelige v0.34.179-releasebeskrivelse er bevaret ordret som `Docs/ReleaseHistory/README_RELEASE_DA_v0.34.179_snapshot.md`.

Denne udgave opdaterer versions- og QA-tekster samt TOC/Bootstrap-version. Der indgår **ingen ændringer i native crafting, recipe-autorisation, datakontrakter, UI eller SavedVariables-struktur**.

## Installation i WoW Forever

1. Luk WoW Forever helt. Sikkerhedskopiér den aktuelle `JuztLevelProfessions`-mappe og relevante SavedVariables.
2. Udpak **kun** `JuztLevelProfessions_0.34.180-p2-release-documentation-consistency.zip` til `D:\Battle.net - Games\World of Warcraft\_classic_beta_\Interface\AddOns\`.
3. Kontrollér, at `JuztLevelProfessions.toc` ligger direkte under `...\AddOns\JuztLevelProfessions\`, uden ekstra mappeniveau.
4. Kontrollér `## Version: 0.34.180-p2-release-documentation-consistency` i TOC, og at `Bootstrap.lua` angiver den samme version.
5. Start spillet; åbn professionerne, kontroller Lua-fejl og gem et `/jlpaudit release`-snapshot sammen med klientens faktiske build/interface.
6. Udfør den **aktuelle** `TESTPLAN_DA.md` før en eventuel ingame-godkendelse.

**Rollback:** Luk spillet, og gendan den uændrede v0.34.179-installationspakke og en eventuel sikkerhedskopi af SavedVariables, hvis der opstår regressionsfejl. Ingen automatiseret migration er udført i denne P2-udgave.

## Kompatibilitet og buildpolitik

- TOC deklarerer fortsat `## Interface: 16000, 16001` som kendte interface-ID'er. Ukendte fremtidige interfaceværdier kræver konkret observation og eventuel tilpasning af TOC før Lua indlæses (valgfrit værktøj: `Tools/Set-JuztLevelInterface.ps1`).
- Addonen må ikke generelt afvises alene på grund af forskel mellem et aktuelt klientbuild og et historisk kildebuild.
- Read-only observationer kan i relevante moduler virke uden komplet sessionsidentitet; de giver ikke automatisk native autorisation. Craft One, Craft All og Enchant kræver egne live-kontroller.

## Funktionalitet og åbne acceptkrav

Fase 3–18 har tilføjet/forbedret professions-workflows, forskningsrute-overførsel, katalog-/guideadgang, Planner, craftability-status, materialekvalitet, reagent-/recipeparitet, output-yield, eventrecovery, volatil observationsstøtte og loaderkompatibilitet. **Offline beståede målrettede tests er ikke ensbetydende med komplet 1–300 dækning eller ingame-godkendelse af alle 12 professioner.**

Det kræver stadig faktisk klienttest af native crafting/enchant-targets, Craft All og `/reload`, Bank/AH-observationer, Gathering Map/Fishing og JuztTom/JuztTravel/Current Step. Uverificerede opskrifter, skillintervaller, materialebeviser og transportforbindelser må ikke fremstilles som bekræftede.

## Diagnostik

```text
/jlpaudit start
/jlpaudit release
/jlpaudit capabilities
/jlpaudit mark before-test
/jlpaudit mark after-test
/jlpaudit status
/jlpaudit stop
```

Det er read-only auditkommandoer; `release`/`capabilities` er ikke produktionsautorisation. Den dokumenterede SavedVariables-log (`JuztLevelP0LiveAuditDB`) bør gemmes sammen med addonversion, klientbuild og testnoter.

## Dokumentstruktur

- `INTEGRATION_STATUS.md`: Aktuel samlet integrationsstatus efterfulgt af historisk kronologi.
- `TESTPLAN_DA.md`: Aktuel testplan for 0.34.180-p2-release-documentation-consistency.
- `CHANGELOG.md`: Versionsspecifikke ændringer inklusive denne P2-revision.
- `Docs/ReleaseHistory/`: Uændrede dokumentationssnapshots fra v0.34.179 med deres ældre versionshenvisninger.
- Kumulativ QA-leverance: historisk originalarkiv, rollback, kodediff, tests og Word-rapport.


## v0.34.187 – sandsynlighedsmodel, destinationsintegration og offline QA

- Udviklingsbaseline v0.34.186; ny version v0.34.187; rollback v0.34.186.
- Skill-up rådgivning: RecipeTelemetry når egnet; ellers brugergodkendt Orange 100 %, Yellow 60 %, Green 25 % (20–30 %), Gray 0 %. Grøn overgang i historiske data er modelleret, ikke verificeret.
- Current Step bærer JuztTravel/JuztTom-kildekvalificeret navigationsstatus; eksisterende fælles navigation respekteres. Guide bevarer reagentantal.
- Servernedlukning til 4. november 2026: udelukkende OFFLINE SIMULATION, ingen ingame-accept.
- Alle 12 professioners fulde 1–300-datadækning, trainers/vendors/drops og stationer er fortsat et åbent udviklingsmål. Camp-workstations ekskluderes.
