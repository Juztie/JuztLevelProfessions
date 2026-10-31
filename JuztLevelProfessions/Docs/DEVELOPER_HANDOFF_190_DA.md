# Udvikleroverdragelse 0.34.190 (P0 Fase 29)

Udviklingsbaseline v0.34.189, nu v0.34.190, rollback v0.34.189. Deadline 3. november 2026; 4. november er spilledag, ikke testdag.

Læs bindende `Docs/DEVELOPER_PRODUCT_CONTRACT_DA.md` samt `READ_ME_FIRST.md` i handoffpakkens rod. 1–300 Current Step beregnes fra addondata, learned/unlearned, beholdning, valgfri AH, materialegenbrug, skill-opportunity og JuztTravel/JuztTom (uden krav om historiske klient-evidence logs). Green=25% standard; 20–30% brugerjusterbar, Yellow=60%, Orange=100%, Gray=0%. Camp-workstations udelukket, almindelige krævede workstations bevaret. Ingen native autorisation via read-only source-data.

Ændret: `Core/RecipeSourcePlanningBridge.lua`, `Core/CurrentStepTravelBridge.lua`, `Data/ForeverAcquisitionModes190.lua`, TOC, Bootstrap samt projektdokumentation. Bevarer alle tidligere addonfiler.

Kildedækning: 2.664 DB-kildeposter, 2.001 med teaching-item-link, 33 med mindst en navngiven aktørreference i det samlede nu indlæste research-delgrundlag, 2.631 uden. Et historisk named-research match kan ikke give vendor-stock, dropchance, faction-adgang eller GPS-autorisation. Elixir of Minor Agility (ID 3230/item 2553) har kildeverificerede generelle anskaffelsesformer fra Wowhead, ikke præcis NPC.

Simuleret test: 51/51 regressioner PASS; 362/362 Lua syntaks PASS; 12 professioner x med/uden AH = 24 hele 1–300 reference/scenarier PASS med eksplicitte gaps; ikke live-klient. Native crafting/recovery kode er uændret.

Næste P0: udvid kildekataloget kilde-for-kilde med eksakt SpellID↔itemID↔NPC/loot/quest relationsdata fra Wowhead Forever og brugeroriginaler. Prioriter de recipes, som optimeringsmotoren faktisk vælger under fulde 1–300-simuleringer. Dernæst tilføjes træner, vendor, bank og AH destinationer via OwnerAuthorizedNavigation uden opfundne koordinater. Integrér learn/material/skill progression i GUI, test UI og native workflows klientnært, inkl. reload/zone hop, karaktergrænser og lagrede SavedVariables hvis originaler senere genfindes. Ingen claim om fuld produktion før checks er bestået.
