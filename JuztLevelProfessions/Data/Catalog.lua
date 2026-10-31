local _, JLP = ...

JLP.data.professions = {
    TAILORING = {
        key = "TAILORING",
        name = "Tailoring",
        kind = "crafting",
        maxSkill = 300,
        primary = true,
        linked = { "ENCHANTING" },
        routeStatus = "route-1-300-integrated",
    },
    ENCHANTING = {
        key = "ENCHANTING",
        name = "Enchanting",
        kind = "crafting",
        maxSkill = 300,
        primary = true,
        linked = { "TAILORING" },
        routeStatus = "route-1-300-integrated",
    },
    ALCHEMY = {
        key = "ALCHEMY", name = "Alchemy", kind = "crafting", maxSkill = 300, primary = true,
        routeStatus = "production-candidate-readonly", sourceBuild = 70245, productionEnabled = false,
    },
}

JLP.data.routeContract = {
    minSkill = 1,
    maxSkill = 300,
    strategies = { "fastest", "economical", "self_found" },
    actionKinds = { "learn", "train", "craft", "disenchant", "vendor", "auction", "farm", "complete" },
    evidenceLevels = { "forever-verified", "classic-continuity", "provisional", "user-research-horde-v1", "user-research-horde-v2" },
    ahSnapshotPolicy = "last-successful-manual-scan",
}
