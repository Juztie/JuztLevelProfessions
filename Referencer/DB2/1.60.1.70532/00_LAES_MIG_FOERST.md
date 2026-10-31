# WoW Forever DB2 – build 1.60.1.70532 | 73 CSV-tabeller

## Anvendelse
Dette er et **read-only kildearkiv** til udvikling af JuztLevel – Professions. Udpak ZIP-filen i `D:\JuztLevel - Codex`, så filerne kommer under `Referencer\DB2\1.60.1.70532`.

- 73 originale CSV-filer fra brugerens udvidede DB2-eksport. Der er ikke ændret én eneste CSV-byte.
- 27 CSV-filer er **byte-identiske** med den tidligere 27-filers eksport. De øvrige 38 i 65-filers grundlaget var tilføjelser. Yderligere otte tabeller er nu tilføjet; alle oprindelige 65 CSV er byte-identiske med den tidligere audit.
- `MANIFEST_SHA256.txt` dokumenterer CSV-integritet. `TABEL_OVERSIGT.md` viser de faktiske rækker og antal kolonner.
- Aktiv baseline har Tailoring 77–102 og den første DB2-integration afsluttet. Dette er et tillæg til samme DB2-opgave; Tailoring 102–107 er ikke påbegyndt.

## Datakontrakt
DB2 er klient-kildedata, IKKE en generel garanti for aktiv learned-state, live-API, faktisk craft-resultat, tilgængelig trainer/vendor, world-spawn, opdaget flyverute, pris eller beskyttet handling. Brug feltvis kildeproveniens. Afgør `MinSkillLineRank`, `TrivialSkillLineRankLow/High`, og `SpellEffect.EffectBasePointsF` semantik eksplicit; de er ikke automatisk recipe learning-minimum, komplette orange/yellow/green/gray-grænser eller bevis for live output-yield.

## Relevante nye tabeller
- `TaxiNodes` (100), `TaxiPath` (328), `TaxiPathNode` (10.778) – taxi-graph som kandidatkilde. Kun 315 af 328 TaxiPath-rækker har begge endepunkter i denne TaxiNodes-eksport; forkast/isolér de øvrige 13. Dokumentér separat live tilgængelighed, faction, ruteomkostninger og eventuelt manglende verdenskobling.
- `UiMapAssignment` (61), `UiMapArt*`, `UiMapXMapArt` – UIMap-geografi og art-tilknytning; `MapID`, `AreaID`, `UiMapID` er forskellige identiteter. Ingen sikre waypoints uden separat kvalificering.
- `PlayerCondition` (1.944), `SpellLearnSpell` (52), `SkillRaceClassInfo` (186), `SpellCastingRequirements` (3.272) – potentielle betingelses-/relationstabeller, men ikke en komplet trainer-, quest- eller recipe-adgangskæde.
- `Creature` (184) og `GameObjects` (1.526) – ikke en komplet NPC-/world-spawn-database. Navne/positioner i tabellerne må ikke automatisk forbindes med professionelle NPC'er eller tilgængelige spawns.
- `Lock`, `LockType`, `ItemExtendedCost`, `CurrencyTypes`, `FactionTemplate` – kan understøtte adgangs- og omkostningskrav, når den korrekte relation findes.

## Kildespecifikke checks
- Recipe 2963: `SpellReagents` → Linen Cloth item2589 x2; `SpellEffect` effect24 → Bolt of Linen Cloth item2996; EffectBasePointsF=1.
- Recipe 2964: `SpellReagents` → Wool Cloth item2592 x3; `SpellEffect` effect24 → Bolt of Woolen Cloth item2997; EffectBasePointsF=1.
- Dette understøtter item- og reagentidentitet. Det validerer ikke alene faktisk observeret output-yield. Eksisterende build70532 recipe-schematic-vidnesbyrd er et separat kildebevis.
- `SpellLearnSpell` har ingen post med `SpellID` 2963/2964/2402/3758; dette må ikke fortolkes som at opskrifterne ikke kan læres.

## Anbefalet sekvens
1. Verificér alle 73 CSV og kortlæg schema samt relevante joints under `Tools`, ikke i WoW-runtime.
2. Kvalificér konkrete felter for Tailoring 25–102 og næste 102–107 uden at gætte eller ændre validerede live-beviser.
3. Implementér kun nødvendige, kompakte, verificerede korrektioner i eksisterende Data/Planner-kæde.
4. Test eksisterende og nye krav via Windows-QA mod aktiv addon. Derefter fortsættes progression 102–107 som en ny opgave.
5. Taxi, map og transport bør blive selvstændig opgave, efter professionernes kildeintegration er stabil; ingen automatisk navigation ud fra rå DB2-rækker.

## Mulige senere eksporter
`SkillTiers` og `UiMapLink` findes ikke i den tilgængelige build70532-tabeloversigt. De er ikke nødvendige afhængigheder og skal ikke efterspørges som forudsætning. AreaPOI er nu inkluderet. Eksakte trainer/vendor/drop/world-spawn-relationer kræver selvstændige kilder eller observerede data, ikke blot flere tilfældige DB2-filer.

## Tillæg: otte nye tabeller (73 samlet)
- **Profession (12)**: SkillLineID/ProfessionEnumValue kan validere eksisterende ProfessionRegistry mod SkillLine. Profession.ID er en særskilt recordidentitet, ikke professionsenum. First Aid har enum0. Ingen caps, læring eller live status kan udledes alene heraf.
- **ProfessionEffect (1)**: rå effekt-type, Amount og ModifiedCraftingReagentSlotID. Ingen ProfessionID/SkillLineID-kolonne; ingen direkte dokumenteret join til Profession eller sikker professionseffekt i runtime.
- **ItemDisenchantLoot (54)**: Class/Subclass, Quality, MinLevel/MaxLevel, SkillRequired, ExpansionID. Ingen output-items, mængder eller sandsynligheder. Ikke en komplet loot-/yieldtabel eller tilladelse til disenchant. Negative enum/sentinel-værdier bevares rå, og eksisterende Classic-scenarier bliver ikke Forever-verificerede af denne tabel.
- **AreaPOI (372)**: world-positioner med Map-/Area-/conditionreferencer; koordinater er ikke automatisk UIMap-waypoints, NPC-positioner eller sikre port-/rejseforbindelser.
- **Path (13), PathEdge (98), PathNode (99), PathProperty (8)**: strukturelle path/node/edge-relationer. PathNode.LocationID kræver en separat kvalificeret Location-relation; koordinater, enheder og path-/property-enums må ikke gættes. Ingen pathfinding eller navigation implementeres i DB2-opgaven.

`MANIFEST_SHA256.txt` omfatter nu alle73CSV. Dokumentopdateringen ændrer ingen CSV-byte. Fuld schema-/relationsaudit og den samlede aflevering vedligeholdes under Tools. Eksisterende PowerShell-QA kontrollerer kildehashes og de genererede kompakte data; udviklingsqualifieren er ikke en ekstra runtime-/installationsafhængighed.
