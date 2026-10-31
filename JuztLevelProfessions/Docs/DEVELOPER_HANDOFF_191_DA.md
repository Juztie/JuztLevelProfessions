# Udvikleroverdragelse v0.34.191 – Fase 30

**Aktuel kodebaseline:** 0.34.191-p0-selected-recipe-acquisition-continuity. **Rollback:** 0.34.190-p0-exact-acquisition-crosschecks.

Først: Læs `READ_ME_FIRST.md` i kompakt handoff ZIP. Udpak den vedhæftede install ZIP og fortsæt kun fra denne kilde. Se `Docs/DEVELOPER_PRODUCT_CONTRACT_DA.md` for projektmål og releasegrænse (3. november færdig, 4. november spiller bruger, ingen ingame-test).

## Implementeret i fase 30

- `Data/ForeverQuestAcquisition191.lua` tilføjer eksakt item+spell+quest+Horde-source med Wowhead Forever URL, navn/mængde på questmaterialer. Ingen påstået ItemSparse-ID eller klientobservation.
- `Core/RecipeSourcePlanningBridge.lua` kopierer public vendor skill/favor, sammenkobler en quest kun ved eksakt profession/SpellID/teaching-item/quest/faction og eksponerer krav i `Describe()`. Hvis konflikt, ingen source-promotion.
- 53/53 Lua-regressioner og 363/363 TOC syntax offline PASS. `QA/Regression_191_ReloadZoneContinuity.lua` tester SavedVariables checkpoint gennem simuleret reload, nyt map, ændret planrevision, anden karakter, tamper. 0 ingame.
- `QA/SELECTED_ROUTE_SOURCE_GAPS_191.csv` viser kildeforhold for opskrifter i 24 fulde 1-300 *scenarieprognoser*. 128 rutesegmenter, hvor 122 mangler en navngiven aktør i kildegrundlaget; sammenligninger bygger på syntetisk status: ALLE recipes lært og fiktiv pris 100. Må ikke kaldes praktisk skill 1-300-godkendelse.

## Kritisk fund: realismekløft i prognoser

Forecasterens rå `rawMinRank` kan være 1 på endgame-recipes som Mooncloth, og en syntetisk alle-recepies-lært tilstand kan placere Mooncloth ved skill 80. Det er ikke verificeret læringsminimum. Næste P0 skal koble den korrekte profession-required-skill/adgang fra data og live API, særskilt fra yellow/gray cutoffs. Forecasterens scenario-data-status alene er ikke en garanti for tilgængelighed.

## Næste implementering (konkret)

1. Prioritér de præcist valgte opskrifter i CSV. Opnå korrekte skillminima og kilde-/lærbarhedsrelationer fra addonens API-/DB-kilde og Wowhead Forever; rekonstruér IKKE ved at trække tilfældige point fra yellow/gray.
2. Verificér 1-300-ruter for de 12 med realistiske lærte/ulærte states, trainer caps, optional AH, intermediate-output og materialegenbrug. Fjern falske tidlige recipes. Registrér huller.
3. Slut hele Current Step → materials → navigation → handling → faktisk progression/replan. Udbyg `/reload`, zone/transport, pausede/stale sourcecases, fremtidig QA uden live klient. Bevar native gate.
4. Gem Word-rapport og gentag kompakt handoffprocedure.

Originale rå SavedVariables-originaler fra andre samtaler er ikke i denne pakke; angiv dette tydeligt, og behandl eksisterende in-game observationer i QA-historien som sekundær dokumentation, ikke som gættede råfiler.
