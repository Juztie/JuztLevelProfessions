local _, JLP = ...

local I = {
    STRANGE_DUST = 10940,
    LESSER_MAGIC = 10938,
    GREATER_MAGIC = 10939,
    SMALL_GLIMMERING = 10978,
    LARGE_GLIMMERING = 11084,
    SOUL_DUST = 11083,
    LESSER_ASTRAL = 10998,
    GREATER_ASTRAL = 11082,
    SMALL_GLOWING = 11138,
    LARGE_GLOWING = 11139,
    VISION_DUST = 11137,
    LESSER_MYSTIC = 11134,
    GREATER_MYSTIC = 11135,
    SMALL_RADIANT = 11177,
    LARGE_RADIANT = 11178,
    DREAM_DUST = 11176,
    LESSER_NETHER = 11174,
    GREATER_NETHER = 11175,
    SMALL_BRILLIANT = 14343,
    LARGE_BRILLIANT = 14344,
    ILLUSION_DUST = 16204,
    LESSER_ETERNAL = 16202,
    GREATER_ETERNAL = 16203,
}

local N = {
    [I.STRANGE_DUST] = "Strange Dust",
    [I.LESSER_MAGIC] = "Lesser Magic Essence",
    [I.GREATER_MAGIC] = "Greater Magic Essence",
    [I.SMALL_GLIMMERING] = "Small Glimmering Shard",
    [I.LARGE_GLIMMERING] = "Large Glimmering Shard",
    [I.SOUL_DUST] = "Soul Dust",
    [I.LESSER_ASTRAL] = "Lesser Astral Essence",
    [I.GREATER_ASTRAL] = "Greater Astral Essence",
    [I.SMALL_GLOWING] = "Small Glowing Shard",
    [I.LARGE_GLOWING] = "Large Glowing Shard",
    [I.VISION_DUST] = "Vision Dust",
    [I.LESSER_MYSTIC] = "Lesser Mystic Essence",
    [I.GREATER_MYSTIC] = "Greater Mystic Essence",
    [I.SMALL_RADIANT] = "Small Radiant Shard",
    [I.LARGE_RADIANT] = "Large Radiant Shard",
    [I.DREAM_DUST] = "Dream Dust",
    [I.LESSER_NETHER] = "Lesser Nether Essence",
    [I.GREATER_NETHER] = "Greater Nether Essence",
    [I.SMALL_BRILLIANT] = "Small Brilliant Shard",
    [I.LARGE_BRILLIANT] = "Large Brilliant Shard",
    [I.ILLUSION_DUST] = "Illusion Dust",
    [I.LESSER_ETERNAL] = "Lesser Eternal Essence",
    [I.GREATER_ETERNAL] = "Greater Eternal Essence",
}

local function out(itemID, chance, minQty, maxQty)
    return { itemID=itemID, name=N[itemID], chance=chance, minQty=minQty, maxQty=maxQty }
end

-- First production disenchant model. Forever sources currently describe the same
-- item-level material bands; probability/quantity weights use Classic continuity.
-- Keep the evidence explicit so a later Forever-specific audit can replace it.
local ARMOR = {
    {5,15,  out(I.STRANGE_DUST,0.80,1,2), out(I.LESSER_MAGIC,0.20,1,2)},
    {16,20, out(I.STRANGE_DUST,0.75,2,3), out(I.GREATER_MAGIC,0.20,1,2), out(I.SMALL_GLIMMERING,0.05,1,1)},
    {21,25, out(I.STRANGE_DUST,0.75,4,6), out(I.LESSER_ASTRAL,0.15,1,2), out(I.SMALL_GLIMMERING,0.10,1,1)},
    {26,30, out(I.SOUL_DUST,0.75,1,2), out(I.GREATER_ASTRAL,0.20,1,2), out(I.LARGE_GLIMMERING,0.05,1,1)},
    {31,35, out(I.SOUL_DUST,0.75,2,5), out(I.LESSER_MYSTIC,0.20,1,2), out(I.SMALL_GLOWING,0.05,1,1)},
    {36,40, out(I.VISION_DUST,0.75,1,2), out(I.GREATER_MYSTIC,0.20,1,2), out(I.LARGE_GLOWING,0.05,1,1)},
    {41,45, out(I.VISION_DUST,0.75,2,5), out(I.LESSER_NETHER,0.20,1,2), out(I.SMALL_RADIANT,0.05,1,1)},
    {46,50, out(I.DREAM_DUST,0.75,1,2), out(I.GREATER_NETHER,0.20,1,2), out(I.LARGE_RADIANT,0.05,1,1)},
    {51,55, out(I.DREAM_DUST,0.75,2,5), out(I.LESSER_ETERNAL,0.20,1,2), out(I.SMALL_BRILLIANT,0.05,1,1)},
    {56,60, out(I.ILLUSION_DUST,0.75,1,2), out(I.GREATER_ETERNAL,0.20,1,2), out(I.LARGE_BRILLIANT,0.05,1,1)},
    {61,65, out(I.ILLUSION_DUST,0.75,2,5), out(I.GREATER_ETERNAL,0.20,2,3), out(I.LARGE_BRILLIANT,0.05,1,1)},
}

local WEAPON = {
    {6,15,  out(I.STRANGE_DUST,0.20,1,2), out(I.LESSER_MAGIC,0.80,1,2)},
    {16,20, out(I.STRANGE_DUST,0.20,2,3), out(I.GREATER_MAGIC,0.75,1,2), out(I.SMALL_GLIMMERING,0.05,1,1)},
    {21,25, out(I.STRANGE_DUST,0.15,4,6), out(I.LESSER_ASTRAL,0.75,1,2), out(I.SMALL_GLIMMERING,0.10,1,1)},
    {26,30, out(I.SOUL_DUST,0.20,1,2), out(I.GREATER_ASTRAL,0.75,1,2), out(I.LARGE_GLIMMERING,0.05,1,1)},
    {31,35, out(I.SOUL_DUST,0.20,2,5), out(I.LESSER_MYSTIC,0.75,1,2), out(I.SMALL_GLOWING,0.05,1,1)},
    {36,40, out(I.VISION_DUST,0.20,1,2), out(I.GREATER_MYSTIC,0.75,1,2), out(I.LARGE_GLOWING,0.05,1,1)},
    {41,45, out(I.VISION_DUST,0.20,2,5), out(I.LESSER_NETHER,0.75,1,2), out(I.SMALL_RADIANT,0.05,1,1)},
    {46,50, out(I.DREAM_DUST,0.20,1,2), out(I.GREATER_NETHER,0.75,1,2), out(I.LARGE_RADIANT,0.05,1,1)},
    {51,55, out(I.DREAM_DUST,0.22,2,5), out(I.LESSER_ETERNAL,0.75,1,2), out(I.SMALL_BRILLIANT,0.03,1,1)},
    {56,60, out(I.ILLUSION_DUST,0.22,1,2), out(I.GREATER_ETERNAL,0.75,1,2), out(I.LARGE_BRILLIANT,0.03,1,1)},
    {61,65, out(I.ILLUSION_DUST,0.22,2,5), out(I.GREATER_ETERNAL,0.75,2,3), out(I.LARGE_BRILLIANT,0.03,1,1)},
}

JLP.data.disenchant = {
    schema = 1,
    status = "classic-continuity-first-model",
    evidence = "forever-bands-plus-classic-probabilities",
    itemIDs = I,
    itemNames = N,
    armor = ARMOR,
    weapon = WEAPON,
}

-- Forever guide estimates use tooltip Requires Level, NEVER ItemLevel.
-- Shard quantities are not specified; no implicit yield of one is assigned.
JLP.data.disenchant.foreverGuide={
 contract="forever-disenchant-required-level-guide-v1",levelDomain="REQUIRES_LEVEL",
 sourceURL="https://www.wow-professions.com/forever/disenchanting-guide",
 evidence="FOREVER_GUIDE_ESTIMATE_NOT_BUILD70532_LOOT_TABLE",observedDate="2026-10-25",
 abilitySource="WITH_ENCHANTING_REFERENCE_NOT_CURRENT_LEARNED_STATE",
 abilityUI="PROFESSIONS_ENCHANTING_BOX_NOT_SPELLBOOK_REFERENCE",
 itemEligibility="UNKNOWN_REQUIRES_ITEM_SPECIFIC_EVIDENCE",
 rareProbabilityConflict="SHARD100_TEXT_VS_RARE_CRYSTAL_ESTIMATE_NOT_EXACT_DISTRIBUTION",
 -- min,max,dustID,dustMin,dustMax,essenceID,essenceMin,essenceMax,shardID,crystalID
 bands={
 {1,10,10940,1,2,10938,1,2},
 {11,15,10940,2,3,10939,1,2,10978},
 {16,20,10940,4,6,10998,1,2,10978},
 {21,25,11083,1,2,11082,1,2,11084},
 {26,30,11083,2,5,11134,1,2,11138},
 {31,35,11137,1,2,11135,1,2,11139},
 {36,40,11137,2,5,11174,1,2,11177},
 {41,45,11176,1,2,11175,1,2,11178},
 {46,50,11176,2,5,16202,1,2,14343},
 {51,55,16204,1,2,16203,1,2,14344,20725},
 {56,60,16204,2,5,16203,1,3,14344,20725},
 },nativeDispatchAllowed=false,inventoryCreditAllowed=false,
}
