# Installerbar addon v0.34.231 – læs først

Denne ZIP installeres som `Interface/AddOns/JuztLevelProfessions/`. Seneste kodespor er baseret på v0.34.230 uden slettede filer.
Den komplette bindende udviklingskontrakt, uafhængige audit, regressioner og SHA-manifest findes i **separat overdragelses-/QA-ZIP** (`READ_ME_FIRST.md` i rod).
De verificerede kodefund er F01/F02/F04/F06/F07; F03 indeksforbedring og F05 modulbaseret testudvidelse er delvis, ikke fuld releaseaccept.
Der er stadig ingen klientcertificerede 1–300-professioner. 3. november deadline, 4. november launch uden planlagt test.

---

# AKTUEL INSTALLERBAR ADDON v0.34.230 – Skinning og kildekontrolleret flertrinsbudget

**Versionsidentitet:** `0.34.230-p0-skinning-eligibility-source-budget-replay`. Bindende udviklerkontrakt og ny aktiv baseline står i `READ_ME_FIRST.md` i roden af separat QA-/overdragelses-ZIP. Skinning har dokumenteret mob-level eligibility; 225–300-områder er UNKNOWN. `sourceConditionalBudget230` er eksplicit scenario, aldrig virkelig beholdning eller native autorisation. 135/135 offline-tests og 394/394 Lua-syntakskontroller PASS. Ingen profession fuldt klientverificeret 1–300. Deadline 3. november; releasedag 4. november er ikke testdag.

---

# AKTUEL INSTALLERBAR ADDON v0.34.230 – Skinning og kildekontrolleret flertrinsbudget

**Versionsidentitet:** `0.34.230-p0-skinning-eligibility-source-budget-replay`. Bindende udviklerkontrakt og ny aktiv baseline står i `READ_ME_FIRST.md` i roden af separat QA-/overdragelses-ZIP. Skinning har dokumenteret mob-level eligibility; 225–300-områder er UNKNOWN. `sourceConditionalBudget230` er eksplicit scenario, aldrig virkelig beholdning eller native autorisation. 134/134 offline-tests og 394/394 Lua-syntakskontroller PASS. Ingen profession fuldt klientverificeret 1–300. Deadline 3. november; releasedag 4. november er ikke testdag.

---

# AKTUEL INSTALLERBAR ADDON v0.34.229 – P0 feltkvalificering og quest-gates

**Versionsidentitet:** `0.34.229-p0-exact-minimum-learning-bom-currentchain`. Start en ny udviklingssamtale med **`READ_ME_FIRST.md` i roden af den separate overdragelses-/QA-ZIP**, ikke denne addoninterne historik. Source-minimummer og Fishing 225–300 er read-only; questadgang, NPC-stock og canonical waypoints ikke live-attesterede. 130/130 offline regressioner og 392/392 TOC-syntaks PASS. 0/12 professioner fuldt klientverificeret 1–300; rollback v0.34.225 kun i handoff. 3. november kode-/QA-deadline; 4. november releasedag uden planlagt QA.

---

# AKTUEL INSTALLERBAR ADDON v0.34.228 – P0 source/receipt coverage

**Aktiv kode:** `0.34.228-p0-twelve-source-coverage-stateful-chain`. Ved ny ChatGPT-samtale: læs `READ_ME_FIRST.md` i **rod af den kompakte overdragelses-/QA-ZIP**. Ny per-skill source matrix i fremtidig PlanTo300, mere robust `/reload`-sessiondiagnostik og 124/124 OFFLINE / 391/391 TOC-Lua kontroller. 0/12 fuld liveaccepterede ruter. Rollback v0.34.225 findes kun i overdragelsesarkivet. 3. november er kode-/QA-deadline; 4. november er releasedag og ikke testdag. Tidligere revisionsinformation er historik.

---

# AKTUEL INSTALLERBAR ADDON v0.34.227 – P0 Current Step research-review

**Aktiv kode:** `0.34.227-p0-stitched-current-step-material-nav-review`. **Separat overdragelse:** læs `READ_ME_FIRST.md` i **roden af den kompakte overdragelses-/QA-ZIP**. Herunder følger tidligere README-revisioner som historik, ikke som aktive releasekrav. 121/121 offline-regressioner PASS; 390/390 Lua-syntaks PASS; 0/12 fuldt klientverificerede 1–300. Rollback 0.34.225 er kun i overdragelsesarkivet. 3. november er kode-/QA-deadline; 4. november er releasedag, ikke testdag.

---

# AKTUEL ADDON v0.34.200 — overdragelsesrod: READ_ME_FIRST.md

Denne installerbare addon er del af den separate v200-overdragelsespakke, som har den bindende rod-README. Aktuel status: 68/68 offline regressioner, 373/373 syntaks; 0 faktisk ingame-accept. Read-only CrossProfessionDependencyPlanner viser betingede materialekæder; native sikkerhed og destinationsejer uændret. 3. november kode-/QA-deadline; 4. november er releasedag uden planlagt test.

---

## Historisk inkluderet dokumentation

# SENESTE v0.34.196 – læs overdragelsespakkens READ_ME_FIRST.md i roden først

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

## Historisk bevaret intern README fra v192

# Seneste: JuztLevel v0.34.192 – læs dette først

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

# READ ME FIRST — JuztLevel Professions v0.34.190

Dette er addonens kopi. **I den separate overdragelses-ZIP ligger den fulde `READ_ME_FIRST.md` i roden.** Start dér ved ny ChatGPT-samtale. Indlæs ikke en ældre version frem for seneste baseline.

Baseline v0.34.189, aktuel version v0.34.190, rollback v0.34.189. Releaseklarhedsmål 3. november 2026; 4. november er spilledag uden ingame-test. Læs `Docs/DEVELOPER_PRODUCT_CONTRACT_DA.md`, `Docs/DEVELOPER_HANDOFF_190_DA.md` og rapport/QA fra den selvstændige overdragelsespakke. Alle 12 professioner 1–300, AH valgfri, skill odds, materials, JuztTom/JuztTravel, native gates. Kode QA 51/51, Lua syntaks 362/362, 24 offline simuleringer.

---

## Historisk tidligere overdragelse (v0.34.189 – kun reference)

# READ_ME_FIRST – JuztLevel Professions, komplet udvikleroverdragelse

**LÆS DENNE FIL FØRST.** Denne fil gør det muligt for en ny ChatGPT-samtale at fortsætte JuztLevel-udviklingen uden adgang til den gamle samtale. Dette arkiv er **selvbærende** og er den primære overdragelsesfil.

## 1. Første handlinger for den overtagende udvikler

1. Læs hele denne fil. Læs derefter `DOCS/DEVELOPER_PRODUCT_CONTRACT_DA.md`, `DOCS/DEVELOPER_HANDOFF_188_DA.md`, `QA/STATUS_188.md` og `QA/OPEN_GAPS_188.csv`.
2. Åbn **`ADDON/INSTALL_v0.34.188.zip`**. Denne ZIP er den komplette, installerbare JuztLevelProfessions-source tree (inkl. TOC og alle datakilder). Den er den **eneste gældende kodebaseline**.
3. Verificér `JuztLevelProfessions.toc` og `Bootstrap.lua`: begge skal angive `0.34.188-p0-currentstep-chain-handoff`. Gå ikke tilbage til ældre versioner ved en fejl.
4. `ROLLBACK/INSTALL_v0.34.187.zip` er den fulde sidste fungerende kodebaseline til rollback, ikke starten på næste fase.
5. Kør `QA/RegressionTests/` samt de nye `QA/Regression_188_*.lua` ved hjælp af Lua 5.4 eller den medfølgende Python/Lua-ctypes-runner. Hold originale ældre testfixtures intakte; se `QA/STATUS_188.md` for en forventningsændring.
6. Fortsæt derefter **uden at bede brugeren gentage requirements** med åbne P0-datamangler og fuld Current Step → materialer → navigation → handling → progression-integration. Forsøg at løse reelle kodefejl og dokumentér ærligt utilstrækkelig kilde.
7. Aflevér igen *én selvstændig installations-ZIP plus én kompakt selvbærende overdragelses-/QA-ZIP med READ_ME_FIRST i roden*.

## 2. Ufravigelige datoer, mål og systemgrænser

- **3. november 2026 er udviklings- og afleveringsdeadline.** Brugerens mål er at have alle 12 professioner 1–300 integrerede og funktionelle, klar til releasedagen.
- **4. november 2026 er spillets release og brugerens spilledag. Der må IKKE planlægges ingame-tests til den dag.** Spilserverne er utilgængelige før release.
- Brug eksisterende API-definitioner, tidligere SavedVariables/observerede ingame-data, 70450-kataloget, JuztTravel/JuztTom, kildebeviser og meget realistiske offline klient-simulationer. Ikke-gennemførte ingame-tests må ikke opdigtet godkendes.
- Alle 12 guides 1–300 skal vælge bedste dynamiske Current Step fra profession, skill, lært/ulært recipe, inventory, mellemprodukter og valgfrie AH-data. **Intet AH-scan og ingen historisk klient-evidence er en forudsætning** for at planlægge. Historisk build bruges kun som dataproveniens, ikke en hardcoded klientlås.
- Bedste skill-up-chance via eksisterende RecipeTelemetry, ellers Orange 100 %, Yellow 60 %, Green 25 % (tilladt 20–30 %), Gray 0 %. Scenarieprocenter er ikke garanterede klienttal.
- Output-yields: API `GetRecipeSchematic` når tilgængelig, ellers dokumenteret datakilde med klar usikkerhed. Hold craftantal og output-items adskilt.
- Alle handlinger (trainer, NPC, vendor, bank, AH, gathering) skal tilknyttes den fælles JuztTravel/JuztTom destinationsarkitektur med eksisterende kanoniske koordinater. **Opfind aldrig map-ID, coords eller NPC-relationer.** Beskyt manuelt waypoint og Stop.
- **Camp-workstations skal udelukkes.** Almindelige faktisk nødvendige Forge, Anvil, Fireplace, Moonwell mv. kan indgå, når dokumenterede.
- Native Craft One/Craft All/Enchant kræver fortsat separat klient-/policy-/ledgerautorisation; et read-only planforslag er IKKE native tilladelse.

## 3. Nøjagtig versionsstatus

| Felt | Værdi |
|---|---|
| Baseline før ændringer | `0.34.187-p1-skillup-currentstep-travel` |
| Aktuel kode og næste baseline | `0.34.188-p0-currentstep-chain-handoff` |
| Rollback | `0.34.187-p1-skillup-currentstep-travel` |
| Ændringer | `Core/CurrentStepCompletionChain.lua` NY; `CurrentStepTravelBridge.lua`, `UniversalCurrentStep.lua` afhængighed, `Planner.lua`, `ActionQueue.lua`, `GuideSteps.lua`, `Bootstrap.lua`, `.toc`, docs |
| Klientaccept | IKKE udført i denne fase; offline simulation er eneste ny QA |
| Historie | Tidligere store QA-arkiver indlejres IKKE. Se indeks og tidligere referencer. |

## 4. Aktuel udviklingsfase og konkret næste arbejde

**Fase 27:** fælles Current Step fuld kædestatus og samtaleoverdragelse. Kædekontrakt er advisory/read-only. Navigation til gathering er map-reference, ikke garanteret vejpunkt.

**Næste P0-opgave:** luk source-præcise trainer/vendor/drop/recipe-anskaffelsesrelationer fra addonens DB først, suppler fra wowhead.com/forever når feltet mangler. Derefter udvid E2E-simulation til alle skillintervaller 1–299 for alle 12 professioner; sørg for Current Step repræsenterer learned- og unlearned-branches, trainer-rang, reagentbehov, bank/AH med/uden skanning, dokumenteret JuztTravel-destination og efterfølgende progression. Prioriter faktiske code/data fixes, ikke ekstra rent diagnostiske lag. ``QA/OPEN_GAPS_188.csv`` er startpunkt.

**E2E-kæde:** Character + Profession Skill → Recipe Access → Expected Skill-Up + Output → BOM/Inventory → Acquisition (vendor/gather/AH) → Canonical JuztTravel/JuztTom → Manual/Native-approved Action → New Skill + Recipe/Inventory Observation → Replan. Afgør aldrig native success alene ud fra forecast.

## 5. Pakkens indhold

- `ADDON/INSTALL_v0.34.188.zip`: fuld installerbar source/version.
- `ROLLBACK/INSTALL_v0.34.187.zip`: komplet rollback-source.
- `DOCS/`: bindende kontrakt, teknisk handoff, tidligere kumulativ Word-hovedaudit og ny fase-rapport, kilde-/historieindeks.
- `DATA/`: detaljeret tidligere recipe-feltmatrix og datamangelsoversigt; originale store referencepakker findes kun hvis tilgængelige. De tre originale referencefiler `WowApiExport(6).lua`, `WoW_Forever_API_Opslagsvaerk_Dansk(3).docx` og `JuztLevel - Fuld Produktbeskrivelse v1.0(3).docx` er medtaget uændret fra Fase 2-kildearkivet. Rå SavedVariables-filer er ikke identificeret i den seneste kompakte leverance; tidligere kvalificeret observation er bevaret i kildekoden og rapporterne, men manglende rå kilder er ikke fabrikeret.
- `QA/`: testkilder, testresultater, skill-matrix, integritetsmanifest, kildekode-diff og åbne fund.

## 6. Hvad er bekræftet, og hvad er IKKE bekræftet?

- Kildearkivet indeholder en komplet 12-professionsregistrering, recipe-referencer og JuztTravel ownerdata; det betyder ikke fuldt kvalificeret 1–300-produktion.
- Nye kodeændringer er syntakstestet i Lua 5.4; denne verificering er ikke det samme som faktisk WoW Forever-klienteksekvering.
- Tidligere 70450 data er kildedata. De er ikke en sikker indikator på aktuell learned-status, resultatkvitteringer eller tilgængelige trainer-/vendor-/dropsteder.
- Kildespecifikke huller, usikre skillprobabiliteter, output-yields og eventuelle manglende navpositioner må ikke skjules eller udfyldes med gæt.

## 7. Kompakt pakning og fremtidig procedure

Der skal **altid** laves denne READ_ME_FIRST i rod, med opdateret baseline, resultater og næste arbejde. Én komplett installations-ZIP + én kompakt handoff-ZIP, ingen kæder af tidligere kumulative ZIP-filer, tidligere rapporter bevares eller henvises via historisk checksumindeks. Liste eventuelle fraværende originaler eksplicit.

**Særligt til nye udviklere:** Begynd med kode og data i denne pakke. Anmod ikke om den gamle samtale, før de vedlagte filer er læst. Undgå at hævde at alle professioner er færdige alene fordi alle 12 er registreret.

## 0.34.198-p0-qualified-intermediate-credit-and-replan
Advisory-only material rollup now withholds unlearned/unknown or conflicting-item intermediate credits; no native authority. See QA handoff README.
