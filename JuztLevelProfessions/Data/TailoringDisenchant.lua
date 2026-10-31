local _, JLP = ...

-- Tailoring items that can serve as disenchant sources. Item IDs / item levels
-- are verified against Forever item pages; probability/yield comes from the
-- separate disenchant model and remains explicitly evidence-tagged there.
local CANDIDATES = {
    { recipe="Double-stitched Woolen Shoulders", itemID=4314,  itemLevel=22, kind="armor", evidence="forever-item-level-verified" },
    { recipe="Gloves of Meditation",             itemID=4318,  itemLevel=26, kind="armor", evidence="forever-item-level-verified" },
    { recipe="Azure Silk Cloak",                 itemID=7053,  itemLevel=35, kind="armor", evidence="forever-item-level-verified" },
    { recipe="Crimson Silk Vest",                itemID=7058,  itemLevel=37, kind="armor", evidence="forever-item-level-verified" },
    { recipe="Crimson Silk Pantaloons",          itemID=7062,  itemLevel=39, kind="armor", evidence="forever-item-level-verified" },
    { recipe="Black Mageweave Gloves",           itemID=10003, itemLevel=43, kind="armor", evidence="forever-item-level-verified" },
    { recipe="Black Mageweave Headband",         itemID=10024, itemLevel=46, kind="armor", evidence="forever-item-level-verified" },
    { recipe="Runecloth Belt",                   itemID=13856, itemLevel=51, kind="armor", evidence="forever-item-level-verified" },
    { recipe="Brightcloth Cloak",                itemID=14103, itemLevel=55, kind="armor", evidence="forever-item-level-verified" },
    { recipe="Runecloth Pants",                  itemID=13865, itemLevel=57, kind="armor", evidence="forever-item-level-verified" },
    { recipe="Mooncloth Robe",                   itemID=18486, itemLevel=61, kind="armor", evidence="forever-item-level-verified" },
}

JLP.data.tailoringDisenchant = {
    schema = 1,
    status = "first-production-candidate-map",
    sourceBuild = 70009,
    candidates = CANDIDATES,
}
