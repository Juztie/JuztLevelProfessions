# P0 Fase 31 – 0.34.192-p0-recipe-minimum-access-gates

**Udviklingsbaseline:** v0.34.191; **aktuel:** v0.34.192; **rollback:** v0.34.191. **Releaseklarhed senest 3. november 2026; den 4. november er spilledag uden planlagte ingame-tests.**

## Implementeret

- `ProfessionRecipeMinimumGate`: Adskil faktiske recipe-minimumskills og guidevinduer fra DB70450 SkillLineAbility MinRank, som står `1` for 2.636 af de udlæste spellrækker og derfor IKKE repræsenterer et recipe learning-minimum.
- Eksakte Forever-referencer: Bolt of Linen Cloth skill 1, Bolt of Woolen Cloth skill 75, Mooncloth pattern skill 230, Mooncloth Robe pattern skill 275 og Transmute: Iron to Gold skill 225. Gemte source-URL'er og spell-/item-ID'er følger datamodulerne.
- **Konservativ fallback** når eksakt minimum mangler: DOKUMENTERET gult difficulty-skillpoint kan anvendes som en senere sikker planlægningsgrænse, KUN når opskriften er angivet lært. Dette er aldrig en påstand om recipeets faktiske læringsminimum, trainer- eller adgangsstatus. Aktuelt stabilt åbent professionsvindue kan rådgive om en lært opskrift uden fuldt kvalificeret minimum; ikke i syntetisk 1–300-forecast.
- Grey 0 % => recipe afvises før `ceil(1/p)`; undgår uendelige craftestimater.
- Recipe 11479 → teaching item 9304 → Alchemist Pestlezugg, Tanaris, public Forever kildehenvisning. Ingen koordinat opfundet, ingen vendor-stock- eller waypoint-godkendelse.
- 55/55 regressions-PASS, 366/366 TOC Lua-syntaks-PASS, 24/24 12-professions × AH/no-AH syntetiske prognoser PASS. De 24 prognoser har tilsammen **278 udækkede skill-overgange**; ikke komplet live 1–300-validering. 428 planlagte segments i samme scenarier, 410 uden navngiven kildereference. Modellen bruger en bevidst urealistisk "alle learned"-fixture for adgangsfuzzing, ingen egentlig bruger-karakter.

## Åbne P0-opgaver

1. Kvalificér faktisk minimumskill for flere valgte recipes mod eksakt Forever-id og item/Spell-læring; farvegrænse er midlertidig sen adgangsvurdering, ikke reelt minimum. Undgå samtidige spamrequests; prioriter `QA/SELECTED_ROUTE_SOURCE_GAPS_192.csv`.
2. Udfyld faktisk NPC/vendor/trainer/drop/quest-kæde for de valgte recipes og map kun nav tilladelser til `OwnerAuthorizedNavigation`.
3. End-to-end instrumentér reel UI data binding og hele Current Step/materialer/navigation/handling/progression med mockede C_TradeSkillUI, inventory, AH events, professionsskill events, SavedVariables, transport, reload, disconnect, unexpected native receipt; ingen nye native rettigheder.
4. Reducér modeldækningshuller og test realistisk learned-state per skillinterval. 4 gather-professioner har separat referenceplan, ikke en craft-forecaster.

Kilde-evidens: `https://www.wowhead.com/forever/spell=11479/transmute-iron-to-gold`, `https://www.wowhead.com/forever/spell=2963/bolt-of-linen-cloth`, `https://www.wowhead.com/forever/spell=2964/bolt-of-woolen-cloth`, `https://www.wowhead.com/forever/item=18487/pattern-mooncloth-robe`, `https://foreverdiff.com/recipes/mooncloth-10487/`. Fremmede kilder er rådgivende og aldrig native tilladelser.

**Fast handoff:** To ZIPs – standalone installabel addon + komplet kompakt handoff med READ_ME_FIRST.md direkte i roden, hele nye addon, én rollback, rapport, komplet QA, referenceoriginaler, provenance, samt dette udviklingstrin.
