# Klienttest for JuztLevel Professions 0.34.156 rc1

Formålet er at godkende faktiske spillerforløb i WoW Forever efter de automatiserede rettelser. Testene er ikke udført i klienten som del af denne leverance. Brugeren har oplyst 1.60.1.70532 som aktuel klient. Andre builds kan bruges, når API-kontrakterne er kompatible.

## Opstart og gemte data

- Kontrollér version 0.34.156-rc1 og aktivér almindelig visning af Lua-fejl.
- Åbn hovedvindue, Guide, Overview, Settings, Bank, Auction House, History, Gathering Map og JuztTom. Notér fejl, clipping og uventede tomme flader.
- Kontrollér små og store vinduer, den anvendte UI-skala og Gathering Maps zoom.
- Kør `/jlpaudit release` og bevar observationssnapshot.
- Genindlæs med `/reload`. Kontrollér, at egne indstillinger og bankhistorik fortsat kan læses.
- Skift karakter. Personlige gatheringobservationer og aktive mapindstillinger må ikke være tilskrevet den forkerte karakter. Arkiveret ældre historik må ikke være slettet.

## Tailoring og materialer

- Åbn professionen og kontrollér et tidligt interval, et opdelt interval og et sent interval, som karakteren faktisk har adgang til.
- Samme opskrift i to intervaller må ikke give en falsk dubletfejl.
- Kontrollér råvarer, eksisterende bolts, bankmaterialer og eventuelle værktøjsinput. Samme enhed må højst være reserveret én gang.
- Følg en bankhandling. Guide og overlay skal pege på samme aktuelle handling; crafting bliver først umiddelbart klar, når materialerne findes i bags.
- Udfør en legitim Craft One fra et faktisk lært recipe med nok materialer. Bekræftet craft og faktisk skillstigning er to forskellige observationer; ingen skill-up er også et gyldigt craftresultat.
- Stop eller afbryd et forløb og genindlæs. Flytning af reagenter eller en unrelated skill-up må ikke alene godkende en gammel pending craft.

## Enchanting

- Kontrollér lært recipe, nødvendigt tool, reagentantal og et konkret valgt target.
- Flyt eller fjern target før handling. Der skal ske ny kontrol, før en native enchant tillades.
- Udfør en legitim enchant og kontrollér popup-/bekræftelsesforløb og historik.
- Afbryd, skift recipe, skift target og brug `/reload` på adskilte forsøg. Der må ikke udføres en skjult gentagelse.
- Tailoring/disenchant-alternativer skal være tydeligt betingede, når itemadgangen er ukendt. De må ikke erstatte en gennemførlig kilde som en falsk sikker anbefaling.

## Auction House økonomi og strategier

- Udfør et nyt manuelt scan. Ældre snapshots er utilstrækkelige til de nye helauktionspriser.
- Find en vare, som sælges i større stacks end dit behov. Kontrollér faktisk købssum og overskydende antal.
- Sammenlign flere stackstørrelser og utilstrækkelig quote-depth. Addonen må ikke vise et opdigtet delkøb af en udelelig auktion.
- Afbryd et scan eller luk AH. Det tidligere snapshot må ikke erstattes af et fejlagtigt komplet nyt snapshot.
- Kontrollér kendt og ukendt pris, manglende penge samt et delvist prissat indkøb. Ukendt total må ikke vises som nul eller som fuldt betalelig.
- Skift mellem Fastest, Economical og Self-found. AH må ikke blive en godkendt Self-found-handling alene, fordi et scan findes.
- På et senere klientbuild skal et nyt scan kunne gennemføres med de tilgængelige API'er. Snapshot fra en anden session/build skal genkvalificeres.

## Gathering og navigation

- Test Herbalism og Mining i Smart og Custom med Skill, Materials og Balanced.
- Test OBSERVED_ONLY med egne punkter, som ikke fandtes i den historiske database.
- Test et valg med nul mulige punkter og en afbrudt generation. Begge kortflader skal vise det afsluttede resultat.
- Ved skill 300 skal et reelt materialebehov fortsat kunne give materialevejledning i BALANCED.
- Vælg Current Step, derefter en gatheringstop, derefter et manuelt waypoint. Der skal være én aktiv destination, og baggrundsopdateringer må ikke overtage et eksplicit manuelt mål.
- Test Stop, Pause, Resume, zoneskift og `/reload`. Genoptagelse skal beregne ud fra aktuel position og kildeintention.
- Kontrollér en lokal service på samme MapID og en rejse via en faktisk tilgængelig transportforbindelse. Navigationens ankomst må ikke i sig selv fuldføre bank, køb, træning eller crafting.
- Kontrollér relevante lokaliserede klientnavne, hvis flere locales skal understøttes. Numerisk forkert map eller maptype skal stadig afvises.

## Øvrige professioner og godkendelse

For Alchemy, Blacksmithing, Engineering, Leatherworking, Skinning, Cooking, First Aid og Fishing kræves særskilte forløb fra flere aktuelle skillniveauer. Katalog, reference eller en enkelt succesfuld craft dokumenterer ikke en fuld 1–300-rute.

For hver profession registreres hvilke intervaller, recipes, rankgates, arbejdsstationer, kilder, materialer, UI-handlinger og navigationsoverdragelser der faktisk er testet. Et manglende obligatorisk interval eller en ukendt nødvendig adgang er en åben releaseblokering for løftet om en fuld guide til den profession.

Endelig release kræver, at de funktioner og professioner, som releasen lover, har bestået de relevante scenarier uden åbne fejl, falske pris-/mængdeudsagn, fejlagtig completion eller uautoriseret gentagelse. Gem log og versionsidentitet sammen med godkendelsen.
