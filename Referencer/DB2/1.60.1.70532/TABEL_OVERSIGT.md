# DB2 CSV-tabeloversigt – build 1.60.1.70532

73 fulde CSV-filer. Poster er eksklusive header; kolonnebredde, UTF-8-sig-CSV og unikke numeriske ID’er kontrolleres af eksisterende qualifier. De oprindelige 65 CSV er byte-identiske med den tidligere audit.

| Tabel | Poster | Kolonner | Identitet mod 65-filers grundlag |
|---|---:|---:|---|
| AreaPOI | 372 | 24 | Ny i 73-filers tillæg |
| AreaTable | 1,375 | 29 | Uændret |
| AreaTrigger | 333 | 17 | Uændret |
| AreaTriggerActionSet | 245 | 2 | Uændret |
| AreaTriggerCreateProperties | 14 | 4 | Uændret |
| AreaTriggerSphere | 8 | 2 | Uændret |
| ChrClasses | 9 | 43 | Uændret |
| ChrRaces | 58 | 62 | Uændret |
| Creature | 184 | 20 | Uændret |
| CreatureFamily | 27 | 12 | Uændret |
| CreatureFamilyXUIModelScene | 23 | 3 | Uændret |
| CreatureType | 13 | 3 | Uændret |
| CreatureXDisplayInfo | 193 | 7 | Uændret |
| CurrencyCategory | 6 | 5 | Uændret |
| CurrencyTypes | 9 | 25 | Uændret |
| Faction | 253 | 40 | Uændret |
| FactionGroup | 4 | 6 | Uændret |
| FactionTemplate | 453 | 22 | Uændret |
| GameObjects | 1,526 | 26 | Uændret |
| Item | 31,875 | 17 | Uændret |
| ItemDisenchantLoot | 54 | 8 | Ny i 73-filers tillæg |
| ItemEffect | 12,651 | 10 | Uændret |
| ItemExtendedCost | 1,101 | 28 | Uændret |
| ItemNameDescription | 93 | 3 | Uændret |
| ItemSearchName | 6,641 | 19 | Uændret |
| ItemSparse | 19,257 | 104 | Uændret |
| ItemXItemEffect | 12,643 | 3 | Uændret |
| Lock | 311 | 34 | Uændret |
| LockType | 23 | 7 | Uændret |
| Map | 73 | 30 | Uændret |
| Path | 13 | 8 | Ny i 73-filers tillæg |
| PathEdge | 98 | 4 | Ny i 73-filers tillæg |
| PathNode | 99 | 4 | Ny i 73-filers tillæg |
| PathProperty | 8 | 4 | Ny i 73-filers tillæg |
| PlayerCondition | 1,944 | 162 | Uændret |
| Profession | 12 | 11 | Ny i 73-filers tillæg |
| ProfessionEffect | 1 | 4 | Ny i 73-filers tillæg |
| QuestLineXQuest | 22 | 6 | Uændret |
| QuestV2 | 6,616 | 3 | Uændret |
| SkillLine | 154 | 15 | Uændret |
| SkillLineAbility | 7,853 | 20 | Uændret |
| SkillRaceClassInfo | 186 | 9 | Uændret |
| Spell | 31,962 | 4 | Uændret |
| SpellCastingRequirements | 3,272 | 8 | Uændret |
| SpellCastTimes | 72 | 3 | Uændret |
| SpellCooldowns | 4,496 | 7 | Uændret |
| SpellEffect | 42,726 | 37 | Uændret |
| SpellEquippedItems | 1,886 | 5 | Uændret |
| SpellFocusObject | 244 | 2 | Uændret |
| SpellItemEnchantment | 2,217 | 33 | Uændret |
| SpellLearnSpell | 52 | 4 | Uændret |
| SpellLevels | 12,957 | 7 | Uændret |
| SpellMisc | 31,942 | 34 | Uændret |
| SpellName | 31,962 | 2 | Uændret |
| SpellReagents | 3,300 | 34 | Uændret |
| SpellTotems | 1,121 | 6 | Uændret |
| TaxiNodes | 100 | 20 | Uændret |
| TaxiPath | 328 | 4 | Uændret |
| TaxiPathNode | 10,778 | 11 | Uændret |
| TotemCategory | 28 | 4 | Uændret |
| TradeSkillCategory | 216 | 7 | Uændret |
| TradeSkillItem | 3,240 | 2 | Uændret |
| TraitCurrencySource | 187 | 10 | Uændret |
| TraitTreeXTraitCurrency | 13 | 4 | Uændret |
| TransportAnimation | 1,016 | 7 | Uændret |
| UiMap | 60 | 15 | Uændret |
| UiMapArt | 144 | 4 | Uændret |
| UiMapArtStyleLayer | 6 | 10 | Uændret |
| UiMapArtTile | 1,672 | 6 | Uændret |
| UiMapAssignment | 61 | 18 | Uændret |
| UiMapXMapArt | 60 | 4 | Uændret |
| WorldMapOverlay | 1,081 | 16 | Uændret |
| WorldMapOverlayTile | 1,739 | 6 | Uændret |

Kildebegrænsninger, relationer og runtimepolitik: se `00_LAES_MIG_FOERST.md` og `Tools/DB2_70532_AFLEVERING.md` i projektets rod. Ingen fuld CSV indlæses i WoW-runtime.
