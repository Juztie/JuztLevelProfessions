# WoW Forever – TOC og interfacekompatibilitet

Fra v0.34.179 har `JuztLevelProfessions.toc` deklarationen `## Interface: 16000, 16001`.
Begge værdier er dokumenteret i offentlige Forever-addonudgivelser; v0.34.179
har kun offline-kontrol, så den faktiske klientaccept skal testes ingame.

Det er **ikke** et krav til addonens datasæt eller API-kald at have en bestemt
buildversion. `Interface` er en statisk loaderdeklaration, som WoW læser før Lua.
Et nyt klient-interface kan derfor give en *Out of date*-markering, selv når
alle nødvendige runtime-API'er fortsat findes.

## Nyt klient-interface (uden at ændre addonens kode)

1. Start klienten og skriv `/run print(select(4, GetBuildInfo()))` i WoW-chatten.
2. Notér det numeriske interface-ID, luk derefter WoW helt.
3. Åbn PowerShell i denne `Tools`-mappe og kør:
   `./Set-JuztLevelInterface.ps1 -InterfaceVersion <DET_OBSERVEREREDE_TAL>`
4. Scriptet bevarer allerede deklarerede versioner, sætter den observerede værdi
   først og opretter en `.toc.bak`. Det kræver ingen administratorrettigheder.
5. Hvis klienten ikke understøtter flere værdier, kan `-SingleVersion` bruges.
   Dette betyder ikke, at addonens API'er er kompatible; det kræver fortsat test.

`-WhatIf` viser ændringen uden at skrive den.

På klienter, hvor scripts ikke må køre, kan kun den ene `## Interface:`-linje
opdateres manuelt til den observerede værdi. Ingen native calls, ledger,
SavedVariables, kildebuild eller professionsmoduler ændres af værktøjet.

**Advarsel:** Med en fremtidig klient, hvor Blizzard har fjernet nødvendige API'er,
kan en opdateret TOC ikke genoprette de manglende funktioner. Benyt client-
capability-diagnostik og ingame QA. Undlad at oplyse historiske buildnumre som
aktuelt interface-ID; build 70532 er ikke det samme som Interface 16001.
