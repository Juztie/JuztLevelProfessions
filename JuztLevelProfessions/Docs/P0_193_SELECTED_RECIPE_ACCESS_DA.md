# P0 Fase 32 – Selected Recipe Access & Acquisition v0.34.193

Baseline v0.34.192. **Targeted, exact SpellID facts from selected AH/no-AH routes**.

- Added 22 Tailoring recipe minimum-skill entries from https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes (public Forever guide dated 2026-10-12), and Enchanting 13882 from its Forever spell page.
- Important conflict: earlier Mooncloth spell reference stated 230, current guide gives 250; earlier Mooncloth Robe 275, guide lists 300. Treat pattern access and actual crafting requirement as different facts; the stricter 250/300 gate is **advisory conservative** and reports `minimumSourceConflict=true`.
- Public acquisition modes: Bright Yellow Shirt vendor Danielle Zipstitch (Duskwood), Dark Silk Shirt generic vendor, Lesser Agility formula drop category. None gives a verified NPC-to-item DB join or canonical navigable waypoint. No automated route is created.
- Learned != accessible; exact skill minima do not certify NPC stock, faction access, source availability, skill-up results, native execution, or all-profession completeness.
- API panel observations and SavedVariables continue to be advisory for planning. Existing owner/gated navigation and ledger unchanged.
- WoW Forever server unavailable for ingame QA; release readiness due 2026-11-03, 2026-11-04 is play day.
