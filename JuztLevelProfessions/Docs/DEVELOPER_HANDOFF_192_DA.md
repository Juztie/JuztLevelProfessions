# Teknisk udvikleroverdragelse – JuztLevel v0.34.192

**Brug denne version som eneste kodebaseline.** Rollback = 0.34.191. Handoff pakker original API-export, opslagsværk, produktbeskrivelse, kumulativ audit, fuld kode, QA/kildediff og prioriteret next work. Ingen andre roller eller gamle chats kræves.

- Ny recipe-minimum-adgangskontrol på `Core/ProfessionRecipeMinimumGate.lua` og `Data/ForeverRecipeMinimums192.lua`. Historical DB `rawMinRank=1` er *ikke* recipe skill floor.
- Minimumskilder fra Wowhead Forever for 2963,2964,22902,11479, samt ForeverDiff for 18560. YELLOW er en **konservativ senere eligibility bound**, ikke egentlig minimumskill, og kun anvendelig med learned=true.
- Ny eksakt kilde fra public Wowhead Forever + DB teaching item: 11479→9304→Alchemist Pestlezugg i Tanaris. Den er **ikke** navigationsautoritet.
- 55 regressioner og 366 TOC-lua-parse PASS; 24 prisfri/prissat all-12-scenarier; 428 rutesegmenter, 410 uden navngiven NPC-kilde, 278 manglende skillovergange (dobbelt talt over AH/no-AH). Ingen ingame tests.
- Næste P0: ret actual skill-learning-min for udvalgte opskrifter med Forever beviser, komplete vendor/trainer/drop-relations for *valgte* recipes; simulér C_TradeSkillUI learned/recipe colors, brugerens inventory + bank, AH med/uden scan, JuztTravel owner waypoint, manual/native-fenced action, event skill-up, /reload og zone hop. Fjern ikke native gates.
- Releasefærdig senest 3. nov 2026; 4. nov er spil og ikke testing.
- **Fast handoff:** næste aflevering både selvstændig installerbar addon ZIP og selvstændig kompakt QA/handoff ZIP, med ny READ_ME_FIRST.md, alle aktuelle kodefiler, original relevant dokumentation, rollback, QA samt ny version og nye tests.
