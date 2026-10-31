# v0.34.179 – P1 TOC-loaderkompatibilitet

Denne vedligeholdelsesrevision deklarerer `## Interface: 16000, 16001` og har
et valgfrit offlineværktøj i `Tools/Set-JuztLevelInterface.ps1`, der bruger det
**faktisk observerede** interface-ID til at opdatere TOC for fremtidige/andre
klienter. Se `Tools/README_DA.md`. Det ændrer ikke runtime-API, dataproveniens
eller craftingautorisation. Den forrige releasebeskrivelse er historisk.

# JuztLevel Professions 0.34.156 rc1

Dette er en rettet releasekandidat baseret på 0.34.155. Den indeholder rettelser til de 15 fund i kodeanalysen samt regressionstests for de berørte kaldestier.

Pakken er endnu ikke godkendt som en fuld 1–300-release for alle 12 professioner. Nogle professionsforløb mangler fortsat kvalificerede progressionstal eller adgangsdata, og faktisk crafting, AH, bank, UI og navigation skal testes i WoW Forever. Kandidaten skjuler ikke disse datamangler og låser ikke generelt addonen til et bestemt klientbuild.

## Installation

1. Luk WoW Forever og tag en kopi af den nuværende addonmappe samt dens SavedVariables.
2. Udpak installationsarkivet. Arkivets øverste mappe hedder `JuztLevelProfessions`.
3. Placér den mappe i den relevante Forever-klients `Interface/AddOns`.
4. Kontrollér, at TOC-filen ligger direkte i `Interface/AddOns/JuztLevelProfessions` og ikke i en ekstra undermappe.
5. Start klienten og kontrollér, at versionen er `0.34.156-rc1`.

Kandidaten ændrer ikke automatisk din installation. Gemte indstillinger og observationer bruges fortsat via den eksisterende SavedVariable. Personlig gatheringhistorik flyttes til GUID-opdelte karakterposter. Ældre historik uden entydig ejer bevares i et arkiv frem for at blive tilskrevet den aktuelle karakter.

## Klientbuild og API

Brugeren har oplyst den aktuelle klient som 1.60.1.70532. Det er en testkontekst, ikke en adgangslås. Buildnumre 70009, 70245, 70374 og 70450 findes fortsat som oprindelse for historiske data. Tilgængelige API'er, observeret identitet, åben professionskontekst og den konkrete handling afgør, hvad der kan bruges.

Et AH-snapshot fra et andet observeret klientbuild bliver rådgivende, indtil et nyt scan er udført. Addonen kan stadig scanne på det nye build, når de nødvendige API'er findes. Det er en friskhedskontrol af prisdata og ikke en lås på hele funktionen.

## Vigtige ændringer

- Tailoring skelner mellem 31 rutesegmenter og 21 forskellige opskrifter. Samme opskrift må bruges i flere sammenhængende intervaller, mens modstridende recipefelter fortsat afvises.
- Recovery godkender ikke længere en bestemt craft alene på grund af en generel skillstigning, et bagtab eller et ændret enchant uden korreleret operationsbevis.
- Materialer, mellemprodukter og værktøjsinput kan ikke disponere den samme beholdning flere gange i de rettede planner-, readiness-, kø- og anskaffelsesforløb.
- AH-priser bevarer hele auktioners stackstørrelse og buyout. Købssum og overskydende enheder fremgår særskilt. Begrænset prisdybde og heuristiske løsninger på store forespørgsler beskrives som sådanne.
- Ukendt pris vises som ukendt og bliver ikke til et gratis køb.
- Current Step-overlayet bruger den samme køs aktuelle handling som Guide frem for altid at vise den planlagte recipe.
- Smart og Custom kan bruge kvalificerede personlige gatheringpunkter uden et historisk koordinatmatch.
- Gathering publicerer også tomme og fejlende slutresultater. BALANCED kan fortsat foreslå nødvendige materialer efter afsluttet skillprogression.
- Lokaliserede kortnavne kan bruges med validerede numeriske kortidentiteter uden et krav om klientbuild 70450.
- Manuel navigationsrecovery bevarer alle returværdier fra ruteplanlægningen.
- Observeret skill 300 giver en afsluttet levelingtilstand for alle 12 professioner, også når der ikke findes et klassisk craftingdatasæt.
- Anskaffelsesplanen viser observerede penge og om den kendte sum kan betales. En ukendt total godkendes ikke som betalelig.

## Afgrænsninger der stadig kræver arbejde

Fuld funktionsgodkendelse kræver mere end syntaks- og modultests. Der mangler især gennemgående klientaccept for professionsrejserne, komplette kildekvalificerede intervaller hvor data endnu er ufuldstændige, Skinning-område-/mob-outputdækning samt fulde Secondary-forløb efter de dokumenterede referenceintervaller.

Tailoring/disenchant vises fortsat som et betinget alternativ, når den aktuelle klients data ikke kan bevise det konkrete items disenchantkrav. At karakteren kender Disenchant beviser ikke alene, at alle kandidatitems kan disenchant'es. Kandidaten opfinder ikke skillgrænser og præsenterer ikke et sådant alternativ som sikkert gennemførligt.

AH-snapshots fra 0.34.155 mangler de nye helauktionsdata. De bevares som reference, men et nyt manuelt scan er nødvendigt for en kvalificeret købssum.

## Test i spillet

Brug den medfølgende `TESTPLAN_DA.md`. En afgrænset, passiv observationslog kan aktiveres med:

```text
/jlpaudit start
/jlpaudit release
/jlpaudit mark before-test
```

`/jlpaudit release` gemmer observeret build/interface, API-tilstedeværelse og professions-/planstatus. Den udfører ikke crafting, handler, køb eller transport. En sådan observation er ikke i sig selv en releasegodkendelse.

Efter test:

```text
/jlpaudit mark after-test
/jlpaudit status
/jlpaudit stop
```

Loggen gemmes i addonens SavedVariables under `JuztLevelP0LiveAuditDB`. Gem eventuelle Lua-fejl sammen med scenarie, faktisk forventning og karakterens profession/skill. Bevar oplysninger om den testede addonversion og klientbuild, så resultater kan knyttes til den rigtige pakke.
