# v0.34.236 — P0-236 First Aid 1–300 kildekontinuitet og reel Owner/Travel/Tom QA

- Eksisterende `ForeverFirstAidArtisan232` understøtter nu `AtAnySkill(1..299)` og `PlanFullTo300(1..300)` med 11 sammenhængende rådgivende guideintervaller. De syv tidlige bandageopskrifter genvalideres mod DB70450 (spellID, kanonisk navn og præcis reagensmængde). De fire 225–300-intervaller bevarer den tidligere P0-232-sikkerhed.
- Førstehjælps læringsled: Expert book 16084, Heavy Silk manual 16112, Mageweave manual 16113, faction-dokumenteret vendor Balai Lok'Wein (13476)/Deneb Walker (2805); 225 Artisan Triage med de eksisterende quests og kirurger. Offentlige identiteter giver ALDRIG canonical Owner waypoint eller verificeret stock.
- `ProfessionSourceActionChain234` bruger samme kilde til konkrete 1–225 manuelle Current Step-opgaver, ikke en ny planner. `UniversalCurrentStep:PlanTo300` vedhæfter `sourceFirstAidFullContinuity236` uden at ændre optimizer- eller native-kald. 1–300 guidevinduer er IKKE 1–300 accepterede skill-ups.
- Betingede flertrinsmaterialebudgetter beregnes kun ved eksplicitte crafttal pr. guidevindue; output-kreditter, learned, inventory, skill-odds og faktisk vendoraccess er ikke opdigtet. Fix: `learned=false` beholdes (Lua and/or pitfall).
- Tre nye offline fixtures: 11 First Aid-vinduer/learning/inventory/source revocation; faktiske produktionmoduler IntegratedDestinationOwner + IntegratedTravelEngine med portable Travel Net/Planner/Journey + JuztTom UI-binding i MOCK-client; 96 12-profession skill-/ranggrænser. Server/frames/taint/real-world ETA/true skill gains er IKKE testet.
- `NativeDispatchService`, action security, transaction settlement, existing owner & rollback er uændrede. Udviklingsdeadline 03-11-2026; release/play 04-11-2026. Kildebeviser er offentlige referencefakta, ikke session receipts.

# Changes in 0.34.234 – P0-234 source-to-action continuity



- `Core/ProfessionSourceActionChain234.lua` er ét read-only, kildegenvaliderende REVIEW-lag. Det genbruger P0-233 Forever/DB70450, P0-232 First Aid, P0-228 kildekort, `RecipeSourcePlanningBridge` og eksisterende P0-230 flertrinsmaterialebudget. Ingen ny Planner, AH-motor, aktiv navigationsowner eller native dispatcher.
- `UniversalCurrentStep:Recommend` bevarer almindelige kvalificerede anbefalinger; der tilføjes `sourceActionEvidence234`. Ved manglende brugbare recipes vises read-only `VERIFY_SOURCE_GAP`, så brugeren kan identificere den konkrete uafklarede handling, men aldrig et opdigtet skill-up-trin. Kildekonflikter i eksisterende dataset fastholder den tidligere afvisning.
- `UniversalCurrentStep:PlanTo300` vedhæfter `sourceActionContinuity234` for både crafting og gathering/fishing. Den kan kategorisere dokumenterede felter og source gaps, men overtrumfer ikke optimizerens route eller sælger falsk fuld dækning.
- Secondary learning-source/reputation: eksisterende First Aid bog 16084 → Horde-vendor 13476 som read-only source-lead, Cooking Artisan 6610, Fishing Artisan 6607 og Alchemy Elixir of Greater Fortitude (1250784) med Friendly + 120 Merchant's Favor (Horde: Durotar Supply and Logistics; Alliance: Azeroth Commerce Authority). Ingen NPC-koordinater uden owner-verifikation; vendorstock/quest completion UNKNOWN.
- Ny kildekonflikt: Tailoring `2964 Bolt of Woolen Cloth`, offentlig Forever min 75 / difficulty 75–75–77–85, 3 Wool Cloth; DB70450 yellow 70, gray 85. Afvist som automatisk referencekandidat: `SOURCE_YELLOW_THRESHOLD_CONFLICT`. Kilde: https://www.wowhead.com/forever/spell=2964/bolt-of-woolen-cloth . Ingen opfundet skill 75–85-bro.
- Tre nye regressionsscripts: 84 punkter på 12 professioner, Current Step-/PlanTo300-paritet samt 180 stateful source/BOM/completion/travel/event-korrelationsovergange med reload og karakterskift. Alt er offline-simulation; ægte JuztTom UI/Travel graf og protected taint er ikke klienttestet.



# Aktuel release v0.34.205 – 0.34.205-p0-first-aid-source-route-correction

**Dato:** 24. oktober 2026. **Baseline/rollback:** v0.34.204. **Ingame-status:** IKKE TESTET. **Offline:** 81/81 regressioner, 373/373 Lua-syntakskontroller PASS.

P0-205: First Aid 1–225 bandageguide (7 kildeintervalrækker), ti nye eksakte, betingede First Aid output-/reagenskrydsninger (samlet 35), rådgivende læringsreferencer for 225–300. Materialemængder og crafttal bygger på guideestimat, IKKE live kvittering. NPC-/guidekoordinater giver ikke kanonisk JuztTravel/JuztTom navigation. Native sikkerhed uændret. Måldato 3. november; releasedag 4. november uden planlagt test.

## Ældre versionshistorik

# Senest: v0.34.196 (0.34.196-p0-source-coverage-material-continuity)

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

# Changes in 0.34.195 – Exact-source learning advice and live-action parity

- Admit exact sourced spell/profession minimum facts as **read-only** learn/verify candidates for not-yet-learned recipes; historical DB-only/MinRank still excluded.
- Stable live recipe learned=false now consistently drives UI, Current Step action, completion stage, and existing navigational source qualification.
- Resolve 192/193/194 minimum conflicts to the highest supported floor with correct winning source attribution.
- Feed strict resolved minimum to advisory odds rather than unqualified historical MinRank.
- 60/60 offline regression simulations and 368/368 TOC Lua syntax tests pass; 0 ingame tests, all 12 1–300 workflows still unverified.
- Native dispatcher, ledger, owner navigation and all client build admission policies unchanged.

# v0.34.194 – Seven-crafting selected source facts and simulator

# P0 Phase 33 / v0.34.194 – Seven-crafting recipe data and replan simulation

- This is a source-backed increment, NOT a claim of complete 1–300 guides or an ingame test.
- 14 selected precise minimumskill references from Forever spell/guide pages in six professions; Cooking Charred Wolf Meat is handled as a **starter/source/workstation hint**, NOT assigned a fabricated skill minimum. Cross-version corroborated min 1 facts for Enchanting 7421 and Blacksmithing 2660 are flagged in `referenceKind`.
- New public acquisition hints include Alchemy named drop mobs, generic First Aid trainer and Cooking Fire. None is an exact teaching-item-to-NPC join; no faction, coordinate or waypoint is synthesized.
- Recipe/SPELLID relation verified against existing DB70450 packed catalogue before adding facts.
- AH/no-AH and remembered/updated learned-state/inventory paths are advisory and must replan after material receipt or skill observation. Native execution gates, canonical JuztTravel/JuztTom and `/reload` persistence unchanged.
- Cooking Fire is a normal station; **Camp** workstations are excluded.
- Server offline: 0 WoW Forever ingame tests. Hard target 2026-11-03, 2026-11-04 is play/release day, no testing.

# v0.34.193 – selected recipe access and bounded public acquisition hints

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

## v0.34.191 – P0 præcise source-prerequisites og /reload-/zonetransition-simulation
- Udviklet fra v0.34.190; rollback v0.34.190; ingen native-dispatch eller build-lock ændringer.
- Quest 2858 / Pattern 8406 / Spell 10566: dokumenterede 2 x Nightscape Pants, 2 x Nightscape Boots, 2 x Wildvine; læsebaserede adgangskrav uden falske item-ID'er eller auto-navigation.
- Eksakte vendor skill/merchant favor kilder medføre Current Step-referencen når de findes.
- P0-191 simulations- og source-selection-matricer; 53/53 regressions, 363/363 syntax PASS; 0 ingame.
- Handoff og READ_ME_FIRST opdateret; 3/11 deadline, 4/11 releasedag uden tests.

## v0.34.190 – P0 source crosschecks, trainer-owner binding, 1–300 simulation
- Baseline 0.34.189; ny version 0.34.190, rollback 0.34.189.
- Read-only eksakt teaching-item join til `Data/RecipeAccessSources.lua` og præcis named-source research `Data/ProfessionSources.lua`.
- Wowhead Forever: Recipe: Elixir of Minor Agility (item 2553) har drop/fished/pickpocketed anskaffelsesformer, men præcis NPC/position er UNKNOWN.
- Unik, genverificeret kanonisk trainer-binding til JuztTravel kun når source actor, profession og zone matcher. Ingen inferred vendor-, drop- eller quest waypoint.
- Dækning: aktørreference 33/2664, 2001 præcise teaching item-relationer, resterende 2631 aktørhuller (dette lag). Ingen falske fuldacceptpåstande.
- 51/51 regressioner, 362/362 Lua-syntaks; 24 offline 1–300-scenarieprognoser med/uden AH; ikke ingame-verificeret.
- Fast kompakt fuld overdragelses-ZIP, READ_ME_FIRST, kilde- og QA-data, checksummer; deadline 3 nov 2026, 4 nov spilledag.

## v0.34.189 – P0 præcise recipe-kilder i Current Step
- Kildebro til DB70450 exact recipe→teaching item→vendor/trainer/drop/quest.
- Ingen hardcoded klient-build blokering: 70450 er KUN kildeproveniens.
- Factionfiltrering, deduplikering, konfliktstatus; manglende NPC-kilde er UNKNOWN.
- Current Step, Guide og ActionQueue viser kildehenvisninger for ulærte recipes uden at autorisere native handlinger eller navigation på research-koordinater.
- P0-datamangler vedvarer: DB angiver 2.664 poster, 2.001 teaching links men kun 15 recipes med kildehenvisninger; source relationer er ikke komplette.
- Klientnære offline tests; ingen ingame QA. Deadline 3. november 2026; 4. november er spilledag, ikke testdag.

## v0.34.188 – P0 fælles Current Step-kæde og fast samtaleoverdragelse

- Baseline v0.34.187; rollback v0.34.187. Ingen hardcoded build-allowlist eller native dispatch-ændring.
- Nyt `Core/CurrentStepCompletionChain.lua`: ensartet handling → materialestatus → ownernavigation → efterfølgende progressionscheck for alle 12, inklusive ukendt lager.
- Kvalificerede bank-/AH-kilder kan bruges til materialetrin; gathering viser ærligt eksisterende map-reference uden opfundne waypoints.
- ActionQueue viser konkrete gatheringanvisninger i stedet for anonym reference; Guide modtager kædestatus.
- Fast overdragelsesprocedure og deadline 3. november 2026. Ingen brugerkrav om ingame-testing på release 4. november.


## v0.34.187 – sandsynlighedsmodel, destinationsintegration og offline QA

- Udviklingsbaseline v0.34.186; ny version v0.34.187; rollback v0.34.186.
- Skill-up rådgivning: RecipeTelemetry når egnet; ellers brugergodkendt Orange 100 %, Yellow 60 %, Green 25 % (20–30 %), Gray 0 %. Grøn overgang i historiske data er modelleret, ikke verificeret.
- Current Step bærer JuztTravel/JuztTom-kildekvalificeret navigationsstatus; eksisterende fælles navigation respekteres. Guide bevarer reagentantal.
- Servernedlukning til 4. november 2026: udelukkende OFFLINE SIMULATION, ingen ingame-accept.
- Alle 12 professioners fulde 1–300-datadækning, trainers/vendors/drops og stationer er fortsat et åbent udviklingsmål. Camp-workstations ekskluderes.

# JuztLevel Professions — aktiv version 0.34.187-p1-skillup-currentstep-travel

Aktuel udviklingsversion: v0.34.187; rollback: v0.34.186. Dette er offline-godkendt advisory-planlægning, IKKE ingame-godkendt native crafting.
Den bindende fremtidige produktkontrakt står i `Docs/DEVELOPER_PRODUCT_CONTRACT_DA.md`.
Ny read-only planlægningskilde: `ProfessionPlanningFacts` (aktuel difficulty, learned-status, output min/max og kildeopslag), uden krav om historiske klient-evidence logs.
Yellow/Green klientpræcision er ukendt; brugerautoriserede scenarier 0.60/0.25 (Green justerbar 0.20–0.30) er antagelser og eksisterende RecipeTelemetry er valgfri.
Camp-workstation-forudsætninger er udelukket i den nye planlægningsvej. Native sikkerhedsgates er uændrede.
Den kumulative QA-leverance er fra denne version FLAD uden indlejrede gamle kumulative arkiver; historiske originaler bevares separat med referencer og SHA.

---

# 0.34.185-p1-multi-step-route-economy-optimizer · 23. oktober 2026 · P1 Fase 24

- Nyt `Core/UniversalRouteOptimizer.lua` med 20-skill-point lookahead og on-demand 1–300-kildeprognose.
- Valgfri AH-pris, read-only recipe-/trainerleads, rekursiv mellemproduktfremstilling, beholdningsafstemning og materialeforbrug mellem ruteled.
- Planner og UniversalCurrentStep integrerer forecast uden native dispatchautoritet.
- Skillchance-/antalantagelser vises som scenarier, aldrig som verificerede craftbudgetter; ukendte priser forbliver unknown.
- 37/37 målrettede og videreførte regressionstests; 356/356 Lua-moduler syntaksbestået; klienttest afventer.

---

# 0.34.184-p1-universal-current-step-catalogue · 23. oktober 2026 · P1 Fase 23

- Ny byggeuafhængig `Core/UniversalCurrentStep.lua`: samme anbefalingsarkitektur til 12 professioner, DB70450-recipe-/reagentkatalog og historiske ruter.
- Learned, inventory og AH-priser bruges som uafhængige input. AH-scan er valgfri; ukendte tal er aldrig 0.
- `Planner`, `GuideSteps`, `ActionQueue`: Current Step med valgte recipe og dokumenterede materialer, samt gathering- og trænertrin.
- Langsom fuld receptekatalog-scanning i UI undgås med single-profession-cache og højst 96 aktuelle recipe-opslag per evaluering.
- Native crafting autorisation, transaction ledger, historiske data og originalt referencemateriale bevaret.
- Offline regression: 36/36 testfiler PASS, Lua-syntaks 355/355 PASS, WoW Forever ingame IKKE TESTET.

---

## 0.34.183-p1-tailoring-progression-evidence-integration (2026-10-23)

- Ny read-only Tailoring skill 1–300 observabilitet, referencekrav og skillhistorikkorrelation; ingen autorisation til native crafting eller opskrivning af successrate.
- Kildekrav for Moonwell 883 harmoniseret på begge Mooncloth-steps; Spinning Wheel 2250 dokumenteret som kildekrav, ikke verificeret klientadgang.
- Skill cap håndteres som verificerings-/traineropgave. Planner og Guide kan eksplicit vise evidens pr. skillvindue.
- De 11 andre professioner uændrede; faktisk klienttest mangler.

## 0.34.182-p1-tailoring-recipe-progression-qualification (23-10-2026)

- Read-only Tailoring 1–300 recipe/progression audit pr. source-trin og fem skillbands; 31 rækker dokumenteret.
- Eksplicit volatil recipeinspektion med learned, difficulty, craftability og reagent-paritet; udfører ingen native handlinger, ingen SavedVariables-opdateringer, intet build-allowlisting.
- 13 splittede craft-estimat-risici og 10 reference-yield-konflikter markeret som advarsler, ikke faktiske klientfejl.
- Ingen ændringer i Tailoring-kildedata eller øvrige 11 professioner. Fuld Tailoring 1–300 INGAME ikke godkendt.

# Changes in 0.34.181 – P1 Tailoring 1–300 live guidance and source coverage

- Add read-only `TailoringLevelingCoverage` with exact 1–299 route-position accounting (source coverage vs actual qualified skill-ups, acquisitions, trainer gates).
- Prefer a safe, **manually performed ONE** action on a live learned, non-gray and craftable Tailoring recipe in all 1–300 bands, including below skill 137; retain up to five earlier deduplicated IDs as potential client-observed alternatives.
- Make Guide current-step distinguish live manual recipe from registered historical skill-band recipe. Historical craft counts, reagents and yields do not become native execution rights.
- Keep untouched native dispatch, ledger, recovery, SavedVariables schema, other eleven profession routes and TOC interface identifiers.
- Update release docs and add route coverage CSV, regression tests and Tailoring-specific ingame test plan. Offline QA cannot attest complete playable 1–300 or Craft All.

# Changes in 0.34.180 – P2 release-documentation consistency

Active version: `0.34.180-p2-release-documentation-consistency`

- Reconcile active development version across TOC/Bootstrap, integration status, Danish release notes, test plan and changelog.
- Move outdated 0.34.156-rc1 *current candidate* and installation instructions into clearly labeled historical snapshots rather than treating them as the active release.
- Preserve v0.34.179 documents verbatim under Docs/ReleaseHistory; preserve existing integration chronology and changelog entries.
- Explicitly distinguish offline QA, pending WoW Forever ingame acceptance, historical evidence and rollback baseline.
- No change to native crafting, RuntimeCompatibility logic, SavedVariables, clientbuild allowlists, TOC Interface values or Lua loading order.

# Changes in 0.34.179 – P1 TOC interface compatibility

- Declare verified public Forever interface variants 16000 and 16001 in a
  single Interface directive; retain all TOC Lua-file ordering.
- Add optional offline PowerShell update utility for an **observed** future
  interface value; never guess client versions or self-modify the TOC at runtime.
- Keep API capability checks, native dispatch authorization and evidence
  provenance unmodified; loader compatibility is not runtime certification.

# Changes in 0.34.156 rc1

Based on 0.34.155-p0-unified-consumer-callpaths. This is a release candidate; offline validation does not certify full in-client or twelve-profession 1–300 acceptance.

- Separate Tailoring recipe identity from route segment identity across staging, route evidence, requalification and endurance diagnostics.
- Require correlated confirmation evidence when reconciling pending crafts and enchants.
- Allocate shared physical stock once across direct inputs, recursive intermediates and tool preparation in the repaired planner/readiness/action/acquisition paths.
- Preserve and quote whole Auction House listings, purchase excess and optimization limits; retain older rounded-price snapshots as advisory.
- Account for owned intermediates, live feasibility and current affordability; retain explicit uncertainty for item-specific disenchant access.
- Preserve unknown/partial price state through acquisition session formatting.
- Use the common action queue head in the Current Step overlay and permit read-only action presentation without promoting profession execution rights.
- Recognize observed skill 300 independently of a crafting dataset.
- Share eligible personal gathering candidates between Smart and Custom, publish terminal generation results and retain material relevance in Balanced after skill progression is complete.
- Scope gathering state and observations by character GUID; archive unowned legacy state without false reassignment.
- Validate transport map identity independently of translated display names and fixed client build numbers.
- Preserve route and reason returns during manual destination revalidation.
- Reject malformed difficulty enum values; refresh affordability after money changes.
- Add bounded passive `/jlpaudit release` observations and an executable offline regression suite in the separate source/test deliverable.

Historical source builds remain provenance. Current API and observation contracts, character identity and protected-action constraints remain required. No data gap or untested profession has been silently promoted to production.
