local _, JLP = ...
-- Curated WOWHEAD FOREVER recipe/skill-gate corrections. These records describe
-- READ-ONLY preview routing, not production recipe modifications or permissions.
-- Historical routes remain immutable; optional NPC/TradeSkill snapshots are not required.
JLP.data.foreverStarterCorrections = {
    contract="forever-public-starter-corrections-v1",
    sourceBuild=70245,
    ALCHEMY={
        blockedRecipeID=1245246, blockedMinSkill=10,
        substituteRecipeID=7183, substituteMinSkill=1,
        substituteOrangeThrough=55,
        correctionEndSkill=10,
        sourceURLs={
            "https://www.wowhead.com/forever/spell=7183/elixir-of-minor-defense",
            "https://www.wowhead.com/forever/spell=1245246/minor-arcane-elixir",
        },
        reason="Forever recipe 1245246 requires Alchemy 10; recipe 7183 is orange from skill 1 through 55.",
    },
}
