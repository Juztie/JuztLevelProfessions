# v0.34.195 – P0 Fase 34: Præcist adgangsbevis og konsistent Current Step

Baseline: `0.34.194-p0-seven-crafting-skill-access-and-replanning` (SHA-256: `52669990287b11c50e695a1a330bd991f23550e88546fca2cfd058302b9a1d82`). Ny kode: `0.34.195-p0-exact-access-advisory-and-live-parity`. Dato: 24.10.2026. Status: **OFFLINE SIMULATION**, 0 verificerede WoW Forever-klienttests.

## Konkrete implementeringer

1. `Core/UniversalCurrentStep.lua`: En DB70450-recipe uden registreret rute må nu give *læsebaseret lærings-/verificeringsvejledning*, selv når learned=false/UNKNOWN, **kun** hvis `ProfessionRecipeMinimumGate` allerede har et eksakt kildebevis (`FOREVER_SELECTED_RECIPE_MINIMUM_193`, `_194` eller `FOREVER_EXACT_SPELL_OR_ITEM`). Hverken generisk `rawMinRank`, gule/grå cutoffs eller navnelighed får denne adgang. Prioritet for aktuelt lærte opskrifter og read-only policy bevares. Ukendt recipe-acquisition/teaching-item/NPC må ikke antages kendt.
2. `Core/UniversalCurrentStep.lua`: Stable live-panel `GetRecipeInfo.learned` vinder over cached/override for handlingsbesked, CompletionChain og destination. En faktisk ulært recipe vises ikke længere med `Craft ONE`-tekst. Skillup-scenarie får det strengt kvalificerede minimum fra `ProfessionRecipeMinimumGate`, ikke det almindeligvis ukvalificerede `rawMinRank=1`.
3. `Core/CurrentStepCompletionChain.lua`: Observationen learned=false giver `LEARN_RECIPE`, mens live GRAY/canSkillUp=false giver `VERIFY_RECIPE`. Handling og kædestatus peger dermed mod samme næste opgave. Kæden er stadig read-only.
4. `Core/ProfessionRecipeMinimumGate.lua`: Uenighed mellem **alle tre** referencelag (192, 193, 194) markeres. Den strengeste grænse får kildeetiketten og URL til det faktiske vindende lag. En strengere ældre værdi må ikke fejlagtigt præsenteres som v194-autoritet.
5. Versionsidentiteten er identisk i `.toc` og `Bootstrap.lua`; alle 550 addonfiler videreført, heraf 5 kilde-/manifestfiler ændret før opdatering af release-dokumenter.

## QA og sikkerhed

- **60/60** Lua-simulerede regressioner bestået, heraf 1 ny P0-195 test; **368/368** TOC-indlæste Lua-filer syntaktisk bestået.
- Ny test: 6 udvalgte professioner × learned=false/UNKNOWN × med/uden AH = **24** Current Step-leads; eksakt minimum, ulærte opskrifter, ingen uautoriseret navigation/native dispatch, DB-only negativ kontrol, kilde-konflikt, stabil klient-learned=false, live-grå sikkerhedsstop.
- Alle historiske regressionscripts i den selvstændige QA-pakke er genkørt mod den nye installations-ZIP. Simulator-LEDGER/event/reload/travel-resultater er **ikke** ingame-accept.
- Ingen ændringer i `NativeDispatchService.lua`, `Crafting.lua`, `TransactionLedger`/receipt-/eventautorisation, `IntegratedDestinationOwner`, `IntegratedTravelEngine` eller `IntegratedJuztTom`. Intet build allowlist, ingen syntetisk NPC, ikke nogen Camp-workstation.

## Åbne P0-krav, prioriteret

1. Fulde 1–300-ruteforløb for alle 12 professioner er fortsat **IKKE VERIFICERET**. Udvid eksakte source-backed recipe minimums og kvalificér de faktisk valgte recipes frem for at betragte DB-catalogue som autoritet. Tidligere 72 realistisk begrænsede modeller havde **855 ikke-dækkede skillovergange** – historisk QA-mål, ikke genmålt produktdækning i P0-195.
2. Verificér SpellID→teaching ItemID→faction→NPC/quest/vendor/drop og koordinater i eksisterende owner-data. Intet navngivet guide-hint uden ownerbevis må blive waypoint. Forbedr Cooking/First Aid og gathering-specifikke 1–300-workflows.
3. Etabler en fuld, sammenhængende simuleret eventsekvens på tværs af faktisk skill, learned-state, reagenter, bank/AH snapshots, Current Step, JuztTravel/JuztTom, brugerhandling, event-/ledger-kvittering og genberegning efter `/reload` og zoneskift, uden at ophøje read-only data.
4. Verificér prioriteret klientkompatibilitet offline mod tilgængelige API-dumps og eksisterende ingame-observationer. 3. november 2026 er færdiggørelsesmål; 4. november er releasedag/spilledag, ikke testdag. Ingen live-accept kan hævdes.

**Rollback:** Installér uændret `ROLLBACK/INSTALL_v0.34.194.zip` fra handoff-arkivet ved regression. Tag altid kopi af SavedVariables før udskiftning af addonfiler. Versions- og SHA-256-kontrakt fremgår af `QA/QA_MANIFEST_195.json` og `SHA256_FILES.txt`.
