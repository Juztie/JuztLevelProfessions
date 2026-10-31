# JuztLevel – udvikleroverdragelse v0.34.187

## Mål og gældende baseline

Baseline: v0.34.186. Aktuel kandidat: v0.34.187. Bevar rollback v0.34.186. Kompakt QA, ingen kæde af indlejrede gamle arkiver.

## Funktionelle kontrakter

1. Alle 12 professioner skal give sammenhængende 1–300-anbefalinger med lærte/ulærte recipes, skill, reagentbehov og acquisition, også uden AH-scan eller klient-evidence. Kildeprioritet: eksisterende addondata, wowhead.com/forever, andre dokumenterede kilder. Kildebuild må ikke spærre planlægning.
2. Skill-up-rate: eksisterende RecipeTelemetry når kvalificeret; ellers Orange=100%, Yellow=60%, Green=25% (konfigurerbar 20–30%), Gray=0. Orange/gray color rules og Yellow/Green scenario mærkes tydeligt. En manglende Green-overgang i DB er ikke et verificeret threshold.
3. JuztTravel/JuztTom hører til Current Step. Trainer, NPC, vendor, bank, AH, gathering og almindelige nødvendige arbejdsstationer benytter kun owner-kvalificerede koordinater og en fælles navigationsvej. Ingen dobbelt destinationsowner; brugerens manuelle waypoint og Stop beskyttes. Manglende destination -> LOCATION_UNVERIFIED.
4. Camp-workstations ekskluderes, almindelige dokumenterede Forge/Anvil/Fireplace mv. kan bruges. Ingen native craftingautoritet tildeles af en advisory prognose.
5. WoW Forever-serverne er ifølge brugeren utilgængelige til 2026-11-04. QA sker indtil da via klientnære simulationsfixtures, **ikke** ved faktisk ingame-test.

## v0.34.187 konkret leverance

- `Core/SkillUpProbabilityPlanner.lua` genbruger RecipeTelemetry, med kilde- og stikprøvekrav; uden data bruges godkendt 100/60/25/0.
- `Core/UniversalRouteOptimizer.lua` genbruger beregneren i fremadrettet prognose, med cache pr. recipe frem for API/telemetry-læsning pr. repaint/skillpoint.
- `Core/CurrentStepTravelBridge.lua` forbinder Current Step med canonical owner-kilder og eksisterende rejse-/pilservices; planvisningen alene flytter ikke waypoint.
- `Core/UniversalCurrentStep.lua`, `Planner.lua`, `GuideSteps.lua` viderefører probability/proveniens, navigation og korrekt reagentantal til Guide.
- Regressioner og netværksfri simulationer følger med i QA-arkivet.

## Resterende arbejde

- Verificere fysisk tilgængelighed for alle trainer/vendor/droprelationer pr. profession og kildepræcist mapID/zoneID, samt komplette recipe-kataloger og 1–300-skills.
- Forbedre Yellow/Green transitions med kildekvalificerede thresholds. Udvid AI-/DB-baseret estimator til reel skill-range-konditionering i stedet for opskriftsglobal observation.
- Etablere normal arbejdsstations-NPC/-facilitetsintegration på dokumenterede koordinater, uden Camp-workstations.
- Integrere synlige JuztTom/Travel UI-actions i alle relevant Guide/Planner-paneler og verificere med klientnære eventtests.
- Endelig ingame-accept efter 2026-11-04: native Craft One/Craft All, AH, banks, transport, zone-hop, `/reload` og alle 12 professioner.

## QA-definition

OFFLINE SIMULATION PASS betyder kun, at simulerede API-/eventkontrakter består. Endelig klientaccept kræver efterfølgende test. Ingen nye build-allowlists eller uautoriseret native dispatch.
