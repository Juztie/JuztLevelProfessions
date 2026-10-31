# Teknisk udvikleroverdragelse – v0.34.189

Gældende baseline `0.34.189-p0-recipe-source-currentstep-bridge`. Forrige kode `0.34.188-p0-currentstep-chain-handoff`. **3. november er afleveringsdeadline. 4. november er spil/release, IKKE klienttest.**

## Denne fases implementering

- Ny `CurrentStepCompletionChain.lua`: stable read-only handlingskategorier `LEARN_PROFESSION`, `TRAIN`, `LEARN_RECIPE`, `VERIFY_RECIPE`, `VERIFY_MATERIALS`, `VERIFY_INVENTORY`, `ACQUIRE_MATERIALS`, `MANUAL_CRAFT_ONE`, `GATHER`, `COMPLETE`.
- `CurrentStepTravelBridge`: skelner mellem kanoniske train/bank/AH-destinationer, workspace-action og gathering-map-reference; ingen opdigtede koordinater eller automatisk navigation.
- `Planner`: efter normal beregning vedhæftes `currentStepCompletionChain`; det ændrer ikke native sikkerhed.
- `ActionQueue`: konkrete gatheringanvisninger og transport af allerede kvalificeret navigation til materielle anskaffelsestrin.
- `GuideSteps`: eksponerer kæden på konkret Current Step-række.

## Næste udviklingsmål

1. Kildepræcis recipe→trainer/vendor/drop på tværs af alle 12, ved at krydsreferere eksisterende DB70450 og `SourceResolver`, `ProfessionsDataCatalogue`, `OwnerAuthorizedNavigation` og Wowhead Forever. Begræns aldrig dataadgang alene pga. build.
2. Nedbryd skill 1–300 i praktiske, komplette trin for hvert profession; lærte/ulærte recipes, trainer/adgang og nødvendigt forventet materialeforbrug med / uden AH.
3. Verificér Current Step destination for trainer, vendor/NPC, bank, AH og gathering; kun canonic owner-admitted pins. JuztTom-pil og zoneskift skal fortsat simuleres så virkelighedsnært som muligt.
4. Gennemfør komplet E2E nær-klient-simulation af de 12 professioner og Craft One/All/Enchant-sikkerhed med transaktionsledger, resultater, fejlhændelser og reload.
5. Lever ny installation + komplet self-contained handoff ZIP med en opdateret `READ_ME_FIRST.md`.

## Åbne begrænsninger

E2E advisory-kæden er ikke en køreplan med alle source-relations kvalificeret. Kæden er read-only, og native dispatch er bevidst uændret. Gathering Map-reference giver ikke et bekræftet waypoint eller en opsøgt node. Gamle release-/kildebuild-værdier er metadata. Klientens faktiske adfærd er ikke testet i denne fase.

## Fase 28: faktisk udført
Read-only `RecipeSourcePlanningBridge.lua` integreret i UniversalCurrentStep, ActionQueue, GuideSteps, CurrentStepTravelBridge og CurrentStepCompletionChain. Legacy SourceResolver og native dispatch er uændrede. Kontroller DATA_SOURCE_COVERAGE_189.csv, QA og README_FIRST; stop aldrig efter kun at have tilføjet en diagnostik.
