# JuztLevel Professions — bindende produkt- og udviklingskontrakt

Version 0.34.190 · Målsætning gælder alle efterfølgende udviklingsversioner.

## Produktmål

- Samtlige 12 professioner skal have en brugbar, sammenhængende guide fra skill 1 til 300; ingen profession må udelukkes alene på grund af build, client/interface-version eller et internt produktionsflag.
- **Current Step** skal ud fra profession, aktuel skill/rang, allerede lærte og ikke-lærte recipes, inventory, bankreferencer og dokumenterede opskrift-/anskaffelsesdata vælge bedste mulige næste trin og vise alle nødvendige materialer, kilder og alternative trin.
- **Auction House-scanning er valgfri.** Med AH-data sammenlignes relevante priser og craft-vs-buy; uden data fungerer guiden fortsat uden at opdigte markedstal.
- Beregn på tværs af fremtidige trin: mats, output-yield, mellemprodukter, anskaffelser, rejsehensyn og progression; genbrug allerede ejede eller fremstillede produkter, undgå dobbelttælling.
- **JuztTravel og JuztTom er en fast del af Current Step.** For train, learn, vendor/NPC, bank, AH og relevante samlesteder skal guide/Planner vise en source- og owner-kvalificeret navigationsstatus via det fælles `IntegratedDestinationOwner`, `IntegratedTravelEngine` og `IntegratedJuztTom`. Brug de kanoniske JuztTravel/owner-destinationskoordinater; en uverificeret NPC eller manglende koordinater må give `LOCATION_UNVERIFIED`, aldrig opfundne koordinater. Eksisterende manuelt waypoint og stop-tilstand skal beskyttes. Ingen automatisk bevægelse eller crafting.
- Brug først de eksisterende JuztLevel-kataloger, kilder, trainer-/vendor-/drop-relationer og koordinater. Søg manglende præcise oplysninger på **https://www.wowhead.com/forever**; brug anden dokumenteret ekstern kilde kun efter behov. Sæt ikke opdigtede NPC'er, koordinater, dropchancer eller opskriftsgrænser ind.
- Opskrifternes **orange/yellow/green/gray** farve bruges i ruteoptimering. Aktuel farve kan læses gennem `C_TradeSkillUI.GetRecipeInfo` når muligt. Den eksisterende adaptive `RecipeTelemetry` skal kunne benyttes, hvis valide data findes, men er aldrig nødvendig for Current Step. Hvis intet kvalificeret sandsynlighedsestimat findes, bruges de brugerautoriserede **planlægningsscenarier Orange 100 %, Yellow 60 %, Green 25 % (tilladt 20–30 %), Gray 0 %**. Dette er scenarieprocenter, ikke klientmålte chancer. Overgang Yellow→Green må aldrig fremstilles som verificeret, hvis DB alene leverer Yellow-/Gray-grænser. Historiske cutoffs må bruges som reference, ikke som bevis for aktuel farve.
- Recipe-output og outputintervaller læses fra `C_TradeSkillUI.GetRecipeSchematic` (felterne `quantityMin`, `quantityMax`, `outputItemID`) når API'et findes. Kendte faste kilde-yields kan bruges med tydelig proveniens. Interval/ukendt yield er ikke et sikkert materialebudget.
- Træner- og vendor-/droprelationer skal knyttes til eksakte item-/recipe-/NPC-ID'er med kilde, korrekt faction og koordinatdomæne, hvis kilden faktisk indeholder dem.
- **Camp-workstations er eksplicit udelukket** fra planlægning, krav og navigation. Reelt krævede almindelige faciliteter som **Anvil, Forge, Fireplace, Cooking Fire, Moonwell eller Spinning Wheel** kan medtages, men må ikke antages at eksistere ved enhver trainer uden dokumentation.
- Ingen indsamling af historisk klient-evidence er en forudsætning for advisory-guide, Current Step eller budgetberegning. Aktuelle ikke-persistente WoW API-kald er tilladte til skill/learned/farve/yield-status. Native crafting har uændrede selvstændige sikkerhedsgates.

## Korrektheds- og acceptkriterier

1. For hvert skillpunkt 1–299: enten vis et dokumenteret muligt trin eller forklar præcis hvilke data der mangler; aldrig fabrikeret craftantal eller sandsynlighed.
2. Med og uden AH skal samme aktuelle karakter tilbydes en konkret next step eller en tydelig trainer/learn/verify/gather-opgave; ukendt lager er aldrig nul.
3. Reagensbehov beregnes over flere trin med genbrug af mellemprodukter, adgangs-/rankkrav og alternative acquisition paths.
4. Aktuelt lærte og ulærte recipes håndteres særskilt, med dynamisk genplanlægning når skill, opskrifter, lager eller prisændringer observeres.
5. Offlinetests kontrollerer alle 12, materialegenbrug, ukendt pris/lager, API-fejl, variabelt output, stationsexclusion og ingen uautoriseret native dispatch. Ingame-beviser må ikke kræves som input til planlægning; slutstatus baseres på bedste offline-simulation og tydeligt erklærede begrænsninger før 3. november.
6. Ingen build-allowlists må deaktivere planlægning. Kildebuild er provenance, ikke krav til brugerens klient.

## QA-/arkivpolitik

Fremtidige udviklingspakker skal være **kompakte, flade og uden indlejrede tidligere kumulative ZIP-filer**. Bevar aktuelle installationsfiler, én rollback, en versions- og SHA-256-manifest, ændringsdiff, aktuelle regressionstests, tekniske beslutninger, uafklarede mangler og en original referenceindeks. Ældre store arkiver kan opbevares separat, men må ikke indlejres igen og igen. Bevar historisk sporbarhed med checksums og beslutningslog.

## Nuværende afgrænsning

Skill-chance Yellow/Green er ikke dokumenteret i procent. En enkelt 1–300-scenarieberegning er ikke en garanti for antal crafts eller globalt optimal rute, når datagrundlaget er ufuldstændigt.

## Obligatorisk overdragelsesprocedure ved HVER aflevering

1. Aflever **to downloadfiler**: én komplet, selvstændig installerbar addon-ZIP og **én kompakt selvbærende overdragelses-/QA-ZIP**.
2. Den kompakte ZIP skal have `READ_ME_FIRST.md` i arkivets **rod** og skal kunne vedhæftes i en ny ChatGPT-samtale. Filen skal forklare præcis, hvad næste udvikler skal læse, gældende baseline, roller, mål, tidligere beslutninger, åbne fund og næste opgave.
3. Medtag **hele seneste addonversion** (installations-ZIP med alle kildefiler), én fuld rollback, aktuel produktbeskrivelse/referenceindeks, kumulativ teknisk hovedaudit, vigtig API-/datadokumentation hvor lovligt/tilgængeligt, samtlige aktuelle QA-regressioner og resultater, kilde-delta, SHA-256/manifest og åbne datamangler. Historiske, tunge ZIP'er må IKKE kædes indlejret.
4. En ny samtale skal kunne fortsætte direkte fra medfølgende kildekode og instruktioner uden at kende den gamle samtale. Den nye udvikler skal først læse `READ_ME_FIRST.md`, derefter udviklerkontrakt, teknisk handoff og tests, verificere versionsidentitet og fortsætte den åbne opgave.
5. Manglende originalmateriale skal stå eksplicit i handoff og må ikke stiltiende erstattes af en genereret reference. Ældre originalarkiver kan henvises med verificerede checksumværdier uden at kopiere deres store indhold.

## Ubetinget releasekrav – korrigeret tidslinje

- **3. november 2026:** Brugerens mål er en færdigprogrammeret, integreret og bedst muligt offline-verificeret releaseklar addon. Kode- og QA-arbejde prioriteres, så fejl ikke udskydes til releasedagen.
- **4. november 2026:** World of Warcraft Forever lanceres. Brugeren skal SPILLE, ikke udføre planlagte ingame-tests. Undgå at bruge denne dag som udviklings-/acceptvindue.
- Da klienten/serverne ikke er tilgængelige før release, skal der bruges realistiske API-/SavedVariables-/event-/navigation-simuleringer og eksisterende dokumenterede tidligere ingame-observationer. Simuleret PASS må aldrig beskrives som faktisk ingame-verifikation eller som en garanti for ukendte klientforhold.

## QA i perioden uden aktive WoW Forever-servere

Brugeren oplyser, at serverne er nede **til 4. november 2026**. Indtil da er faktiske ingame-tests ikke mulige. Alle kørsler skal derfor tydeligt markeres **OFFLINE SIMULATION**, og testmiljøet skal simulere faktiske WoW-API'er, ejede navigationskilder, ændring af lært recipe/skill, bag-data, AH med/uden scanning, build-API mangler, waypoint-prioritet, `/reload`, zoneskift, eventkvitteringer og manglende koordinater. Disse testresultater må ikke omdøbes til ingame-accept. Nye udviklere skal fortsætte arbejdet uden at afvente brugerens klienttests.

## Kildebro og næste udviklingsfase (v0.34.189)
`RecipeSourcePlanningBridge.lua` bruger præcis RecipeID og kildebyggede teaching-item-relationer som rådgivning. Kildebygnings-ID er dataproveniens, ikke klient-lås. NPC-kilder vises kun med faktisk registreret identitet og kompatibel faction. Research-lokationer giver aldrig et navigerbart waypoint uden canonical JuztTravel-owner kvalificering.
Færdiggør fortsat manglende trainer/vendor/drop/quest-NPC identiteter og koordinater via eksisterende ownerdatabase først, efterfulgt af præcise Wowhead Forever-links. Bevar UNKNOWN for manglende relationer. De øvrige 11 professioner og Tailoring skal alle til sidst have komplette 1–300 workflows.

## P0 Fase 31 – recipe learning minimum og yellow-gate
Brug eksakt required profession skill fra aktuelle WoW Forever recipe-/itemreferencer hvor det findes. Historical SkillLineAbility MinRank er ikke recipe required skill. Hvis eksakt minimum mangler, må et learned recipe tidligst medtages i gul-grænse-referencescenarie, som KONSERVATIV eligibility bound, aldrig som autentisk learning minimum. Grey 0 % er ikke craftable progression. Ingen native craft-autoritet tildeles via den nye planlægning. Alle 12 professioner kræver stadig end-to-end dæknings- og sourcesimulering.
