# AKTUEL INTEGRATIONSSTATUS v0.34.236 — P0-236

Aktiv version: `0.34.236-p0-first-aid-continuity-owner-travel-tests`. First Aid har 11 sammenhængende guide-/DB70450-bånd fra 1–300; hver kilde kontrolleres igen og publiceres kun read-only. 3 nye OFFLINE tests inkluderer faktiske Owner/Travel/Tom-moduler; MOCK_CLIENT er ikke WoW Forever klientaccept. Samtlige 12 professioner er kontrolleret ved otte repræsentative skillpunkter, men 0/12 har bevist klientfullførelse 1–300. Tidligere P0-231–235 auditrettelser, native gates og rollback v0.34.225 er bevaret. Udviklingsdeadline 3. november; 4. november er spil/release uden test.

--- TIDLIGERE STATUS ---

# AKTUEL RELEASE v0.34.235 – P0-235

**Aktiv:** `0.34.235-p0-profession-exact-windows-route-integration`. Nye source-validated read-only alternative opskriftsvinduer for seks primære professioner (9 kvalificerede, 3 på HOLD), source-revocation, strategibaseret kilde-sammenligning og eksisterende Current Step/PlanTo300-integration. Den hidtidige Source/BOM/Owner/Travel/Tom/native dispatch og alle tidligere P0-231–234-fix er bevaret. **149/149 offline-regressioner og 398/398 TOC Lua5.4-syntaks**; Lua5.1 og reel WoW Forever-klient er ikke verificeret. **0/12** komplette klientgodkendte 1–300-ruter. Deadline 03-11-2026; 04-11 er releasedag, ikke testdag.

---


# AKTUEL INTEGRATIONSSTATUS v0.34.233 – P0-233

**Aktiv:** `0.34.233-p0-primary-six-forever-source-windows`. 15 curated Forever spellreferencer for Alchemy, Blacksmithing, Engineering, Leatherworking, Tailoring og Enchanting; 14 felter med reagens/navneparitet mod DB70450 (13 også med dokumenterede skillfarvegrænser). En Alchemy-kilde har ufuldstændig DB-record; UNKNOWN bevares. `UniversalCurrentStep` bevarer tidligere Planner-beslutninger og bruger kun det nye kildebevis som read-only supplement/fallback. Eksisterende Materialer, AH, Owner, JuztTravel/JuztTom og NativeDispatchService er bevaret. **143/143 offline-regressioner; 396/396 Lua5.4 syntaks**. Fuldt klientverificerede 1–300-ruter: **0/12**. Udviklingsmål 03-11-2026; 04-11 er spilledag, ikke testdag.

--- TIDLIGERE VERSIONER / HISTORISK STATUS ---

# AKTUEL STATUS v0.34.232 – P0-232

First Aid Artisan 225–300: 4 Forever recipe-/learning-/reagensreferencer; Current Step fallback og PlanTo300 source report. Output mismatch 10840/18629 giver ikke source credits. Ingen opfundne NPC-waypoints, ingen native tilladelse. 140/140 OFFLINE regressions, 395/395 Lua 5.4 syntax. 0/12 full client-verified; 3. november er deadline, 4. november ingen test.

--- HISTORISK v0.34.231 ---

# AKTUEL STATUS v0.34.231 – Uafhængig audit, F01–F07

Dels afhjulpet: F01 F02 F03 F04 F05 F06 F07 med selvstændige regressioner. F05 realistisk integration og F06 >384-opskrifter samt Lua 5.1-runtime er ikke fuldt afsluttet. Tidligere native/owner-kontroller består uændret.

---

## HISTORISK NOTAT v0.34.230

# AKTUELT INTEGRATIONSNOTAT – v0.34.230

Skinning skill→mob-level regel fra Wowhead Forever (opdateret 24.10.2026), Horde/Neutral name-only trainer source hints og områder til 225; ingen verificeret mob-spawn, loot, garanteret skillup eller waypoint. Fremtidig `PlanTo300` publicerer kildekontrolleret `sourceConditionalBudget230` ved siden af eksisterende økonomi. Mellemprodukter giver alene planlagt, betinget credit, ikke faktisk lager. Dynamisk kildetilbagekaldelse, UNKNOWN beholdning/pris, learner gate og event-/reload-isolation er testet offline. 135/135 offline PASS, 394/394 Lua syntaks PASS; 0/12 klientverificerede komplette 1–300-ruter.

---

# AKTUELT INTEGRATIONSNOTAT – v0.34.230

Skinning skill→mob-level regel fra Wowhead Forever (opdateret 24.10.2026), Horde/Neutral name-only trainer source hints og områder til 225; ingen verificeret mob-spawn, loot, garanteret skillup eller waypoint. Fremtidig `PlanTo300` publicerer kildekontrolleret `sourceConditionalBudget230` ved siden af eksisterende økonomi. Mellemprodukter giver alene planlagt, betinget credit, ikke faktisk lager. Dynamisk kildetilbagekaldelse, UNKNOWN beholdning/pris, learner gate og event-/reload-isolation er testet offline. 134/134 offline PASS, 394/394 Lua syntaks PASS; 0/12 klientverificerede komplette 1–300-ruter.

---

# AKTUELT INTEGRATIONSNOTAT – v0.34.229

`ProfessionFieldChain229` giver read-only kilde→learning→materiale→conditional BOM→manuel handling med kildekonflikter og UNKNOWN i stedet for opfundne værdier. `UniversalCurrentStep` blokerer manuelt craftforslag ved dokumenteret source-reagent mismatch; native service uændret. Fishing 225–300 officielt guideforslag (Tanaris) og Artisan-quests for Fishing/Cooking/First Aid adskiller quest og trainer. Ingen uverificerede koordinater går videre til JuztTravel/JuztTom; Existing canonical owner/stop/pause respekteres. 130/130 regressioner, 392/392 syntaks; ingen fuld klientaccept, 0/12 komplette 1–300. Deadline 3. november; 4. november er releasedag, ikke testdag. Tidligere status nedenfor er historik.

---

# AKTUELT INTEGRATIONSNOTAT – v0.34.228

P0-228 kildekvalificeringsmatrix for 12 professioner i eksplicit `PlanTo300`, ingen garanterede crafttal, ingen nye NPC-/waypoint-facts og ingen native autorisation. `CraftEventCorrelation` bruger vedvarende karakterlokalt stigende sessionsnummer for at afvise kolliderende tickets efter hurtig `/reload`. 124/124 offline regressioner + 391/391 Lua-syntaks PASS; 0/12 komplet ingame-accepterede 1–300-ruter. 3. november er kode-/QA-deadline; 4. november er releasedag, ikke en testdag. Ældre status nedenfor er historik.

---

# AKTUELT INTEGRATIONSNOTAT – v0.34.227

Ny read-only per-craft Current Step-kildereview for BS/LW forbinder source-paritet, aktuel learned-state, bagmaterialer og eksisterende kanoniske navigation-preview. Ingen ny native crafting, automatisk waypoint, verified 1–300-dækning eller faktisk klientaccept. 121/121 offline-regressioner og 390/390 TOC-Lua-syntakskontroller PASS. Alle ældre statuslinjer nedenfor er historik. Kode-/QA-mål 3. november; releasedag 4. november er ikke en testdag.

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

# Aktuel status v0.34.195 — P0 fase 34

Baseline v0.34.194 bevaret som rollback. Kildebaserede ulærte recipe-leads og live learned-state harmonisering er implementeret. Source-authority, native craft/ledger, ejerautoriseret navigation og byggeneutral runtime er uændret. QA 60/60; Lua 368/368; ingame 0/12 professioner fuldt accepteret. Alle 12 1–300-forløb er fortsat åbne; start næste P0 med selekterede recipe-/NPC-kildegap og event-for-event simulation.

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

# P1 Fase 24 – Fremsynet Current Step-planlægning

**Aktuel udviklingsversion:** `0.34.185-p1-multi-step-route-economy-optimizer`. **Rollback:** `0.34.184-p1-universal-current-step-catalogue`. **Status:** Offline QA bestået, **ikke** WoW Forever ingame-godkendt.

Multi-step forecast, source-difficulty bands og AH-/lagerbaseret dependency-BOM findes nu i `UniversalRouteOptimizer`. De 12 professioner har fortsat 8 crafting/smelting-/enchant-domæner og 4 gathering-domæner, som ikke må behandles som identiske. Public `Planner:GetProfessionRouteForecast` kan udarbejde et fuldt 1–300-referencescenarie med eksplicitte gaps; Current Step anvender 20 skillpoints lookahead. Ingen globale optimum- eller garanteret skillup-påstande; kilde-data og eksterne yields forbliver rådgivende. Ingen ny build-lock.

---

# P1 Fase 23 – Universal Current Step fra eksisterende professionskatalog

**Aktuel kode:** `0.34.184-p1-universal-current-step-catalogue`. **Rollback:** `0.34.183-p1-tailoring-progression-evidence-integration`. **Status:** Offline-tests bestået; **ingen samlet ingame 1–300-accept af 12 professioner**.

Den nye `UniversalCurrentStep` bruger lært/ikke-lært recipe-status når tilgængelig, eksisterende build70450-recipe- og reagentkatalog, aktuelle/taskekendte beholdningsdata og valgfrie AH-priser. For ukendte værdier angives `UNKNOWN`, ikke nul; en manglende AH-scanning stopper ikke Planner. Skillrelevante materialer vises pr. 1 craft, ikke som garanteret skill-up-budget. Gathering (Herbalism, Mining, Skinning og Fishing) får særskilte kildebaserede instruktioner. Ingen klientbuild eller live evidence-arkiv påkræves for *rådgivning*.

Alt er **read-only advisory**; `sourceBuild=70450` er proveniens, ikke klientlåse. Eksisterende native Craft One/All/Enchant, ledger, recovery og anti-replay er ikke ophævet. Manglende recipe-kilde/trainer, manglende fuld 1–300-skilldækning og ubekræftede yield/skill-ups er stadig åbne. QA og datadækning: `Docs/CurrentStep184/`.

---

## P1 Fase 22 – Tailoring 1–300: progressionsevidens (offline)

Aktiv kodeversion: `0.34.183-p1-tailoring-progression-evidence-integration` · rollback `0.34.182-p1-tailoring-recipe-progression-qualification`.
Ny datamatrix dækker 31 kildevinduer / 299 skillovergange; nul samlede live-kvalificerede skillovergange. Skillhistorik er højst 150 seneste resultatrækker for aktuel karakter og må ikke bruges som statistisk 1–300-beregning. Moonwell-/Spinning Wheel-krav er kildehenvisninger og kræver klientverifikation. Ingen automatisk native autorisation.

# JuztLevel Professions – Aktuel udviklingsstatus

**Aktuel kode:** `0.34.183-p1-tailoring-progression-evidence-integration`  
**Baseline/rollback:** `0.34.181-p1-tailoring-1-300-live-guidance`  
**Acceptstatus:** **Offline-testet; Tailoring 1–300 IKKE ingame-godkendt.**

P1 Fase 21: Feltvis audit af alle 31 Tailoring-steps. OBSERVED recipe/difficulty/craftability/reagents holdes adskilt fra kilde- og historikestimater; Guide og Planner kan vise aktuelle referencefejl. Ingen ændringer i 11 øvrige professioner, native dispatch eller kildebuildkontrakter. Fuld 1–300-klientaccept udestår.

P1 Tailoring 1–300: Dækningsaudit 299/299 historiske skillpositioner fordelt på 31 trin. Live-kvalificerede sammenhængende skillpositioner: **0/299 som dokumenteret i katalogets vedlagte routefelter** (dette tæller ikke senere, midlertidige ingame-observationer). Planner kan nu vise en aktuelt verificeret manuel craftingmulighed fra alle intervaller og en begrænset tidligere learned-opskrift som fallback; indkøbsmængder og Craft All kvalificeres ikke af dette. Andre 11 professioner er ikke ændret.

**Vigtige udeståender:** læring/adgang til opskrifter, faktisk skill-up og difficulty for 1–300, trainer-/pattern-kilder, 270–300 Mooncloth/robe og cooldown/station, native Craft All, materialeforbrug, reelle resultatkvitteringer, /reload og navigation.

## Historisk integrationsstatus for v0.34.180 (arkiveret, ikke aktiv)

# JuztLevel Professions – Aktuel integrations- og release-status

**Aktuel udviklingsversion:** `0.34.180-p2-release-documentation-consistency`  
**Udviklingsbaseline:** `0.34.179-p1-toc-interface-compatibility`  
**Rollback:** den komplette, uændrede v0.34.179-installationspakke.  
**Release-status:** UDVIKLINGSBUILD – OFFLINE-TESTET; **IKKE INGAME-ACCEPTERET**.  
**Historisk releasekandidat:** `0.34.156-rc1` (ikke den aktuelle version og ikke den gældende installationsvejledning).

## Kilde til gældende versions- og teststatus

- `JuztLevelProfessions.toc` (`## Version`) og `Bootstrap.lua` (`JLP.version`) skal være identiske med den aktuelle udviklingsversion ovenfor.
- `README_RELEASE_DA.md` indeholder den gældende installationsvejledning; `TESTPLAN_DA.md` indeholder aktuelle ingame-acceptkriterier.
- `CHANGELOG.md` registrerer udviklingsændringer kronologisk. Historiske versioner er historik, ikke en påstand om aktuelle testresultater.
- Fuld QA-historik og rapporter ligger i den kumulative leverance; tidligere formuleringer kan være begrænset til den pågældende gamle baseline.
- Ordrette snapshots af de tidligere dokumenter findes i `Docs/ReleaseHistory/` og er **kun historiske referencer**.

## Omfang og godkendelse

v0.34.180 retter **release- og testdokumentation**, ikke native Lua-logik, craftingautorisation, datakilder eller klient-/buildgates. v0.34.179's flerværdideklaration `## Interface: 16000, 16001` bevares. TOC-kompatibilitet er ikke garanti for funktionalitet på alle builds.

P0-/P1-implementeringer fra v0.34.164–v0.34.179 er overført uændret. Der er gennemført offline regression, men **ingen samlet WoW Forever-ingame-accept** af Craft One/Craft All/Enchant, progression 1–300 på alle 12 professioner, AH/Bank, gathering eller rejse-/navigationskæden. Der må ikke udledes sådan en godkendelse af en dokumentationsændring.

Kildebuilds som 70009/70245/70374/70450 er dataproveniens, ikke generelle klientbuild-allowlists. Aktuelle live-observationer, build-/sessionsfriskhed og native handlingsautorisation forbliver separate kontrakter.

## Historisk integrationslog – ikke aktuel releaseautoritet

Den følgende kronologi er bevaret fra de oprindelige udviklingsnoter og indeholder gamle kandidater, tests og datakontrakter. En historisk status gælder kun den version, den henviser til.

---

# JuztTravel / JuztTom integrated candidate 1

Baseline: 0.34.0-build70450-ah-incremental-price-guarded-r1 (uploaded 2026-10-18 08:38).
Sources: JuztTom standalone 0.1.0-alpha9-test1; existing JLP integrated JuztTravel backend.

- JuztTom's six-tab design UI, HUD, motion and visual assets have been embedded under the JLP namespace.
- Settings contains the dedicated `JuztTom Settings` button; opens the original UI on Behaviour.
- Per-character settings are stored in `JuztLevelProfessionsDB.account.juztTom.characters`.
- JLP keeps a single event owner and one renderer. Existing JLP travel network and live verification gates are preserved.
- `IntegratedNavigationHUD` remains solely for legacy world-space geometry/diagnostics; no legacy HUD frame is initialized.

**Status: development candidate, not in-game verified.** End-to-end JuztTravel standalone parity, dynamic routes/Fishing route integration, standalone-profile migration, client-only API behaviour and zone/reload resumption need targeted in-game QA before production release. Use a backup of the current addon and SavedVariables.


### Candidate5: JuztTom menu readability and route diagnostics (2026-10-18)
- Base: Candidate4 source; player map reported in-game as UIMapID 1454 (Orgrimmar). Previous Tirisfal-only assumption revoked.
- Raised JuztTom-owned small font templates (GameFontHighlightSmall/GameFontNormalSmall) to a minimum 14 pt in its six-tab UI, theme buttons, and legacy settings panel. No changes to global WoW font templates or the separate in-world arrow text-size setting.
- Advanced > Diagnostics now exposes the destination owner's travel route reason, player and destination map IDs, navigation and geometry states; reflowed the diagnostic field to stay above its action buttons.
- Current Step route from Orgrimmar 1454 to Undercity 1458 remains UNVERIFIED; this update does not authorize, synthesize, or auto-advance transport. Client test required.

### Candidate6: staged Orgrimmar–Undercity navigation (2026-10-18)
- Candidate5 in-game QA: font readability and layout passed; Current Step selected Doctor Herbert Halsey with player UIMapID 1454 and target 1458, but `NO_VERIFIED_ROUTE` persisted.
- Diagnosed missing city-to-exterior topology in integrated Planner. Canonical R002 does exist (Durotar 1411 -> Tirisfal Glades 1420), but full city-to-city traversal is not represented by qualified edges.
- Added strict staged/advisory guidance: on 1454 show manual gate-exit instructions (no invented city waypoint); on 1411 point toward canonical authorized R002 source platform; on 1420 reuse existing approximate Undercity ingress hint; on 1458 existing owner map-change logic may replan local guidance.
- `routeVerified=false`, `autoAdvance=false`, no taxi/zeppelin dispatch, no fabricated city map walk edge, no native journey advancement; final trainer destination remains canonical.
- Candidate6 is **not** a complete validated transport journey. Actual map changes, platform arrival, zeppelin progress and /reload continuity remain for in-game QA and follow-up implementation.
- Fixed an older integration metadata inconsistency: Bootstrap version previously still displayed Candidate1 while TOC reported Candidate5; both now report Candidate6.

### Candidate7: generisk map-topologi og sikker rejsevejledning (2026-10-18)
- **Eksakt baseline:** Candidate6 `0.34.0-build70450-city-transit-candidate6`. Alt andet addonindhold og den godkendte JuztTom-brugerflade er bevaret.
- Ny intern, klientuafhængig `Core/IntegratedTravel/MapTransitions.lua`. Den opbygger en map-level søgegraf fra godkendte transportedges og særskilt registrerede by/zone-par. Korte på samme kontinent eller fælles UiMap-forælder udløser aldrig implicitte forbindelser.
- De eksplicitte by/zone-par er Orgrimmar (1454) ↔ Durotar (1411) og Undercity (1458) ↔ Tirisfal Glades (1420). De er **vejledende relationer**, ikke præcise gennemgange eller bevis for gangbarhed. Tilføj først yderligere par efter konkret kvalifikation.
- Valg af transportedge bruger `Network:CanTraverse` samt native karakter-faction, klasse, level og dokumenterede taxi unlock-observationer. Ejermarkerede og bekræftede stationsknudepunkter er påkrævet; ikke-kvalificerede research-koblinger kan ikke give adgang.
- `IntegratedTravelEngine:GetStagedGuidance` anvender nu denne generelle model frem for en destinationshardcode til Undercity. Den returnerer næste map-stage ud fra klientens faktiske `Player Map` og markerer alt som `routeVerified=false`, `autoAdvance=false` og `nativeDispatchAllowed=false`.
- I en transitplatforms sikre native verdensradius skifter status til `WAIT_FOR_TRANSPORT`, uden at give transporttilladelse eller markere boarding/ankomst. Kun et faktisk, efterfølgende kortskift ændrer den vejledende næste etape.
- JuztToms binding viser ikke længere den endelige NPC-koordinat som en fiktiv pil ved en tekstbaseret byudgang. Stage-instruktionen vises i stedet, mens det kanoniske slutmål bevares.
- Bevarer stage-navnet `DUROTAR_ZEPPELIN_R002` og nuværende UI/typografi/indstillingspersistens. Versionsmetadata i TOC og Bootstrap rapporterer Candidate7.
- **Offline QA:** 341 Lua-filer har bestået Lua 5.4-syntaks; mock-kørsler bestod city-exit, R002, city-ingress, native platform-wait, forkert kort, Alliance-afvisning, klassebegrænsning, uoplåst/opnået Flight Path og spoof-afvisning. Det faktiske OwnerAuthorizedNavigation-katalog under mockede build-70450 UiMap-navne gav 47 stationsposter og 162 kvalificerede edges; Orgrimmar → Undercity-corridoren blev planlagt korrekt.
- **Begrænsninger:** Ingen live WoW Forever-test udført af Candidate7. Ukendte landbaserede nabozoner, præcise byporte, animationer og alle transportovergange er fortsat ikke fuldt verificerede. Fuld, automatisk genoptagelse efter `/reload` forbliver kilde-/karaktergated via eksisterende TravelContinuity og revalidering. Ingen opfundne map-koordinater eller transport-ETA.

### Candidate8: reversibel city/exterior-navigation uden stale-lock (2026-10-18)

- Baseline: præcis Candidate7. WoW Forever-spiltest: første Undercity-indtræden gav WORLD_VERIFIED / WALK_TO_WAYPOINT; tilbagevenden til Tirisfal udløste `UNEXPECTED_ZONE_REVALIDATION_REQUIRED`, som blokerede genindtræden.
- Kun native-bekræftet udgang fra en kvalificeret lokal bydestination til en eksplicit dokumenteret by-/zoneparring kan genoprette en vejledende etape. Den aktuelle transportgraf skal også levere `ENTER_DESTINATION_CITY` til det samme bykort.
- Ukendte kort, manglende position, ændret karakter, ikke-lokale ruter, stale plan, stop/pause og ikke-verificeret build forbliver blokeret. Ingen automatisk NPC-/craft-/transportankomst.
- Den originale destination forbliver i hukommelsen. Ved faktisk tilbagevenden til bykortet forsøger `AttemptLocalRouteAfterMapChange` igen en lokal rute.
- Kandidaten er **offline-testet**, men endnu ikke testet i WoW Forever efter fejlrettelsen. `/reload`-genoptagelse kræver fortsat den eksisterende kildevalidering og er ikke løst generelt af Candidate8.

### Candidate9: generel sikker tilbagevenden og Tirisfal reference (2026-10-18)
- Baseline: præcis Candidate8. Live WoW Forever: brugerens fire screenshots bekræfter, at Tirisfal 1420 kan genindtræde Undercity 1458 med NAVIGATING / AVAILABLE og WORLD_VERIFIED uden genvalg af destination.
- Generel `ArmNativeReturnRecovery` / `RecoverNativeReturn`: alle allerede kvalificerede lokale WALK-destinationer kan genskabe deres egen rute ved faktisk C_Map-verificeret tilbagekomst til præcis samme kort; ukendte mellemliggende kort forbliver STALE uden opfundne transportkanter. Bevarer karakter/build/source-kontekst og pausering. Andre rejsetyper må ikke auto-recoveres på denne måde.
- For eksplicit attesterede city/zone-overgange findes fortsat Candidate8s aktive staged guidance; nye forbindelser skal tilføjes som verificerede map-pairs. Ingen implicit kontinent-/parent-map linking.
- Tirisfal indgangsreference ændret fra 1420:61.8/74.5 til brugerangivet 1420:62.0/66.0 på både MapTransitions og Corridor (vejledende, ikke produktionsevidens for NPC eller transport).
- Selvstændig /reload- og login-persistens, ukendte transportkorridorer og alle verdenszoner er ikke dermed fuldt spilverificeret.

### Candidate10: Ruins of Lordaeron indgangsreference (2026-10-18)
- Eksakt baseline: Candidate9 `0.34.0-build70450-general-native-return-candidate9`. Candidate9 fortsat bruger-verificeret for Tirisfal 1420 → Undercity 1458 med automatisk aktiv trainer-navigation.
- Brugerangivet korrektion af omtrentlig Ruins of Lordaeron-indgangsreference: UIMapID 1420, X 61.90 %, Y 65.10 % (tidligere X 62.00 %, Y 66.00 %). Ændret konsekvent i `Core/IntegratedTravel/MapTransitions.lua` og `Core/IntegratedTravel/Corridor.lua`.
- **Kun markørdata, ikke landing-/entrance-attest eller native ankomstbevis.** Spilleren rapporterer Y-koordinaten under 0.1 %-point fra klientens zonegrænse, men dette er brugerobservation, ikke generel kort- eller walkability-evidens. Selve indtræden kræver observeret UIMapID 1458.
- Ingen ændringer i ruteautorisation, progression, Current Step-kilden, JuztTom UI, NPC-/stationkoordinater, datasæt eller persistens.
- Candidate10 er offline-regressionstestet men det nye præcise landmark kræver endnu spiltest. Generel native-return-regression er kun delvis spilverificeret fra Undercity-Tirisfal-eksemplet; andre kort skal testes.


### Candidate11: generel transporttilgængelighed og automatisk `/reload`-genoptagelse (2026-10-18)
- Eksakt baseline: Candidate10 `0.34.0-build70450-ruins-reference-candidate10`. Version: `0.34.0-build70450-reload-continuity-candidate11`.
- Brugerens nye datapolitik: **alle strukturelt registrerede kort-/transportforbindelser i grafen er med i vejledende ruteberegning uanset `verified`, `draft`, `confirmed`, `clientVerified` eller `ownerAuthorized`-markeringer**. Registreringskontrakten (valide punkter, kendte endepunkter, gyldig provenance og entydige ID'er) gælder stadig. Fraktion, klasse og level respekteres; bekræftet låste Flight Paths afvises. Manglende flyvepunktundersøgelse er UNKNOWN og skjuler ikke længere forbindelsen i en vejledende rute – aktuel flyveadgang og boarding sker manuelt i spillet.
- `Core/IntegratedTravel/Network.lua`, `Planner.lua`, `MapTransitions.lua` og `Core/IntegratedTravelEngine.lua`: fjernet evidens- og nodestatus-gates på registrerede kanter; bevaret regelmæssig gameplay-adgangskontrol. Kendte eksplicitte by-/zoneovergange er fortsat eneste automatisk tilladte *gangbare kortskift*; kort-/AreaTable-databaserne dokumenterer ID'er, ikke vejforbindelser. Ingen opdigtede terræn- eller transportkanter.
- `/reload`: `IntegratedDestinationOwner` gemmer en afgrænset kilde-identitet sammen med aktiv navigation og karakter-/kort-intention. `TravelContinuity70450` genindlæser den ubetroede kildeinformation, validerer den igen gennem `SourceResolver` (eller tidligere eksplicit valgt manual waypoint), kontrollerer karakter og position med native C_Map og beregner en NY rute. Første `PLAYER_ENTERING_WORLD` udløser genoptagelse; manglende positionsdata giver forsinkede kortkontroller. JuztTom opdateres efter vellykket genoptagelse.
- Ingen aktiv etape, waypoint-ankomst, transportboarding eller tidligere ruteleg genetableres uden ny observation. Brugerstop, invalidation eller pause genaktiveres ikke utilsigtet. SavedVariables er fortsat pr. karakter. Eksisterende Candidate10-checkpoints har ikke kildebevis: **vælg Navigate To én gang efter installation af Candidate11, og test derefter med `/reload` uden yderligere klik**.
- Offline: 341 Lua-filer syntaksbestået; simuleret kilderevalideret auto-resume, ny ruteberegning, manglende position, stop, source-tampering, gammel checkpoint, karakterisolation, uverificerede node-/kantstatusser samt fraktion/taxi-adgang bestået. **Live World of Warcraft Forever-test af Candidate11 afventer**.
- Godkendt JuztTom seksfanet UI, tekstskalering og Ruins of Lordaeron 1420 / 61.90 / 65.10 er uændret.


### Candidate16: Current Step/Gathering source separation and manual Routes isolation (2026-10-18)
- **Baseline:** exact Candidate15. Current Step remains an explicit selection of the ACTIVE learned profession, resolved through existing Planner/SourceResolver and canonical JuztTravel owner; JuztTom renders the current stage and HUD.
- **Gathering button:** now requests the current READY route from GatheringRouteService using map, generation, context token and overlay receipt; only an accepted route is handed to `IntegratedDestinationOwner:SelectGatheringStop`. Switching mode cannot silently keep showing the previous trainer destination. Generation and context mismatches are rejected without inventing waypoints.
- **Routes tab:** user-authored/manual waypoints only (plus an explicit demo when started by the user). Gathering Map generated waypoint collections remain owned by Gathering Map and never appear as a manual JuztTom route; the manual list is not overwritten. Route-switching control for generated routes is hidden.
- **Gathering progression:** eligible selected gathering stop is synchronized to the shared destination owner on advancement. Internal evidence and access checks remain unchanged; no automatic gathering, invented node claim or native movement.
- **In-game result:** pending. Lua 5.4 syntax and mocked mode-switch/owner tests passed. Same-map gathering arrows and non-local gathering map routing still require in-game verification.


## Candidate17 (2026-10-18)
- READY GatheringRouteService generation can be selected for navigation even if UI overlay paint acknowledgement is absent; overlay presentation state remains visible in owner diagnostics.
- Stale tokens, non-READY generation, invalid coordinates, and unknown gathering maps remain rejected.
- Deliberate switch to Herbalism without a qualified Current Step clears obsolete profession destination and saved auto-resume intent; manual destination is preserved.
- Candidate16 remains the source baseline; WoW Forever live verification is pending.


### Candidate22: One-click professionsnavigation fra Gathering (2026-10-18)
- Præcis baseline: Candidate21 `0.34.0-build70450-flight-destination-focus-candidate21`.
- Brugerens WoW Forever-test: Den aktive Herbalism Gathering-rute viser korrekt `Fly to The Crossroads`, `Flight Master: Doras`, men første tryk `Set active` på Alchemy ændrer kun fokus. Andet tryk fremkalder JuztTravel-stadiet `Leave Orgrimmar into Durotar`.
- Årsag: `StandaloneDisplay.lua` havde en udtrykkelig `self.mode=="GATHERING" and oldFocus~=s.key` focus-only-gren. Den sprang `ActivateCurrentStepTarget` over for første klik.
- Rettelse: `Set active` kalder nu én gang `ActivateCurrentStepTarget` uanset forrige navigationsmode. `IntegratedNavigationActions` kvalificerer kilden, den fælles `IntegratedDestinationOwner` overtager destinationen, og `IntegratedTravelEngine` leverer ruten. JuztTom skifter først visuel mode ved godkendt destinationsanmodning.
- Hvis den nye profession mangler Current Step, forbliver en igangværende Gathering-rute aktiv, og årsagen vises på Professions-siden. Ved eksplicit skift mellem to professionskilder ryddes en forældet kilde uden at påvirke brugerens manuelle ruter.
- Uændret: Gathering Map-ruten, alle transportdata og Flight Path-observationer, indstillinger, navigationens Pause/Resume/Stop og `/reload`-checkpoints.
- Offline QA: alle 341 Lua-filer består Lua 5.4 syntax-kontrol; isoleret UI callback-test, første klik under Gathering samt fallback med manglende Current Step består. Ikke live-verificeret i WoW Forever.
- Fortsat særskilt begrænsning: `DESTINATION_ONLY_NO_ROUTE` / `Leave the city` kan stadig være resultatet af en JuztTravel-etape uden verificeret lokalt byudgangs-waypoint. Candidate22 opfinder ikke et waypoint for at vise en pil.


## v0.34.187 – sandsynlighedsmodel, destinationsintegration og offline QA

- Udviklingsbaseline v0.34.186; ny version v0.34.187; rollback v0.34.186.
- Skill-up rådgivning: RecipeTelemetry når egnet; ellers brugergodkendt Orange 100 %, Yellow 60 %, Green 25 % (20–30 %), Gray 0 %. Grøn overgang i historiske data er modelleret, ikke verificeret.
- Current Step bærer JuztTravel/JuztTom-kildekvalificeret navigationsstatus; eksisterende fælles navigation respekteres. Guide bevarer reagentantal.
- Servernedlukning til 4. november 2026: udelukkende OFFLINE SIMULATION, ingen ingame-accept.
- Alle 12 professioners fulde 1–300-datadækning, trainers/vendors/drops og stationer er fortsat et åbent udviklingsmål. Camp-workstations ekskluderes.
