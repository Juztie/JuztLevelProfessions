# UniversalRouteOptimizer – P1 Fase 24

Input: DB70450 skillgrænser og reagenter, learned status via professionen, aktuelle/sidst kendte prisreferencer og bagbeholdning. Buildnummer er dataproveniens og **ikke** tilladelse eller blokering.

API:
- `Planner:GetBestCurrentStep(key, professionOverride, options)` giver aktuelt anbefalet trin og en 20-skill prognose.
- `Planner:GetProfessionRouteForecast(key, options)` giver kildebaseret fremtidsscenarie mod skill 300 inklusive åbne huller.
- `UniversalRouteOptimizer:Forecast(...)` og `:PlanTo300(...)` er read-only. `:PlanMaterials(...)` viser rekursiv materialsimulering.

Modelgrænser: orange 100%, gul 60%, grøn 30% er eksplicitte **heuristikker**, ikke WoW Forever-målte skillchanceprocenter. De bruges udelukkende til at sammenligne *scenarier* og er aldrig garanterede crafts. Uverificeret trainer-/vendor-/pattern-tilgængelighed giver ingen learning- eller native-rettigheder. Specialisering/cooldowns/stationer skal kvalificeres særskilt. Kildebaseret outputantal må ikke bruges som live-outputkvittering.

Mellemvaregrafen tager KUN eksternt kildebelagte faste outputmængder fra `RecipeOutputYields.lua` og `ForeverIntermediateOutputs.lua`; ItemID hentes fra SpellEffect-referencen. Acyklisk rekursion maksimalt tre dybder. Lagerforbrug kan kun tælles én gang i skill-rækkefølge. Fremtidigt producerede varer kan genbruges, men ikke bagud i tid. Oversigt over indkøb er en prognose – ikke et faktuelt materialeforbrug.

Gathering professionerne er ikke eksekverbare craft-forecasts. AH-scanning er valgfrivillig; uden priser kan en strategi stadig rådgive uden at påstå pris-optimum. Begrænset forecast beskytter UI-mod memory/CPU; fuld 1–300-forecast skal efterspørges eksplicit.

Kilder: DB70450 fra addonen; eksisterende Forever-recipe-kildearkiv. Supplerende Wowhead Forever, 2026-10-23:
https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes
https://www.wowhead.com/forever/guide/professions/alchemy-overview-trainer-locations-recipes
https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes
https://www.wowhead.com/forever/guide/professions/first-aid/overview

Source completeness cannot be inferred from DB spell thresholds: a difficultly band does not prove source/vendor availability or learned status. The accompanying all-profession matrix is potential raw-threshold coverage, NOT a confirmed leveling route.
