# Current release candidate: 0.34.156-rc1

This package contains the repaired candidate described in `README_RELEASE_DA.md`, `CHANGELOG.md` and `TESTPLAN_DA.md`. Current client 1.60.1.70532 is user-reported test context, not a required build. Historical build labels identify source evidence.

Offline regressions do not establish live client acceptance or complete 1–300 coverage for all twelve professions. Unqualified progression/access data and item-specific disenchant eligibility remain explicit limitations. Follow the current test plan before release approval.

The entries below are retained integration history from the supplied archive. Their candidate names and historical verification claims refer to those earlier versions, not a new verification of this candidate.

# JuztTravel / JuztTom integrated candidate 1

Baseline: 0.34.0-build70450-ah-incremental-price-guarded-r1 (uploaded 2026-10-18 08:38).
Sources: JuztTom standalone 0.1.0-alpha9-test1; existing JLP integrated JuztTravel backend.

- JuztTom's six-tab design UI, HUD, motion and visual assets have been embedded under the JLP namespace.
- Settings contains the dedicated `JuztTom Settings` button; opens the original UI on Behaviour.
- Per-character settings are stored in `JuztLevelProfessionsDB.account.juztTom.characters`.
- JLP keeps a single event owner and one renderer. Existing JLP travel network and live verification gates are preserved.
- `IntegratedNavigationHUD` remains solely for legacy world-space geometry/diagnostics; no legacy HUD frame is initialized.

**Status: development candidate, not in-game verified.** End-to-end JuztTravel standalone parity, dynamic routes/Fishing route integration, standalone-profile migration, client-only API behaviour and zone/reload resumption need targeted in-game QA before production release. Use a backup of the current addon and SavedVariables.


### Candidate5: JuztTom menu readability and route diagnostics (2026-10-18)
- Base: Candidate4 source; player map reported in-game as UIMapID 1454 (Orgrimmar). Previous Tirisfal-only assumption revoked.
- Raised JuztTom-owned small font templates (GameFontHighlightSmall/GameFontNormalSmall) to a minimum 14 pt in its six-tab UI, theme buttons, and legacy settings panel. No changes to global WoW font templates or the separate in-world arrow text-size setting.
- Advanced > Diagnostics now exposes the destination owner's travel route reason, player and destination map IDs, navigation and geometry states; reflowed the diagnostic field to stay above its action buttons.
- Current Step route from Orgrimmar 1454 to Undercity 1458 remains UNVERIFIED; this update does not authorize, synthesize, or auto-advance transport. Client test required.

### Candidate6: staged Orgrimmar–Undercity navigation (2026-10-18)
- Candidate5 in-game QA: font readability and layout passed; Current Step selected Doctor Herbert Halsey with player UIMapID 1454 and target 1458, but `NO_VERIFIED_ROUTE` persisted.
- Diagnosed missing city-to-exterior topology in integrated Planner. Canonical R002 does exist (Durotar 1411 -> Tirisfal Glades 1420), but full city-to-city traversal is not represented by qualified edges.
- Added strict staged/advisory guidance: on 1454 show manual gate-exit instructions (no invented city waypoint); on 1411 point toward canonical authorized R002 source platform; on 1420 reuse existing approximate Undercity ingress hint; on 1458 existing owner map-change logic may replan local guidance.
- `routeVerified=false`, `autoAdvance=false`, no taxi/zeppelin dispatch, no fabricated city map walk edge, no native journey advancement; final trainer destination remains canonical.
- Candidate6 is **not** a complete validated transport journey. Actual map changes, platform arrival, zeppelin progress and /reload continuity remain for in-game QA and follow-up implementation.
- Fixed an older integration metadata inconsistency: Bootstrap version previously still displayed Candidate1 while TOC reported Candidate5; both now report Candidate6.

### Candidate7: generisk map-topologi og sikker rejsevejledning (2026-10-18)
- **Eksakt baseline:** Candidate6 `0.34.0-build70450-city-transit-candidate6`. Alt andet addonindhold og den godkendte JuztTom-brugerflade er bevaret.
- Ny intern, klientuafhængig `Core/IntegratedTravel/MapTransitions.lua`. Den opbygger en map-level søgegraf fra godkendte transportedges og særskilt registrerede by/zone-par. Korte på samme kontinent eller fælles UiMap-forælder udløser aldrig implicitte forbindelser.
- De eksplicitte by/zone-par er Orgrimmar (1454) ↔ Durotar (1411) og Undercity (1458) ↔ Tirisfal Glades (1420). De er **vejledende relationer**, ikke præcise gennemgange eller bevis for gangbarhed. Tilføj først yderligere par efter konkret kvalifikation.
- Valg af transportedge bruger `Network:CanTraverse` samt native karakter-faction, klasse, level og dokumenterede taxi unlock-observationer. Ejermarkerede og bekræftede stationsknudepunkter er påkrævet; ikke-kvalificerede research-koblinger kan ikke give adgang.
- `IntegratedTravelEngine:GetStagedGuidance` anvender nu denne generelle model frem for en destinationshardcode til Undercity. Den returnerer næste map-stage ud fra klientens faktiske `Player Map` og markerer alt som `routeVerified=false`, `autoAdvance=false` og `nativeDispatchAllowed=false`.
- I en transitplatforms sikre native verdensradius skifter status til `WAIT_FOR_TRANSPORT`, uden at give transporttilladelse eller markere boarding/ankomst. Kun et faktisk, efterfølgende kortskift ændrer den vejledende næste etape.
- JuztToms binding viser ikke længere den endelige NPC-koordinat som en fiktiv pil ved en tekstbaseret byudgang. Stage-instruktionen vises i stedet, mens det kanoniske slutmål bevares.
- Bevarer stage-navnet `DUROTAR_ZEPPELIN_R002` og nuværende UI/typografi/indstillingspersistens. Versionsmetadata i TOC og Bootstrap rapporterer Candidate7.
- **Offline QA:** 341 Lua-filer har bestået Lua 5.4-syntaks; mock-kørsler bestod city-exit, R002, city-ingress, native platform-wait, forkert kort, Alliance-afvisning, klassebegrænsning, uoplåst/opnået Flight Path og spoof-afvisning. Det faktiske OwnerAuthorizedNavigation-katalog under mockede build-70450 UiMap-navne gav 47 stationsposter og 162 kvalificerede edges; Orgrimmar → Undercity-corridoren blev planlagt korrekt.
- **Begrænsninger:** Ingen live WoW Forever-test udført af Candidate7. Ukendte landbaserede nabozoner, præcise byporte, animationer og alle transportovergange er fortsat ikke fuldt verificerede. Fuld, automatisk genoptagelse efter `/reload` forbliver kilde-/karaktergated via eksisterende TravelContinuity og revalidering. Ingen opfundne map-koordinater eller transport-ETA.

### Candidate8: reversibel city/exterior-navigation uden stale-lock (2026-10-18)

- Baseline: præcis Candidate7. WoW Forever-spiltest: første Undercity-indtræden gav WORLD_VERIFIED / WALK_TO_WAYPOINT; tilbagevenden til Tirisfal udløste `UNEXPECTED_ZONE_REVALIDATION_REQUIRED`, som blokerede genindtræden.
- Kun native-bekræftet udgang fra en kvalificeret lokal bydestination til en eksplicit dokumenteret by-/zoneparring kan genoprette en vejledende etape. Den aktuelle transportgraf skal også levere `ENTER_DESTINATION_CITY` til det samme bykort.
- Ukendte kort, manglende position, ændret karakter, ikke-lokale ruter, stale plan, stop/pause og ikke-verificeret build forbliver blokeret. Ingen automatisk NPC-/craft-/transportankomst.
- Den originale destination forbliver i hukommelsen. Ved faktisk tilbagevenden til bykortet forsøger `AttemptLocalRouteAfterMapChange` igen en lokal rute.
- Kandidaten er **offline-testet**, men endnu ikke testet i WoW Forever efter fejlrettelsen. `/reload`-genoptagelse kræver fortsat den eksisterende kildevalidering og er ikke løst generelt af Candidate8.

### Candidate9: generel sikker tilbagevenden og Tirisfal reference (2026-10-18)
- Baseline: præcis Candidate8. Live WoW Forever: brugerens fire screenshots bekræfter, at Tirisfal 1420 kan genindtræde Undercity 1458 med NAVIGATING / AVAILABLE og WORLD_VERIFIED uden genvalg af destination.
- Generel `ArmNativeReturnRecovery` / `RecoverNativeReturn`: alle allerede kvalificerede lokale WALK-destinationer kan genskabe deres egen rute ved faktisk C_Map-verificeret tilbagekomst til præcis samme kort; ukendte mellemliggende kort forbliver STALE uden opfundne transportkanter. Bevarer karakter/build/source-kontekst og pausering. Andre rejsetyper må ikke auto-recoveres på denne måde.
- For eksplicit attesterede city/zone-overgange findes fortsat Candidate8s aktive staged guidance; nye forbindelser skal tilføjes som verificerede map-pairs. Ingen implicit kontinent-/parent-map linking.
- Tirisfal indgangsreference ændret fra 1420:61.8/74.5 til brugerangivet 1420:62.0/66.0 på både MapTransitions og Corridor (vejledende, ikke produktionsevidens for NPC eller transport).
- Selvstændig /reload- og login-persistens, ukendte transportkorridorer og alle verdenszoner er ikke dermed fuldt spilverificeret.

### Candidate10: Ruins of Lordaeron indgangsreference (2026-10-18)
- Eksakt baseline: Candidate9 `0.34.0-build70450-general-native-return-candidate9`. Candidate9 fortsat bruger-verificeret for Tirisfal 1420 → Undercity 1458 med automatisk aktiv trainer-navigation.
- Brugerangivet korrektion af omtrentlig Ruins of Lordaeron-indgangsreference: UIMapID 1420, X 61.90 %, Y 65.10 % (tidligere X 62.00 %, Y 66.00 %). Ændret konsekvent i `Core/IntegratedTravel/MapTransitions.lua` og `Core/IntegratedTravel/Corridor.lua`.
- **Kun markørdata, ikke landing-/entrance-attest eller native ankomstbevis.** Spilleren rapporterer Y-koordinaten under 0.1 %-point fra klientens zonegrænse, men dette er brugerobservation, ikke generel kort- eller walkability-evidens. Selve indtræden kræver observeret UIMapID 1458.
- Ingen ændringer i ruteautorisation, progression, Current Step-kilden, JuztTom UI, NPC-/stationkoordinater, datasæt eller persistens.
- Candidate10 er offline-regressionstestet men det nye præcise landmark kræver endnu spiltest. Generel native-return-regression er kun delvis spilverificeret fra Undercity-Tirisfal-eksemplet; andre kort skal testes.


### Candidate11: generel transporttilgængelighed og automatisk `/reload`-genoptagelse (2026-10-18)
- Eksakt baseline: Candidate10 `0.34.0-build70450-ruins-reference-candidate10`. Version: `0.34.0-build70450-reload-continuity-candidate11`.
- Brugerens nye datapolitik: **alle strukturelt registrerede kort-/transportforbindelser i grafen er med i vejledende ruteberegning uanset `verified`, `draft`, `confirmed`, `clientVerified` eller `ownerAuthorized`-markeringer**. Registreringskontrakten (valide punkter, kendte endepunkter, gyldig provenance og entydige ID'er) gælder stadig. Fraktion, klasse og level respekteres; bekræftet låste Flight Paths afvises. Manglende flyvepunktundersøgelse er UNKNOWN og skjuler ikke længere forbindelsen i en vejledende rute – aktuel flyveadgang og boarding sker manuelt i spillet.
- `Core/IntegratedTravel/Network.lua`, `Planner.lua`, `MapTransitions.lua` og `Core/IntegratedTravelEngine.lua`: fjernet evidens- og nodestatus-gates på registrerede kanter; bevaret regelmæssig gameplay-adgangskontrol. Kendte eksplicitte by-/zoneovergange er fortsat eneste automatisk tilladte *gangbare kortskift*; kort-/AreaTable-databaserne dokumenterer ID'er, ikke vejforbindelser. Ingen opdigtede terræn- eller transportkanter.
- `/reload`: `IntegratedDestinationOwner` gemmer en afgrænset kilde-identitet sammen med aktiv navigation og karakter-/kort-intention. `TravelContinuity70450` genindlæser den ubetroede kildeinformation, validerer den igen gennem `SourceResolver` (eller tidligere eksplicit valgt manual waypoint), kontrollerer karakter og position med native C_Map og beregner en NY rute. Første `PLAYER_ENTERING_WORLD` udløser genoptagelse; manglende positionsdata giver forsinkede kortkontroller. JuztTom opdateres efter vellykket genoptagelse.
- Ingen aktiv etape, waypoint-ankomst, transportboarding eller tidligere ruteleg genetableres uden ny observation. Brugerstop, invalidation eller pause genaktiveres ikke utilsigtet. SavedVariables er fortsat pr. karakter. Eksisterende Candidate10-checkpoints har ikke kildebevis: **vælg Navigate To én gang efter installation af Candidate11, og test derefter med `/reload` uden yderligere klik**.
- Offline: 341 Lua-filer syntaksbestået; simuleret kilderevalideret auto-resume, ny ruteberegning, manglende position, stop, source-tampering, gammel checkpoint, karakterisolation, uverificerede node-/kantstatusser samt fraktion/taxi-adgang bestået. **Live World of Warcraft Forever-test af Candidate11 afventer**.
- Godkendt JuztTom seksfanet UI, tekstskalering og Ruins of Lordaeron 1420 / 61.90 / 65.10 er uændret.


### Candidate16: Current Step/Gathering source separation and manual Routes isolation (2026-10-18)
- **Baseline:** exact Candidate15. Current Step remains an explicit selection of the ACTIVE learned profession, resolved through existing Planner/SourceResolver and canonical JuztTravel owner; JuztTom renders the current stage and HUD.
- **Gathering button:** now requests the current READY route from GatheringRouteService using map, generation, context token and overlay receipt; only an accepted route is handed to `IntegratedDestinationOwner:SelectGatheringStop`. Switching mode cannot silently keep showing the previous trainer destination. Generation and context mismatches are rejected without inventing waypoints.
- **Routes tab:** user-authored/manual waypoints only (plus an explicit demo when started by the user). Gathering Map generated waypoint collections remain owned by Gathering Map and never appear as a manual JuztTom route; the manual list is not overwritten. Route-switching control for generated routes is hidden.
- **Gathering progression:** eligible selected gathering stop is synchronized to the shared destination owner on advancement. Internal evidence and access checks remain unchanged; no automatic gathering, invented node claim or native movement.
- **In-game result:** pending. Lua 5.4 syntax and mocked mode-switch/owner tests passed. Same-map gathering arrows and non-local gathering map routing still require in-game verification.


## Candidate17 (2026-10-18)
- READY GatheringRouteService generation can be selected for navigation even if UI overlay paint acknowledgement is absent; overlay presentation state remains visible in owner diagnostics.
- Stale tokens, non-READY generation, invalid coordinates, and unknown gathering maps remain rejected.
- Deliberate switch to Herbalism without a qualified Current Step clears obsolete profession destination and saved auto-resume intent; manual destination is preserved.
- Candidate16 remains the source baseline; WoW Forever live verification is pending.


### Candidate22: One-click professionsnavigation fra Gathering (2026-10-18)
- Præcis baseline: Candidate21 `0.34.0-build70450-flight-destination-focus-candidate21`.
- Brugerens WoW Forever-test: Den aktive Herbalism Gathering-rute viser korrekt `Fly to The Crossroads`, `Flight Master: Doras`, men første tryk `Set active` på Alchemy ændrer kun fokus. Andet tryk fremkalder JuztTravel-stadiet `Leave Orgrimmar into Durotar`.
- Årsag: `StandaloneDisplay.lua` havde en udtrykkelig `self.mode=="GATHERING" and oldFocus~=s.key` focus-only-gren. Den sprang `ActivateCurrentStepTarget` over for første klik.
- Rettelse: `Set active` kalder nu én gang `ActivateCurrentStepTarget` uanset forrige navigationsmode. `IntegratedNavigationActions` kvalificerer kilden, den fælles `IntegratedDestinationOwner` overtager destinationen, og `IntegratedTravelEngine` leverer ruten. JuztTom skifter først visuel mode ved godkendt destinationsanmodning.
- Hvis den nye profession mangler Current Step, forbliver en igangværende Gathering-rute aktiv, og årsagen vises på Professions-siden. Ved eksplicit skift mellem to professionskilder ryddes en forældet kilde uden at påvirke brugerens manuelle ruter.
- Uændret: Gathering Map-ruten, alle transportdata og Flight Path-observationer, indstillinger, navigationens Pause/Resume/Stop og `/reload`-checkpoints.
- Offline QA: alle 341 Lua-filer består Lua 5.4 syntax-kontrol; isoleret UI callback-test, første klik under Gathering samt fallback med manglende Current Step består. Ikke live-verificeret i WoW Forever.
- Fortsat særskilt begrænsning: `DESTINATION_ONLY_NO_ROUTE` / `Leave the city` kan stadig være resultatet af en JuztTravel-etape uden verificeret lokalt byudgangs-waypoint. Candidate22 opfinder ikke et waypoint for at vise en pil.
