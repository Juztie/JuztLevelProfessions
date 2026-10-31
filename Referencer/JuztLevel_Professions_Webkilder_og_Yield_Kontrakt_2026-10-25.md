# JuztLevel – WoW Forever professionskilder og fast output-kontrakt

**Version:** 2026-10-25  
**Anvendelse:** Tilføj denne fil til `D:\JuztLevel - Codex\Referencer\`. Den er en udviklingsreference, ikke en runtime-afhængighed.  
**Arbejdsstatus ved oprettelse:** Tailoring 102–107 er ifølge den seneste Codex-aflevering `COMPLETED`; seneste faktisk bekræftede klienttest er fortsat begrænset.  
**Omfang:** Kildekatalog og konkret yield-kontrakt. Ingen tilladelse til at omskrive alle professioner, oprette parallelle databaser eller ændre native dispatch.

## 1. To forskellige typer kilder

### A. Opskriftskatalog: ForeverTalent

- https://wowforevertalent.com/professions/tailoring/
- https://wowforevertalent.com/professions/enchanting/
- https://wowforevertalent.com/professions/alchemy/
- https://wowforevertalent.com/professions/blacksmithing/
- https://wowforevertalent.com/professions/engineering/
- https://wowforevertalent.com/professions/leatherworking/
- https://wowforevertalent.com/professions/mining/
- https://wowforevertalent.com/professions/cooking/
- https://wowforevertalent.com/professions/first-aid/

Supplerende katalogsider til samtlige 12 professioner (ikke angivet i brugerens første URL-liste):
- https://wowforevertalent.com/professions/herbalism/
- https://wowforevertalent.com/professions/skinning/
- https://wowforevertalent.com/professions/fishing/

**Anvendelse:** Spell-ID, reagent- og produceret item-ID, katalogdækning, alternative recipes og publicerede yellow-/grey-grænser. Siden oplyser, at orange er under yellow, og at grøn er midpoint mellem yellow og grey; grønne grænser skal derfor ikke ophøjes til selvstændige, observerede klientværdier. `Learn rank: Not recorded` er ikke bevis for, at alle spillere kan lære en opskrift. Gathering-oversigterne dokumenterer ikke specifikke world-spawns, mob-drops eller fangstresultater. Siden er mærket **FOREVER BETA DATA**; vær kritisk ved buildforskelle.

### B. Leveling-ruter: WoW-Professions Forever

- https://www.wow-professions.com/forever/tailoring-leveling-guide
- https://www.wow-professions.com/forever/enchanting-leveling-guide
- https://www.wow-professions.com/forever/alchemy-leveling-guide
- https://www.wow-professions.com/forever/blacksmithing-leveling-guide
- https://www.wow-professions.com/forever/engineering-leveling-guide
- https://www.wow-professions.com/forever/leatherworking-leveling-guide
- https://www.wow-professions.com/forever/mining-leveling-guide
- https://www.wow-professions.com/forever/cooking-leveling-guide
- https://www.wow-professions.com/forever/first-aid-leveling-guide
- https://www.wow-professions.com/forever/fishing-leveling-guide
- https://www.wow-professions.com/forever/fishing-and-cooking-leveling-guide

**Anvendelse:** Alternative end-to-end-ruter, skillovergange, forventede antal crafts, globale materialebudgetter, mulige NPC'er og indkøbs-/gatheringsekvenser. Hjemmesiden erklærer eksplicit, at indkøbslisterne er **estimater**, at guiden stadig er under udarbejdelse, og at betadata kan ændres. Dens foreslåede "fastest/cheapest"-rute er ikke automatisk optimal for den aktuelle karakter, inventory, faction, marked eller de tre JuztLevel-strategier. En angivet NPC uden verificeret kortidentitet/koordinat giver ikke handlingsautorisation til en waypoint.

## 2. Brugerfastlagt output-kontrakt – præcis én enhed pr. gennemført cast

Brugeren har fastslået, at følgende **seks navngivne Tailoring-spells altid producerer ét output-item per succesfuldt cast**. Dette er en eksplicit produkt-/planlægningskontrakt og understøttes også af ForeverTalent-opskriftsposter. Dette er ikke en påstand om en ny in-game-måling i den aktuelle session. Hvis fremtidig konkret Forever-runtime eller nyere verificeret schematic viser en konflikt, skal den registreres og forelægges brugeren – ikke stiltiende overskrive denne kontrakt.

| Recipe | Spell-ID | Reagent pr. cast (katalog) | Output pr. succesfuldt cast |
|---|---:|---|---:|
| Bolt of Linen Cloth | 2963 | 2 Linen Cloth | **1** |
| Bolt of Woolen Cloth | 2964 | 3 Wool Cloth | **1** |
| Bolt of Silk Cloth | 3839 | 4 Silk Cloth | **1** |
| Bolt of Mageweave | 3865 | 5 Mageweave Cloth | **1** |
| Bolt of Runecloth | 18401 | 5 Runecloth | **1** |
| Mooncloth | 18560 | 2 Felcloth | **1** |

Reference: https://wowforevertalent.com/professions/tailoring/ (katalogets Reagents-sektion, opslagsdato 2026-10-25). Reagentmængder skal stadig krydskontrolleres med build 70532-DB2 og tidligere klient-schematics, og være markeret efter faktisk proveniens.

**Krav til implementation og tests:**
- Opdatér kun de relevante eksisterende feltkontrakter; opret ingen parallel yield-database.
- Sørg for, at `expectedOutputQuantity = 1` er separat fra `expectedSkillUp`, `expectedCraftCount` og `observedItemDelta`.
- Ved 10 planlagte Bolt of Silk Cloth-casts er forventet output 10 Bolts og råmaterialeforbrug 40 Silk Cloth, inden evt. kendt inventory eller faktisk gennemførte handlinger fratrækkes; dette er et planlægningsscenario, ikke observeret lager.
- Planlagte producerede mellemprodukter må kun regnes som planforsyning/afhængighed; de må ikke krediteres som aktuel inventory, før runtime-kvittering.
- En gul/grøn craft har ikke garanteret skill-up, selv om item-output er præcis 1.
- Kontroller grenserne for Tailoring 102–107 uden at åbne en ny fuld professionsimplementering.
- Regressionstests: nøjagtigt 1 item pr. cast for alle seks; korrekt råmaterialematematik og ingen dobbelttælling; UNKNOWN-beholdning; modstridende kilder → bevislog frem for tavs ændring; ingen ny native handlingsautorisation.

## 3. Autoritet og konfliktpolitik

1. Aktuel, konkret observeret klientsession (hvor tilgængelig) og verificeret aktuel client-schematic vurderes først efter semantik.
2. Buildkvalificerede DB2-felter (1.60.1.70532) bruges kun til det, de faktisk dokumenterer; `SpellEffect.EffectBasePointsF` er ikke alene bevis for observeret yield.
3. Brugerens eksplicitte beslutning om output=1 for de seks spells er et gældende planlægningskrav, understøttet af kataloget. Konkrete modsætninger skal synliggøres.
4. ForeverTalent er en struktureret ekstern katalogkilde, ikke universelt runtimebevis.
5. WoW-Professions er vejledende rute- og budgetkilde, ikke autoritativt dynamisk strategivalg.
6. Ukendt learned-state, NPC-/vendor-/droprelation, output for andre recipes, handlingstilladelse, zonekoordinater eller priser må ikke gættes. Bevar `UNKNOWN`/`VERIFY`.

## 4. Forslag til afgrænset næste Codex-opgave

**Opgave:** Registrér disse 23 links som udviklingsreferencer og sikr, at de seks Tailoring-yields står til **1** i det eksisterende katalog, Planner og materialeberegning. Ret kun konstaterede afvigelser, tilføj målrettede regressioner, og kør eksisterende Windows-QA. Rapportér konflikter med build 70532 og afslut uden at starte næste Tailoring-interval. Når denne opgave er godkendt, kan næste udviklingsopgave være en større sammenhængende del af Tailoring, i stedet for gentagne 3–5-point-opgaver.
