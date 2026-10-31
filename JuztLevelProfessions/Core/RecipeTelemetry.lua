local _, JLP = ...

-- Persistent recipe efficiency telemetry derived from stable transaction#N
-- units in TransactionLedger. Alpha54 keeps skill-rate transfer conservative and
-- extends cross-build account consensus to exact material-consumption signatures.
-- Material consensus is evidence/diagnostics only: it can prove that observed
-- per-craft reagent behavior remained stable across independently observed builds,
-- but it never changes Planner quantities by itself. Difficulty never crosses
-- builds and remains strictly current-build evidence.
local RecipeTelemetry = {
    contract = "material-consensus-build-revalidation-recipe-telemetry-v9",
    telemetrySchema = 9,
    skillBandSize = 5,
    minDifficultyBandPlannerSamples = 4,
    minDifficultyPlannerSamples = 6,
    minBandPlannerSamples = 4,
    minPlannerSamples = 8,
    mediumSamples = 12,
    highSamples = 24,
    maxDifficultyBandPlannerWeight = 0.55,
    maxDifficultyPlannerWeight = 0.50,
    maxBandPlannerWeight = 0.55,
    maxPlannerWeight = 0.65,
    -- Account-wide priors are intentionally harder to activate and carry less
    -- weight than character-local evidence.  They exist to prevent a new alt
    -- from relearning an already-observed Forever curve from zero, not to
    -- override fresh local behavior.
    minAccountDifficultyBandPlannerSamples = 8,
    minAccountDifficultyPlannerSamples = 12,
    minAccountBandPlannerSamples = 8,
    minAccountPlannerSamples = 16,
    maxAccountDifficultyBandPlannerWeight = 0.30,
    maxAccountDifficultyPlannerWeight = 0.25,
    maxAccountBandPlannerWeight = 0.30,
    maxAccountPlannerWeight = 0.35,
    minAccountTransitionSideSamples = 6,
    -- Data from an older/unknown build is intentionally weaker than even the
    -- normal account prior. Difficulty-specific learning and transition
    -- projection are disabled for these historical profiles because a Forever
    -- build can change recipe colors independently from aggregate skill-up rate.
    minHistoricalBandPlannerSamples = 12,
    minHistoricalPlannerSamples = 24,
    maxHistoricalBandPlannerWeight = 0.18,
    maxHistoricalPlannerWeight = 0.20,
    minHistoricalAccountBandPlannerSamples = 16,
    minHistoricalAccountPlannerSamples = 32,
    maxHistoricalAccountBandPlannerWeight = 0.10,
    maxHistoricalAccountPlannerWeight = 0.12,
    -- Cross-build revalidation is deliberately narrower than a normal local
    -- profile. A prior build can help only after fresh current-build samples
    -- independently agree with it. Skill-up rate is the only planner-transferable
    -- property in alpha50; material signatures are diagnostic and difficulty is
    -- always non-transferable across builds.
    minBuildRevalidationCurrentSamples = 6,
    minBuildRevalidationPriorSamples = 12,
    maxBuildRevalidationRateDelta = 0.10,
    maxBuildRevalidationPlannerWeight = 0.25,
    minBuildRevalidationBandCurrentSamples = 3,
    minBuildRevalidationBandPriorSamples = 8,
    maxBuildRevalidationBandRateDelta = 0.15,
    maxBuildRevalidationBandPlannerWeight = 0.28,
    minBuildRevalidationMaterialCurrentUnits = 4,
    minBuildRevalidationMaterialPriorUnits = 8,
    maxBuildRevalidationMaterialDelta = 0.01,
    -- Cross-character prior-build consensus is an even more conservative
    -- fallback. At least two *other* characters must independently agree before
    -- their prior-build skill-rate can help the current character. Same-build
    -- account evidence remains preferred whenever it is available.
    minAccountBuildConsensusCharacters = 2,
    minAccountBuildConsensusCurrentSamples = 6,
    minAccountBuildConsensusPriorSamples = 24,
    maxAccountBuildConsensusRateSpread = 0.10,
    maxAccountBuildConsensusRateDelta = 0.10,
    maxAccountBuildConsensusPlannerWeight = 0.20,
    minAccountBuildConsensusBandCurrentSamples = 3,
    minAccountBuildConsensusBandPriorSamples = 16,
    maxAccountBuildConsensusBandRateSpread = 0.15,
    maxAccountBuildConsensusBandRateDelta = 0.15,
    maxAccountBuildConsensusBandPlannerWeight = 0.22,
    -- Material consensus never becomes Planner authority. It requires exact,
    -- independently reconciled material units from at least two other
    -- characters and fresh exact units on the current build. Contributor
    -- signatures must agree with each other before the current build can be
    -- classified as compatible.
    minAccountBuildConsensusMaterialCharacters = 2,
    minAccountBuildConsensusMaterialCurrentUnits = 4,
    minAccountBuildConsensusMaterialPriorUnits = 8,
    maxAccountBuildConsensusMaterialRateSpread = 0.01,
    maxAccountBuildConsensusMaterialRateDelta = 0.01,
    minTransitionSideSamples = 3,
    maxTransitionGap = 5,
    initialized = false,
    subscribed = false,
}

local function currentBuildProvenance()
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    if buildInfo and buildInfo.GetProvenance then
        local provenance = buildInfo:GetProvenance({allowTargetFallback=false})
        if provenance then return provenance end
    end
    -- An unavailable API is evidence UNKNOWN, never historical target evidence.
    return {game="Forever",build=nil,interface=nil,token="forever:unknown|interface:unknown",
        source="unknown",quality="UNKNOWN",addonVersion=JLP.version}
end
local function buildToken(provenance)
    if type(provenance) ~= "table" then return nil end
    -- A token containing only an interface (or the synthetic unknown build)
    -- cannot identify a current client. This applies to BOTH newly observed
    -- telemetry and persisted legacy transactions. Their unscoped aggregates
    -- remain available as historical fallback, never as current-build proof.
    local build = tonumber(provenance.build)
    if type(build) ~= "number" or build ~= build or build <= 0 or
       build == math.huge or build ~= math.floor(build) or
       build > 9007199254740991 or provenance.quality == "UNKNOWN" or
       provenance.quality == "TARGET_FALLBACK" or
       provenance.source == "target-constant" then return nil end
    -- Provenance must come from a real client capture. Unqualified or forged
    -- target-only tokens may never be used for a current-build planner prior.
    -- Older SavedVariables may contain only a descriptive source label. Such
    -- labels are not independent proof of a verified live GetBuildInfo read.
    -- Without quality=LIVE the profile remains historical, not current-build.
    if provenance.quality ~= "LIVE" or
       (provenance.source ~= "live-client" and
        provenance.source ~= "live-client-with-historical-source") then return nil end
    local interface = tonumber(provenance.interface)
    if provenance.interface ~= nil and (not interface or interface ~= interface or
       interface <= 0 or interface == math.huge or
       interface ~= math.floor(interface) or interface > 9007199254740991) then
        return nil
    end
    if provenance.token and provenance.token ~= "" then
        local expected = string.format("forever:%s|interface:%s", tostring(build), tostring(interface or "unknown"))
        if tostring(provenance.token) ~= expected then return nil end
        return expected
    end
    return string.format("forever:%s|interface:%s", tostring(build), tostring(interface or "unknown"))
end

local function currentBuildToken()
    return buildToken(currentBuildProvenance())
end

local function epochNow()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function characterKey()
    local identity = JLP:GetModule("CharacterIdentity")
    if identity and identity.GetKey then return identity:GetKey() end
    return "UnknownRealm:UnknownCharacter"
end

local function normalizeText(value)
    value = string.lower(tostring(value or ""))
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("%s+", " ")
    return value
end

local function recipeToken(key, recipeID, recipeName)
    local name = normalizeText(recipeName)
    if name ~= "" then return tostring(key or "UNKNOWN") .. "|name:" .. name end
    if tonumber(recipeID) then return tostring(key or "UNKNOWN") .. "|id:" .. tostring(math.floor(tonumber(recipeID))) end
    return tostring(key or "UNKNOWN") .. "|unknown"
end

local function bandStartForSkill(skill)
    skill = tonumber(skill)
    if not skill then return nil end
    skill = math.max(0, math.floor(skill))
    local size = math.max(1, tonumber(RecipeTelemetry.skillBandSize) or 5)
    return math.floor(skill / size) * size
end

local function bandToken(startSkill)
    startSkill = tonumber(startSkill)
    if not startSkill then return nil end
    return tostring(math.floor(startSkill))
end

local function bandLabel(startSkill)
    startSkill = math.floor(tonumber(startSkill) or 0)
    return tostring(startSkill) .. "-" .. tostring(startSkill + RecipeTelemetry.skillBandSize - 1)
end

local function blankAggregate(extra)
    local row = {
        confirmedCrafts = 0,
        skillObservedCrafts = 0,
        skillUps = 0,
        noSkillUps = 0,
        totalSkillGain = 0,
        recoveredCrafts = 0,
        materials = {},
        transactions = {},
        transactionCount = 0,
        updatedAt = nil,
    }
    for k, v in pairs(extra or {}) do row[k] = v end
    return row
end

local function getTelemetryRoot()
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    JLP.DB.account.recipeTelemetry = JLP.DB.account.recipeTelemetry or { characters = {} }
    JLP.DB.account.recipeTelemetry.characters = JLP.DB.account.recipeTelemetry.characters or {}
    return JLP.DB.account.recipeTelemetry
end

local function getStore()
    local root = getTelemetryRoot()
    if not root then return nil end
    local key = characterKey()
    local store = root.characters[key]
    if type(store) ~= "table" then
        store = { schema=RecipeTelemetry.telemetrySchema, recipes={}, buildProfiles={}, unitContributions={}, updatedAt=nil }
        root.characters[key] = store
    end
    -- Pre-v7 aggregates remain valid as historical fallback. Build-scoped
    -- profiles are populated only by transactions with explicit provenance; we
    -- never invent a build identity for older aggregate evidence.
    store.schema = RecipeTelemetry.telemetrySchema
    store.recipes = type(store.recipes) == "table" and store.recipes or {}
    store.buildProfiles = type(store.buildProfiles) == "table" and store.buildProfiles or {}
    store.unitContributions = type(store.unitContributions) == "table" and store.unitContributions or {}
    return store, key
end

local function ensureBuildProfile(store, provenance)
    local token = buildToken(provenance)
    if type(store) ~= "table" or not token then return nil end
    store.buildProfiles = type(store.buildProfiles) == "table" and store.buildProfiles or {}
    local profile = store.buildProfiles[token]
    if type(profile) ~= "table" then
        profile = {
            token = token,
            game = provenance and provenance.game or "Forever",
            build = provenance and tonumber(provenance.build) or nil,
            interface = provenance and tonumber(provenance.interface) or nil,
            clientVersion = provenance and provenance.clientVersion or nil,
            source = provenance and provenance.source or nil,
            quality = "LIVE", -- admission is gated by buildToken(provenance)
            targetBuild = provenance and tonumber(provenance.targetBuild) or nil,
            targetInterface = provenance and tonumber(provenance.targetInterface) or nil,
            firstAddonVersion = provenance and provenance.addonVersion or JLP.version,
            lastAddonVersion = provenance and provenance.addonVersion or JLP.version,
            recipes = {},
            updatedAt = nil,
        }
        store.buildProfiles[token] = profile
    end
    profile.recipes = type(profile.recipes) == "table" and profile.recipes or {}
    profile.game = profile.game or (provenance and provenance.game) or "Forever"
    profile.build = profile.build or (provenance and tonumber(provenance.build))
    profile.interface = profile.interface or (provenance and tonumber(provenance.interface))
    profile.clientVersion = profile.clientVersion or (provenance and provenance.clientVersion)
    profile.source = profile.source or (provenance and provenance.source)
    -- A fresh verified transaction may upgrade an old token-matching profile,
    -- but a legacy descriptive label cannot independently do so.
    profile.quality = "LIVE"
    profile.targetBuild = profile.targetBuild or (provenance and tonumber(provenance.targetBuild))
    profile.targetInterface = profile.targetInterface or (provenance and tonumber(provenance.targetInterface))
    profile.lastAddonVersion = provenance and provenance.addonVersion or profile.lastAddonVersion or JLP.version
    return profile
end

local function ensureRecipe(store, key, recipeID, recipeName)
    local token = recipeToken(key, recipeID, recipeName)
    local record = store.recipes[token]
    if type(record) ~= "table" then
        record = blankAggregate({
            token = token,
            key = key,
            recipeID = tonumber(recipeID),
            recipeName = recipeName,
            skillBands = {},
            difficulties = {},
            difficultyTimeline = {},
        })
        store.recipes[token] = record
    end
    record.materials = type(record.materials) == "table" and record.materials or {}
    record.transactions = type(record.transactions) == "table" and record.transactions or {}
    record.skillBands = type(record.skillBands) == "table" and record.skillBands or {}
    record.difficulties = type(record.difficulties) == "table" and record.difficulties or {}
    record.difficultyTimeline = type(record.difficultyTimeline) == "table" and record.difficultyTimeline or {}
    record.key = record.key or key
    record.recipeID = record.recipeID or tonumber(recipeID)
    record.recipeName = record.recipeName or recipeName
    return record, token
end

local function ensureBand(record, startSkill)
    local token = bandToken(startSkill)
    if not token then return nil end
    record.skillBands = type(record.skillBands) == "table" and record.skillBands or {}
    local band = record.skillBands[token]
    if type(band) ~= "table" then
        band = blankAggregate({
            token = token,
            bandStart = math.floor(tonumber(startSkill) or 0),
            bandEnd = math.floor(tonumber(startSkill) or 0) + RecipeTelemetry.skillBandSize - 1,
        })
        record.skillBands[token] = band
    end
    band.materials = type(band.materials) == "table" and band.materials or {}
    band.transactions = type(band.transactions) == "table" and band.transactions or {}
    band.difficulties = type(band.difficulties) == "table" and band.difficulties or {}
    band.bandStart = tonumber(band.bandStart) or math.floor(tonumber(startSkill) or 0)
    band.bandEnd = tonumber(band.bandEnd) or (band.bandStart + RecipeTelemetry.skillBandSize - 1)
    return band
end

local DIFFICULTY_LABELS = { orange="Orange", yellow="Yellow", green="Green", gray="Gray" }

local function normalizeDifficultyToken(value)
    value = string.lower(tostring(value or ""))
    if value == "orange" or value == "yellow" or value == "green" or value == "gray" then return value end
    return nil
end

local function ensureDifficulty(target, token)
    token = normalizeDifficultyToken(token)
    if type(target) ~= "table" or not token then return nil end
    target.difficulties = type(target.difficulties) == "table" and target.difficulties or {}
    local row = target.difficulties[token]
    if type(row) ~= "table" then
        row = blankAggregate({ token=token, label=DIFFICULTY_LABELS[token] or token })
        target.difficulties[token] = row
    end
    row.materials = type(row.materials) == "table" and row.materials or {}
    row.transactions = type(row.transactions) == "table" and row.transactions or {}
    row.token = token
    row.label = row.label or DIFFICULTY_LABELS[token] or token
    return row
end

local function clampCounter(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    return value
end

local function materialContribution(material)
    if type(material) ~= "table" or not tonumber(material.itemID) then return nil end
    local confidence = tostring(material.confidence or "unverified")
    local exact = confidence == "aggregate-exact" or confidence == "observed" or confidence == "unit-observed"
    return {
        itemID = math.floor(tonumber(material.itemID)),
        name = material.name,
        expected = math.max(0, tonumber(material.expected) or 0),
        consumed = math.max(0, tonumber(material.consumed) or 0),
        reconciled = 1,
        exact = exact and 1 or 0,
        confidence = confidence,
    }
end

local function inferSkillBefore(tx, unit)
    local skill = unit and unit.reconciliation and unit.reconciliation.skill or nil
    if skill and tonumber(skill.before) then return tonumber(skill.before) end
    local startSkill = tonumber(tx and tx.reconciliation and tx.reconciliation.startedSkill) or tonumber(tx and tx.startedSkill)
    local index = tonumber(unit and unit.index)
    if not startSkill or not index then return nil end
    local cursor = startSkill
    for prior = 1, math.max(0, index - 1) do
        local previous = tx.units and tx.units[prior] or nil
        local previousSkill = previous and previous.reconciliation and previous.reconciliation.skill or nil
        if previousSkill then
            if tonumber(previousSkill.after) then
                cursor = tonumber(previousSkill.after)
            else
                cursor = cursor + math.max(0, tonumber(previousSkill.gain) or 0)
            end
        end
    end
    return cursor
end

local function unitContribution(tx, unit)
    if type(tx) ~= "table" or type(unit) ~= "table" or unit.state ~= "confirmed" then return nil end
    local skill = unit.reconciliation and unit.reconciliation.skill or nil
    local skillKnown = type(skill) == "table" and (skill.status == "skill-up" or skill.status == "no-skill-up" or tonumber(skill.gain) ~= nil)
    local gain = skillKnown and math.max(0, tonumber(skill.gain) or 0) or 0
    local skillBefore = skillKnown and inferSkillBefore(tx, unit) or nil
    local skillAfter = skillKnown and (tonumber(skill and skill.after) or (skillBefore and (skillBefore + gain) or nil)) or nil
    local skillBandStart = skillKnown and bandStartForSkill(skillBefore) or nil
    local difficulty = unit.reconciliation and unit.reconciliation.difficulty or nil
    local difficultyToken = type(difficulty) == "table" and difficulty.confidence == "verified" and normalizeDifficultyToken(difficulty.token) or nil
    local materials = {}
    local materialKeys = {}
    for k in pairs(unit.reconciliation and unit.reconciliation.materials or {}) do materialKeys[#materialKeys+1] = tostring(k) end
    table.sort(materialKeys)
    for _, materialKey in ipairs(materialKeys) do
        local value = unit.reconciliation.materials[materialKey]
        local row = materialContribution(value)
        if row then materials[tostring(row.itemID)] = row end
    end
    local provenance = type(tx.buildProvenance) == "table" and tx.buildProvenance or nil
    local provenanceToken = buildToken(provenance)
    local parts = {
        "telemetry-schema:7",
        tostring(tx.id), tostring(unit.id), tostring(tx.key), tostring(tx.recipeID or ""), tostring(tx.recipeName or ""),
        skillKnown and "skill:1" or "skill:0", "gain:" .. tostring(gain),
        "skill-before:" .. tostring(skillBefore or ""), "skill-after:" .. tostring(skillAfter or ""),
        "band:" .. tostring(skillBandStart or ""),
        "difficulty:" .. tostring(difficultyToken or ""),
        "difficulty-source:" .. tostring(difficulty and difficulty.source or ""),
        "build:" .. tostring(provenanceToken or "legacy-unknown"),
        unit.reconciliation and unit.reconciliation.recovered and "recovered:1" or "recovered:0",
    }
    for _, materialKey in ipairs(materialKeys) do
        local row = materials[materialKey]
        if row then
            parts[#parts+1] = table.concat({"mat",materialKey,tostring(row.expected),tostring(row.consumed),tostring(row.confidence)},":")
        end
    end
    return {
        unitID = tostring(unit.id or (tostring(tx.id) .. "#" .. tostring(unit.index or 1))),
        transactionID = tostring(tx.id),
        key = tx.key or (tx.kind == "enchant" and "ENCHANTING" or nil),
        recipeID = tonumber(tx.recipeID),
        recipeName = tx.recipeName,
        confirmed = 1,
        skillKnown = skillKnown and 1 or 0,
        skillUps = skillKnown and gain > 0 and 1 or 0,
        noSkillUps = skillKnown and gain <= 0 and 1 or 0,
        skillGain = gain,
        skillBefore = skillBefore,
        skillAfter = skillAfter,
        skillBandStart = skillBandStart,
        skillConfidence = skill and skill.confidence or nil,
        difficultyToken = difficultyToken,
        difficultyLabel = difficultyToken and (difficulty.label or DIFFICULTY_LABELS[difficultyToken]) or nil,
        difficultySource = difficultyToken and difficulty.source or nil,
        difficultyConfidence = difficultyToken and difficulty.confidence or nil,
        buildToken = provenanceToken,
        buildProvenance = provenance and {
            game = provenance.game,
            build = tonumber(provenance.build),
            interface = tonumber(provenance.interface),
            token = provenanceToken,
            clientVersion = provenance.clientVersion,
            source = provenance.source,
            quality = provenance.quality,
            targetBuild = tonumber(provenance.targetBuild),
            targetInterface = tonumber(provenance.targetInterface),
            addonVersion = provenance.addonVersion,
        } or nil,
        recovered = unit.reconciliation and unit.reconciliation.recovered and 1 or 0,
        materials = materials,
        signature = table.concat(parts, "|"),
    }
end

local function applyAggregate(target, contribution, sign)
    if type(target) ~= "table" or type(contribution) ~= "table" then return end
    sign = sign or 1
    target.confirmedCrafts = clampCounter((target.confirmedCrafts or 0) + sign * (contribution.confirmed or 0))
    target.skillObservedCrafts = clampCounter((target.skillObservedCrafts or 0) + sign * (contribution.skillKnown or 0))
    target.skillUps = clampCounter((target.skillUps or 0) + sign * (contribution.skillUps or 0))
    target.noSkillUps = clampCounter((target.noSkillUps or 0) + sign * (contribution.noSkillUps or 0))
    target.totalSkillGain = clampCounter((target.totalSkillGain or 0) + sign * (contribution.skillGain or 0))
    target.recoveredCrafts = clampCounter((target.recoveredCrafts or 0) + sign * (contribution.recovered or 0))
    target.materials = type(target.materials) == "table" and target.materials or {}
    for materialKey, material in pairs(contribution.materials or {}) do
        local row = target.materials[materialKey]
        if type(row) ~= "table" then
            row = { itemID=material.itemID, name=material.name, reconciledUnits=0, exactUnits=0, expectedTotal=0, consumedTotal=0 }
            target.materials[materialKey] = row
        end
        row.name = row.name or material.name
        row.reconciledUnits = clampCounter((row.reconciledUnits or 0) + sign * (material.reconciled or 0))
        row.exactUnits = clampCounter((row.exactUnits or 0) + sign * (material.exact or 0))
        row.expectedTotal = clampCounter((row.expectedTotal or 0) + sign * (material.expected or 0))
        row.consumedTotal = clampCounter((row.consumedTotal or 0) + sign * (material.consumed or 0))
        if row.reconciledUnits <= 0 and row.expectedTotal <= 0 and row.consumedTotal <= 0 then target.materials[materialKey] = nil end
    end
    target.transactions = type(target.transactions) == "table" and target.transactions or {}
    if sign > 0 and contribution.transactionID and not target.transactions[contribution.transactionID] then
        target.transactions[contribution.transactionID] = true
        target.transactionCount = (tonumber(target.transactionCount) or 0) + 1
    end
    target.updatedAt = epochNow()
end

local DIFFICULTY_RANK = { orange=1, yellow=2, green=3, gray=4 }
local DIFFICULTY_ORDER = { "orange", "yellow", "green", "gray" }

local function applyDifficultyTimeline(record, contribution, sign)
    if type(record) ~= "table" or type(contribution) ~= "table" then return end
    if contribution.skillKnown ~= 1 or not tonumber(contribution.skillBefore) then return end
    local token = normalizeDifficultyToken(contribution.difficultyToken)
    if not token then return end
    sign = sign or 1
    local skill = math.max(0, math.floor(tonumber(contribution.skillBefore) or 0))
    local key = tostring(skill)
    record.difficultyTimeline = type(record.difficultyTimeline) == "table" and record.difficultyTimeline or {}
    local row = record.difficultyTimeline[key]
    if type(row) ~= "table" then
        row = { skill=skill, counts={}, total=0 }
        record.difficultyTimeline[key] = row
    end
    row.counts = type(row.counts) == "table" and row.counts or {}
    row.counts[token] = clampCounter((row.counts[token] or 0) + sign)
    if row.counts[token] <= 0 then row.counts[token] = nil end
    local total = 0
    for _, count in pairs(row.counts) do total = total + math.max(0, tonumber(count) or 0) end
    row.total = total
    if total <= 0 then record.difficultyTimeline[key] = nil end
end

local function enrichDifficultyTimeline(record)
    local entries = {}
    for key, raw in pairs(type(record) == "table" and record.difficultyTimeline or {}) do
        local skill = tonumber(raw.skill) or tonumber(key)
        if skill then
            local counts, tokens, total = {}, {}, 0
            for _, token in ipairs(DIFFICULTY_ORDER) do
                local count = math.max(0, tonumber(raw.counts and raw.counts[token]) or 0)
                if count > 0 then
                    counts[token] = count
                    tokens[#tokens+1] = token
                    total = total + count
                end
            end
            if total > 0 then
                entries[#entries+1] = {
                    skill = math.floor(skill),
                    counts = counts,
                    total = total,
                    verifiedToken = #tokens == 1 and tokens[1] or nil,
                    conflict = #tokens > 1,
                }
            end
        end
    end
    table.sort(entries, function(a,b) return a.skill < b.skill end)
    return entries
end

local function sumSideSamples(entries, token, minSkill, maxSkill)
    local total = 0
    for _, row in ipairs(entries or {}) do
        if row.skill >= minSkill and row.skill <= maxSkill and row.verifiedToken == token then
            total = total + math.max(0, tonumber(row.counts and row.counts[token]) or 0)
        end
    end
    return total
end

local function buildDifficultyTransitions(record, minSideSamples)
    local entries = enrichDifficultyTimeline(record)
    minSideSamples = math.max(1, tonumber(minSideSamples) or RecipeTelemetry.minTransitionSideSamples)
    local profile = {
        entries = entries,
        transitions = {},
        byFrom = {},
        ranges = {},
        conflict = false,
        eligibleCount = 0,
        evidence = "verified-difficulty-skill-timeline",
        minSideSamples = minSideSamples,
    }
    local lastRank = nil
    for _, row in ipairs(entries) do
        if row.conflict then profile.conflict = true end
        local rank = row.verifiedToken and DIFFICULTY_RANK[row.verifiedToken] or nil
        if rank then
            if lastRank and rank < lastRank then profile.conflict = true end
            if not lastRank or rank > lastRank then lastRank = rank end
            local range = profile.ranges[row.verifiedToken]
            if not range then
                range = { token=row.verifiedToken, label=DIFFICULTY_LABELS[row.verifiedToken], minSkill=row.skill, maxSkill=row.skill, samples=0 }
                profile.ranges[row.verifiedToken] = range
            end
            range.minSkill = math.min(range.minSkill, row.skill)
            range.maxSkill = math.max(range.maxSkill, row.skill)
            range.samples = range.samples + math.max(0, tonumber(row.counts[row.verifiedToken]) or 0)
        end
    end
    for i = 1, #DIFFICULTY_ORDER - 1 do
        local fromToken, toToken = DIFFICULTY_ORDER[i], DIFFICULTY_ORDER[i+1]
        local fromRange, toRange = profile.ranges[fromToken], profile.ranges[toToken]
        if fromRange and toRange and fromRange.maxSkill < toRange.minSkill then
            local fromSkill, toSkill = fromRange.maxSkill, toRange.minSkill
            local gap = toSkill - fromSkill
            local sideWindow = math.max(1, RecipeTelemetry.skillBandSize - 1)
            local fromSamples = sumSideSamples(entries, fromToken, fromSkill - sideWindow, fromSkill)
            local toSamples = sumSideSamples(entries, toToken, toSkill, toSkill + sideWindow)
            local eligible = (not profile.conflict)
                and gap >= 1 and gap <= RecipeTelemetry.maxTransitionGap
                and fromSamples >= minSideSamples
                and toSamples >= minSideSamples
            local minimumSide = math.min(fromSamples, toSamples)
            local confidence = eligible and (minimumSide >= 8 and "high" or minimumSide >= 5 and "medium" or "low") or "learning"
            local transition = {
                fromToken = fromToken,
                fromLabel = DIFFICULTY_LABELS[fromToken],
                toToken = toToken,
                toLabel = DIFFICULTY_LABELS[toToken],
                fromSkill = fromSkill,
                toSkill = toSkill,
                boundaryMin = fromSkill + 1,
                boundaryMax = toSkill,
                gap = gap,
                fromSamples = fromSamples,
                toSamples = toSamples,
                eligible = eligible,
                confidence = confidence,
                evidence = profile.evidence,
            }
            profile.transitions[#profile.transitions+1] = transition
            profile.byFrom[fromToken] = transition
            if eligible then profile.eligibleCount = profile.eligibleCount + 1 end
        end
    end
    return profile
end

local function applyContributionToContainer(container, contribution, sign)
    if type(contribution) ~= "table" then return end
    local record = ensureRecipe(container, contribution.key, contribution.recipeID, contribution.recipeName)
    applyAggregate(record, contribution, sign)
    applyDifficultyTimeline(record, contribution, sign)
    local recipeDifficulty = contribution.difficultyToken and ensureDifficulty(record, contribution.difficultyToken) or nil
    if recipeDifficulty then applyAggregate(recipeDifficulty, contribution, sign) end
    -- Only skill-positioned units enter a skill band. Recipe-wide telemetry is
    -- intentionally retained for older history whose exact craft skill is no
    -- longer recoverable from the bounded ledger.
    if contribution.skillKnown == 1 and contribution.skillBandStart ~= nil then
        local band = ensureBand(record, contribution.skillBandStart)
        if band then
            applyAggregate(band, contribution, sign)
            local bandDifficulty = contribution.difficultyToken and ensureDifficulty(band, contribution.difficultyToken) or nil
            if bandDifficulty then applyAggregate(bandDifficulty, contribution, sign) end
        end
    end
end

local function applyContribution(store, contribution, sign)
    if type(store) ~= "table" or type(contribution) ~= "table" then return end
    applyContributionToContainer(store, contribution, sign)
    if contribution.buildToken then
        local profile = ensureBuildProfile(store, contribution.buildProvenance or { token=contribution.buildToken })
        if profile then
            applyContributionToContainer(profile, contribution, sign)
            profile.updatedAt = epochNow()
        end
    end
end

local function enrichAggregate(record, minSamples)
    if type(record) ~= "table" then return nil end
    local skillObserved = math.max(0, tonumber(record.skillObservedCrafts) or 0)
    local skillUps = math.max(0, tonumber(record.skillUps) or 0)
    local skillGain = math.max(0, tonumber(record.totalSkillGain) or 0)
    local rate = skillObserved > 0 and math.min(1, skillGain / skillObserved) or nil
    local craftsPerSkill = skillGain > 0 and (skillObserved / skillGain) or nil
    local expectedTotal, consumedTotal, materialUnits, exactUnits = 0, 0, 0, 0
    for _, material in pairs(record.materials or {}) do
        expectedTotal = expectedTotal + math.max(0, tonumber(material.expectedTotal) or 0)
        consumedTotal = consumedTotal + math.max(0, tonumber(material.consumedTotal) or 0)
        materialUnits = materialUnits + math.max(0, tonumber(material.reconciledUnits) or 0)
        exactUnits = exactUnits + math.max(0, tonumber(material.exactUnits) or 0)
    end
    local reagentRatio = expectedTotal > 0 and (consumedTotal / expectedTotal) or nil
    local threshold = tonumber(minSamples) or RecipeTelemetry.minPlannerSamples
    local confidence = skillObserved >= RecipeTelemetry.highSamples and "high" or skillObserved >= RecipeTelemetry.mediumSamples and "medium" or skillObserved >= threshold and "low" or "learning"
    return {
        confirmedCrafts = math.max(0, tonumber(record.confirmedCrafts) or 0),
        skillObservedCrafts = skillObserved,
        skillUps = skillUps,
        noSkillUps = math.max(0, tonumber(record.noSkillUps) or 0),
        totalSkillGain = skillGain,
        skillUpRate = rate,
        craftsPerSkill = craftsPerSkill,
        recoveredCrafts = math.max(0, tonumber(record.recoveredCrafts) or 0),
        transactionCount = math.max(0, tonumber(record.transactionCount) or 0),
        materialReconciliations = materialUnits,
        exactMaterialReconciliations = exactUnits,
        reagentExpectedTotal = expectedTotal,
        reagentConsumedTotal = consumedTotal,
        reagentConsumptionRatio = reagentRatio,
        plannerEligible = skillObserved >= threshold,
        confidence = confidence,
        updatedAt = record.updatedAt,
    }
end

local function enrichDifficultyMap(source, minSamples)
    local out, order = {}, {}
    for token, difficultyRecord in pairs(type(source) == "table" and source or {}) do
        local normalized = normalizeDifficultyToken(token)
        local row = enrichAggregate(difficultyRecord, minSamples)
        if normalized and row and ((row.confirmedCrafts or 0) > 0 or (row.skillObservedCrafts or 0) > 0) then
            row.token = normalized
            row.label = difficultyRecord.label or DIFFICULTY_LABELS[normalized] or normalized
            out[normalized] = row
            order[#order+1] = normalized
        end
    end
    local rank = { orange=1, yellow=2, green=3, gray=4 }
    table.sort(order, function(a,b) return (rank[a] or 99) < (rank[b] or 99) end)
    return out, order
end

local function enrich(record, policy)
    if type(record) ~= "table" then return nil end
    policy = policy or {}
    local minPlannerSamples = tonumber(policy.minPlannerSamples) or RecipeTelemetry.minPlannerSamples
    local minDifficultySamples = tonumber(policy.minDifficultyPlannerSamples) or RecipeTelemetry.minDifficultyPlannerSamples
    local minBandSamples = tonumber(policy.minBandPlannerSamples) or RecipeTelemetry.minBandPlannerSamples
    local minDifficultyBandSamples = tonumber(policy.minDifficultyBandPlannerSamples) or RecipeTelemetry.minDifficultyBandPlannerSamples
    local transitionSamples = tonumber(policy.minTransitionSideSamples) or RecipeTelemetry.minTransitionSideSamples
    local out = enrichAggregate(record, minPlannerSamples)
    out.contract = RecipeTelemetry.contract
    out.scope = policy.scope or "character"
    out.contributingCharacters = tonumber(record.contributingCharacters) or (out.scope == "character" and 1 or 0)
    out.token = record.token
    out.key = record.key
    out.recipeID = record.recipeID
    out.recipeName = record.recipeName
    out.skillBandSize = RecipeTelemetry.skillBandSize
    out.difficulties, out.difficultyOrder = enrichDifficultyMap(record.difficulties, minDifficultySamples)
    out.skillBands = {}
    out.skillBandOrder = {}
    for token, bandRecord in pairs(record.skillBands or {}) do
        local band = enrichAggregate(bandRecord, minBandSamples)
        if band and ((band.confirmedCrafts or 0) > 0 or (band.skillObservedCrafts or 0) > 0) then
            band.token = tostring(token)
            band.bandStart = tonumber(bandRecord.bandStart) or tonumber(token)
            band.bandEnd = tonumber(bandRecord.bandEnd) or ((band.bandStart or 0) + RecipeTelemetry.skillBandSize - 1)
            band.label = bandLabel(band.bandStart)
            band.difficulties, band.difficultyOrder = enrichDifficultyMap(bandRecord.difficulties, minDifficultyBandSamples)
            out.skillBands[tostring(token)] = band
            out.skillBandOrder[#out.skillBandOrder+1] = tostring(token)
        end
    end
    table.sort(out.skillBandOrder, function(a,b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    out.difficultyTransitions = buildDifficultyTransitions(record, transitionSamples)
    return out
end

local function mergeAggregateRecord(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return end
    for _, field in ipairs({"confirmedCrafts","skillObservedCrafts","skillUps","noSkillUps","totalSkillGain","recoveredCrafts","transactionCount"}) do
        target[field] = math.max(0, tonumber(target[field]) or 0) + math.max(0, tonumber(source[field]) or 0)
    end
    target.materials = type(target.materials) == "table" and target.materials or {}
    for materialKey, sourceMaterial in pairs(source.materials or {}) do
        local row = target.materials[materialKey]
        if type(row) ~= "table" then
            row = { itemID=sourceMaterial.itemID, name=sourceMaterial.name, reconciledUnits=0, exactUnits=0, expectedTotal=0, consumedTotal=0 }
            target.materials[materialKey] = row
        end
        row.name = row.name or sourceMaterial.name
        for _, field in ipairs({"reconciledUnits","exactUnits","expectedTotal","consumedTotal"}) do
            row[field] = math.max(0, tonumber(row[field]) or 0) + math.max(0, tonumber(sourceMaterial[field]) or 0)
        end
    end
    target.updatedAt = math.max(tonumber(target.updatedAt) or 0, tonumber(source.updatedAt) or 0)
end

local function mergeRawRecipe(target, source)
    mergeAggregateRecord(target, source)
    target.skillBands = type(target.skillBands) == "table" and target.skillBands or {}
    for token, sourceBand in pairs(source.skillBands or {}) do
        local band = target.skillBands[token]
        if type(band) ~= "table" then
            band = blankAggregate({token=tostring(token), bandStart=sourceBand.bandStart or tonumber(token), bandEnd=sourceBand.bandEnd, difficulties={}})
            target.skillBands[token] = band
        end
        mergeAggregateRecord(band, sourceBand)
        band.difficulties = type(band.difficulties) == "table" and band.difficulties or {}
        for difficultyToken, sourceDifficulty in pairs(sourceBand.difficulties or {}) do
            local difficulty = band.difficulties[difficultyToken]
            if type(difficulty) ~= "table" then
                difficulty = blankAggregate({token=difficultyToken,label=sourceDifficulty.label or DIFFICULTY_LABELS[difficultyToken]})
                band.difficulties[difficultyToken] = difficulty
            end
            mergeAggregateRecord(difficulty, sourceDifficulty)
        end
    end
    target.difficulties = type(target.difficulties) == "table" and target.difficulties or {}
    for difficultyToken, sourceDifficulty in pairs(source.difficulties or {}) do
        local difficulty = target.difficulties[difficultyToken]
        if type(difficulty) ~= "table" then
            difficulty = blankAggregate({token=difficultyToken,label=sourceDifficulty.label or DIFFICULTY_LABELS[difficultyToken]})
            target.difficulties[difficultyToken] = difficulty
        end
        mergeAggregateRecord(difficulty, sourceDifficulty)
    end
    target.difficultyTimeline = type(target.difficultyTimeline) == "table" and target.difficultyTimeline or {}
    for skillKey, sourceRow in pairs(source.difficultyTimeline or {}) do
        local row = target.difficultyTimeline[skillKey]
        if type(row) ~= "table" then row = {skill=sourceRow.skill or tonumber(skillKey),counts={},total=0}; target.difficultyTimeline[skillKey] = row end
        row.counts = type(row.counts) == "table" and row.counts or {}
        for difficultyToken, count in pairs(sourceRow.counts or {}) do
            row.counts[difficultyToken] = math.max(0, tonumber(row.counts[difficultyToken]) or 0) + math.max(0, tonumber(count) or 0)
        end
        local total = 0
        for _, count in pairs(row.counts) do total = total + math.max(0, tonumber(count) or 0) end
        row.total = total
    end
end

local ACCOUNT_POLICY = {
    scope = "account-prior",
    minPlannerSamples = RecipeTelemetry.minAccountPlannerSamples,
    minDifficultyPlannerSamples = RecipeTelemetry.minAccountDifficultyPlannerSamples,
    minBandPlannerSamples = RecipeTelemetry.minAccountBandPlannerSamples,
    minDifficultyBandPlannerSamples = RecipeTelemetry.minAccountDifficultyBandPlannerSamples,
    minTransitionSideSamples = RecipeTelemetry.minAccountTransitionSideSamples,
}

local HISTORICAL_LOCAL_POLICY = {
    scope = "character-historical",
    minPlannerSamples = RecipeTelemetry.minHistoricalPlannerSamples,
    minDifficultyPlannerSamples = RecipeTelemetry.minHistoricalPlannerSamples,
    minBandPlannerSamples = RecipeTelemetry.minHistoricalBandPlannerSamples,
    minDifficultyBandPlannerSamples = RecipeTelemetry.minHistoricalBandPlannerSamples,
    minTransitionSideSamples = math.max(RecipeTelemetry.minHistoricalPlannerSamples, RecipeTelemetry.minTransitionSideSamples),
}

local HISTORICAL_ACCOUNT_POLICY = {
    scope = "account-historical-prior",
    minPlannerSamples = RecipeTelemetry.minHistoricalAccountPlannerSamples,
    minDifficultyPlannerSamples = RecipeTelemetry.minHistoricalAccountPlannerSamples,
    minBandPlannerSamples = RecipeTelemetry.minHistoricalAccountBandPlannerSamples,
    minDifficultyBandPlannerSamples = RecipeTelemetry.minHistoricalAccountBandPlannerSamples,
    minTransitionSideSamples = math.max(RecipeTelemetry.minHistoricalAccountPlannerSamples, RecipeTelemetry.minAccountTransitionSideSamples),
}

local function rawRecipeFrom(container, key, recipeID, recipeName)
    if type(container) ~= "table" or type(container.recipes) ~= "table" then return nil end
    local token = recipeToken(key, recipeID, recipeName)
    local record = container.recipes[token]
    if not record and recipeName and recipeName ~= "" then record = container.recipes[recipeToken(key, nil, recipeName)] end
    return record
end

local function hasAggregateEvidence(record)
    return type(record) == "table" and ((tonumber(record.confirmedCrafts) or 0) > 0 or (tonumber(record.skillObservedCrafts) or 0) > 0)
end

local function markBuildScope(out, scope, provenance, historical)
    if not out then return nil end
    out.buildScope = scope
    out.buildProvenance = provenance
    out.buildToken = buildToken(provenance)
    out.currentBuildToken = currentBuildToken()
    out.historicalBuild = historical and true or false
    return out
end

local function rawSkillRate(record)
    if type(record) ~= "table" then return 0, nil end
    local samples = math.max(0, tonumber(record.skillObservedCrafts) or 0)
    if samples <= 0 then return 0, nil end
    local gain = math.max(0, tonumber(record.totalSkillGain) or 0)
    return samples, math.max(0, math.min(1, gain / samples))
end

local function revalidatedRate(currentRecord, priorRecord, currentMinimum, priorMinimum, maxDelta)
    local currentSamples, currentRate = rawSkillRate(currentRecord)
    local priorSamples, priorRate = rawSkillRate(priorRecord)
    local delta = currentRate and priorRate and math.abs(currentRate - priorRate) or nil
    local enough = currentSamples >= currentMinimum and priorSamples >= priorMinimum
    local eligible = enough and delta ~= nil and delta <= maxDelta
    local priorContribution = eligible and math.min(priorSamples, currentSamples * 2) or 0
    local effectiveSamples = currentSamples + priorContribution
    local combinedRate
    if eligible and effectiveSamples > 0 then
        combinedRate = ((currentRate * currentSamples) + (priorRate * priorContribution)) / effectiveSamples
    end
    return {
        status = eligible and "compatible" or (enough and delta ~= nil and "changed" or "learning"),
        eligible = eligible,
        currentSamples = currentSamples,
        priorSamples = priorSamples,
        currentRate = currentRate,
        priorRate = priorRate,
        rateDelta = delta,
        revalidatedSkillUpRate = combinedRate,
        priorContributionSamples = priorContribution,
        effectiveSamples = effectiveSamples,
        currentMinimum = currentMinimum,
        priorMinimum = priorMinimum,
        maxRateDelta = maxDelta,
        transferable = eligible,
        property = "skill-up-rate",
    }
end

local function buildMaterialSignature(record, minimumUnits)
    if type(record) ~= "table" or type(record.materials) ~= "table" then return nil, "no-material-data" end
    local signature, count = {}, 0
    for key, material in pairs(record.materials) do
        local reconciled = math.max(0, tonumber(material.reconciledUnits) or 0)
        local exact = math.max(0, tonumber(material.exactUnits) or 0)
        local expected = math.max(0, tonumber(material.expectedTotal) or 0)
        local consumed = math.max(0, tonumber(material.consumedTotal) or 0)
        if reconciled < minimumUnits or exact < minimumUnits or exact < reconciled then return nil, "insufficient-exact-material-data" end
        local itemKey = tostring(material.itemID or key)
        signature[itemKey] = {
            itemID = tonumber(material.itemID) or tonumber(key),
            name = material.name,
            units = reconciled,
            exactUnits = exact,
            expectedPerCraft = reconciled > 0 and expected / reconciled or nil,
            consumedPerCraft = reconciled > 0 and consumed / reconciled or nil,
        }
        count = count + 1
    end
    if count <= 0 then return nil, "no-material-data" end
    return signature
end

local function compareMaterialSignatures(currentRecord, priorRecord)
    local currentSignature, currentReason = buildMaterialSignature(currentRecord, RecipeTelemetry.minBuildRevalidationMaterialCurrentUnits)
    local priorSignature, priorReason = buildMaterialSignature(priorRecord, RecipeTelemetry.minBuildRevalidationMaterialPriorUnits)
    local out = {
        status = "learning",
        compatible = false,
        transferable = false,
        plannerEligible = false,
        diagnosticOnly = true,
        property = "material-consumption",
        reason = currentReason or priorReason,
    }
    if not currentSignature or not priorSignature then return out end
    local currentCount, priorCount = 0, 0
    for _ in pairs(currentSignature) do currentCount = currentCount + 1 end
    for _ in pairs(priorSignature) do priorCount = priorCount + 1 end
    if currentCount ~= priorCount then out.status="changed"; out.reason="material-set-changed"; return out end
    local maxDelta = 0
    for itemKey, current in pairs(currentSignature) do
        local prior = priorSignature[itemKey]
        if not prior then out.status="changed"; out.reason="material-set-changed"; return out end
        local expectedDelta = math.abs((current.expectedPerCraft or 0) - (prior.expectedPerCraft or 0))
        local consumedDelta = math.abs((current.consumedPerCraft or 0) - (prior.consumedPerCraft or 0))
        maxDelta = math.max(maxDelta, expectedDelta, consumedDelta)
        if expectedDelta > RecipeTelemetry.maxBuildRevalidationMaterialDelta or consumedDelta > RecipeTelemetry.maxBuildRevalidationMaterialDelta then
            out.status="changed"; out.reason="material-rate-changed"; out.maxPerCraftDelta=maxDelta; return out
        end
    end
    out.status = "compatible"
    out.compatible = true
    out.reason = "exact-per-craft-signature-match"
    out.maxPerCraftDelta = maxDelta
    out.currentSignature = currentSignature
    out.priorSignature = priorSignature
    return out
end


local function materialSignatureCount(signature)
    local count = 0
    for _ in pairs(signature or {}) do count = count + 1 end
    return count
end

local function sameMaterialSet(left, right)
    if materialSignatureCount(left) ~= materialSignatureCount(right) then return false end
    for key in pairs(left or {}) do
        if not right or not right[key] then return false end
    end
    return true
end

local function accountMaterialConsensus(currentRecord, contributors)
    local out = {
        status = "learning",
        compatible = false,
        transferable = false,
        plannerEligible = false,
        diagnosticOnly = true,
        property = "material-consumption",
        currentMinimumUnits = RecipeTelemetry.minAccountBuildConsensusMaterialCurrentUnits,
        priorMinimumUnits = RecipeTelemetry.minAccountBuildConsensusMaterialPriorUnits,
        minimumCharacters = RecipeTelemetry.minAccountBuildConsensusMaterialCharacters,
        maxRateSpread = RecipeTelemetry.maxAccountBuildConsensusMaterialRateSpread,
        maxRateDelta = RecipeTelemetry.maxAccountBuildConsensusMaterialRateDelta,
        evidence = "fresh-current-build-material-signature-vs-multi-character-prior-build-consensus",
    }

    local currentSignature, currentReason = buildMaterialSignature(currentRecord, RecipeTelemetry.minAccountBuildConsensusMaterialCurrentUnits)
    if not currentSignature then
        out.reason = currentReason or "insufficient-current-material-data"
        return out
    end

    local valid = {}
    local builds, tokens, characters = {}, {}, {}
    for _, contributor in ipairs(contributors or {}) do
        local signature = buildMaterialSignature(contributor.record, RecipeTelemetry.minAccountBuildConsensusMaterialPriorUnits)
        if signature then
            valid[#valid+1] = {
                signature = signature,
                characterKey = contributor.characterKey,
                build = contributor.build,
                token = contributor.token,
            }
            if contributor.build then builds[tostring(contributor.build)] = true end
            if contributor.token then tokens[tostring(contributor.token)] = true end
            if contributor.characterKey then characters[tostring(contributor.characterKey)] = true end
        end
    end

    out.contributingCharacters = #valid
    if #valid < RecipeTelemetry.minAccountBuildConsensusMaterialCharacters then
        out.reason = "insufficient-material-contributors"
        return out
    end

    local baseline = valid[1].signature
    local aggregates = {}
    local maxContributorDelta = 0
    for _, contributor in ipairs(valid) do
        if not sameMaterialSet(baseline, contributor.signature) then
            out.status = "contributors-disagree"
            out.reason = "material-set-disagreement"
            return out
        end
        for itemKey, row in pairs(contributor.signature) do
            local baseRow = baseline[itemKey]
            local expectedDelta = math.abs((row.expectedPerCraft or 0) - (baseRow.expectedPerCraft or 0))
            local consumedDelta = math.abs((row.consumedPerCraft or 0) - (baseRow.consumedPerCraft or 0))
            maxContributorDelta = math.max(maxContributorDelta, expectedDelta, consumedDelta)
            if expectedDelta > RecipeTelemetry.maxAccountBuildConsensusMaterialRateSpread
                or consumedDelta > RecipeTelemetry.maxAccountBuildConsensusMaterialRateSpread then
                out.status = "contributors-disagree"
                out.reason = "material-rate-disagreement"
                out.maxContributorDelta = maxContributorDelta
                return out
            end
            local weight = math.max(1, tonumber(row.exactUnits) or tonumber(row.units) or 1)
            local aggregate = aggregates[itemKey]
            if not aggregate then
                aggregate = {
                    itemID = row.itemID,
                    name = row.name,
                    weight = 0,
                    expectedWeighted = 0,
                    consumedWeighted = 0,
                    exactUnits = 0,
                }
                aggregates[itemKey] = aggregate
            end
            aggregate.weight = aggregate.weight + weight
            aggregate.expectedWeighted = aggregate.expectedWeighted + ((tonumber(row.expectedPerCraft) or 0) * weight)
            aggregate.consumedWeighted = aggregate.consumedWeighted + ((tonumber(row.consumedPerCraft) or 0) * weight)
            aggregate.exactUnits = aggregate.exactUnits + math.max(0, tonumber(row.exactUnits) or 0)
        end
    end

    local consensus = {}
    for itemKey, aggregate in pairs(aggregates) do
        consensus[itemKey] = {
            itemID = aggregate.itemID,
            name = aggregate.name,
            exactUnits = aggregate.exactUnits,
            expectedPerCraft = aggregate.weight > 0 and aggregate.expectedWeighted / aggregate.weight or nil,
            consumedPerCraft = aggregate.weight > 0 and aggregate.consumedWeighted / aggregate.weight or nil,
        }
    end

    if not sameMaterialSet(currentSignature, consensus) then
        out.status = "changed"
        out.reason = "current-material-set-changed"
        out.consensusSignature = consensus
        out.currentSignature = currentSignature
        out.maxContributorDelta = maxContributorDelta
        return out
    end

    local maxCurrentDelta = 0
    for itemKey, current in pairs(currentSignature) do
        local prior = consensus[itemKey]
        local expectedDelta = math.abs((current.expectedPerCraft or 0) - (prior.expectedPerCraft or 0))
        local consumedDelta = math.abs((current.consumedPerCraft or 0) - (prior.consumedPerCraft or 0))
        maxCurrentDelta = math.max(maxCurrentDelta, expectedDelta, consumedDelta)
        if expectedDelta > RecipeTelemetry.maxAccountBuildConsensusMaterialRateDelta
            or consumedDelta > RecipeTelemetry.maxAccountBuildConsensusMaterialRateDelta then
            out.status = "changed"
            out.reason = "current-material-rate-changed"
            out.consensusSignature = consensus
            out.currentSignature = currentSignature
            out.maxContributorDelta = maxContributorDelta
            out.maxCurrentDelta = maxCurrentDelta
            return out
        end
    end

    local buildList, tokenList, characterList = {}, {}, {}
    for value in pairs(builds) do buildList[#buildList+1] = value end
    for value in pairs(tokens) do tokenList[#tokenList+1] = value end
    for value in pairs(characters) do characterList[#characterList+1] = value end
    table.sort(buildList); table.sort(tokenList); table.sort(characterList)

    out.status = "compatible"
    out.compatible = true
    out.reason = "multi-character-exact-material-consensus"
    out.currentSignature = currentSignature
    out.consensusSignature = consensus
    out.maxContributorDelta = maxContributorDelta
    out.maxCurrentDelta = maxCurrentDelta
    out.contributingBuilds = #buildList
    out.buildList = buildList
    out.buildTokens = tokenList
    out.characterKeys = characterList
    return out
end

local function previousBuildRecipe(store, key, recipeID, recipeName, currentProvenance)
    if type(store) ~= "table" or type(store.buildProfiles) ~= "table" then return nil, nil end
    local currentToken = buildToken(currentProvenance)
    local currentBuild = currentProvenance and tonumber(currentProvenance.build) or nil
    local bestProfile, bestRecord, bestBuild
    for token, profile in pairs(store.buildProfiles) do
        if tostring(token) ~= tostring(currentToken) and type(profile) == "table" then
            local profileBuild = tonumber(profile.build)
            local record = rawRecipeFrom(profile, key, recipeID, recipeName)
            if hasAggregateEvidence(record) and profileBuild and (not currentBuild or profileBuild < currentBuild) then
                if not bestBuild or profileBuild > bestBuild then
                    bestProfile, bestRecord, bestBuild = profile, record, profileBuild
                end
            end
        end
    end
    return bestProfile, bestRecord
end

local function buildCrossBuildCompatibility(store, key, recipeID, recipeName)
    local provenance = currentBuildProvenance()
    local currentToken = buildToken(provenance)
    local currentProfile = currentToken and type(store) == "table" and type(store.buildProfiles) == "table" and store.buildProfiles[currentToken] or nil
    local currentRecord = rawRecipeFrom(currentProfile, key, recipeID, recipeName)
    if not hasAggregateEvidence(currentRecord) then return nil end
    local priorProfile, priorRecord = previousBuildRecipe(store, key, recipeID, recipeName, provenance)
    if not priorProfile or not hasAggregateEvidence(priorRecord) then
        return {
            status = "no-explicit-prior-build",
            currentBuildToken = currentToken,
            currentBuild = provenance and tonumber(provenance.build) or nil,
            transferableProperty = "skill-up-rate-only",
            difficulty = {status="current-build-only",transferable=false,plannerEligible=false,reason="verified-difficulty-never-cross-build"},
            materials = {status="no-explicit-prior-build",compatible=false,transferable=false,plannerEligible=false,diagnosticOnly=true},
            bands = {},
        }
    end
    local global = revalidatedRate(currentRecord, priorRecord, RecipeTelemetry.minBuildRevalidationCurrentSamples, RecipeTelemetry.minBuildRevalidationPriorSamples, RecipeTelemetry.maxBuildRevalidationRateDelta)
    local bands = {}
    for token, currentBand in pairs(currentRecord.skillBands or {}) do
        local priorBand = priorRecord.skillBands and priorRecord.skillBands[token] or nil
        if type(priorBand) == "table" then
            bands[tostring(token)] = revalidatedRate(currentBand, priorBand, RecipeTelemetry.minBuildRevalidationBandCurrentSamples, RecipeTelemetry.minBuildRevalidationBandPriorSamples, RecipeTelemetry.maxBuildRevalidationBandRateDelta)
            bands[tostring(token)].bandStart = tonumber(currentBand.bandStart) or tonumber(token)
            bands[tostring(token)].label = bandLabel(bands[tostring(token)].bandStart)
        end
    end
    local materials = compareMaterialSignatures(currentRecord, priorRecord)
    local status = global.eligible and "compatible" or global.status
    for _, band in pairs(bands) do if band.eligible then status = "compatible" break end end
    return {
        status = status,
        currentBuildToken = currentToken,
        currentBuild = provenance and tonumber(provenance.build) or nil,
        previousBuildToken = priorProfile.token or buildToken(priorProfile),
        previousBuild = tonumber(priorProfile.build),
        previousInterface = tonumber(priorProfile.interface),
        global = global,
        bands = bands,
        materials = materials,
        difficulty = {status="current-build-only",transferable=false,plannerEligible=false,reason="verified-difficulty-never-cross-build"},
        transferableProperty = "skill-up-rate-only",
        evidence = "current-build-agreement-with-explicit-prior-build",
    }
end

local function consensusRevalidatedRate(currentRecord, contributors, currentMinimum, priorMinimum, minCharacters, maxSpread, maxDelta)
    local currentSamples, currentRate = rawSkillRate(currentRecord)
    local priorSamples, priorGain = 0, 0
    local contributorCount, minRate, maxRate = 0, nil, nil
    local builds, buildTokens, characters = {}, {}, {}
    for _, contributor in ipairs(contributors or {}) do
        local samples, rate = rawSkillRate(contributor.record)
        if samples > 0 and rate ~= nil then
            contributorCount = contributorCount + 1
            priorSamples = priorSamples + samples
            priorGain = priorGain + (rate * samples)
            minRate = minRate and math.min(minRate, rate) or rate
            maxRate = maxRate and math.max(maxRate, rate) or rate
            if contributor.build then builds[tostring(contributor.build)] = true end
            if contributor.token then buildTokens[tostring(contributor.token)] = true end
            if contributor.characterKey then characters[tostring(contributor.characterKey)] = true end
        end
    end
    local priorRate = priorSamples > 0 and (priorGain / priorSamples) or nil
    local spread = minRate and maxRate and (maxRate - minRate) or nil
    local delta = currentRate and priorRate and math.abs(currentRate - priorRate) or nil
    local enough = currentSamples >= currentMinimum
        and priorSamples >= priorMinimum
        and contributorCount >= minCharacters
    local consensus = enough and spread ~= nil and spread <= maxSpread
    local eligible = consensus and delta ~= nil and delta <= maxDelta
    local priorContribution = eligible and math.min(priorSamples, currentSamples * 2) or 0
    local effectiveSamples = currentSamples + priorContribution
    local combinedRate
    if eligible and effectiveSamples > 0 then
        combinedRate = ((currentRate * currentSamples) + (priorRate * priorContribution)) / effectiveSamples
    end
    local buildList, tokenList, characterList = {}, {}, {}
    for value in pairs(builds) do buildList[#buildList+1] = value end
    for value in pairs(buildTokens) do tokenList[#tokenList+1] = value end
    for value in pairs(characters) do characterList[#characterList+1] = value end
    table.sort(buildList); table.sort(tokenList); table.sort(characterList)
    local status
    if eligible then status = "compatible"
    elseif not enough then status = "learning"
    elseif not consensus then status = "contributors-disagree"
    else status = "changed" end
    return {
        status = status,
        eligible = eligible,
        currentSamples = currentSamples,
        priorSamples = priorSamples,
        currentRate = currentRate,
        priorRate = priorRate,
        consensusRate = priorRate,
        rateSpread = spread,
        rateDelta = delta,
        revalidatedSkillUpRate = combinedRate,
        priorContributionSamples = priorContribution,
        effectiveSamples = effectiveSamples,
        currentMinimum = currentMinimum,
        priorMinimum = priorMinimum,
        minimumCharacters = minCharacters,
        contributingCharacters = contributorCount,
        contributingBuilds = #buildList,
        buildList = buildList,
        buildTokens = tokenList,
        characterKeys = characterList,
        maxRateSpread = maxSpread,
        maxRateDelta = maxDelta,
        transferable = eligible,
        property = "skill-up-rate",
        evidence = "fresh-current-build-vs-multi-character-prior-build-consensus",
    }
end

local function buildAccountBuildConsensus(key, recipeID, recipeName)
    local store, currentCharacter = getStore()
    local root = getTelemetryRoot()
    local provenance = currentBuildProvenance()
    local token = buildToken(provenance)
    local currentProfile = store and token and store.buildProfiles and store.buildProfiles[token] or nil
    local currentRecord = rawRecipeFrom(currentProfile, key, recipeID, recipeName)
    if not hasAggregateEvidence(currentRecord) then return nil end

    local globalContributors = {}
    local bandContributors = {}
    for otherKey, otherStore in pairs(root and root.characters or {}) do
        if tostring(otherKey) ~= tostring(currentCharacter) and type(otherStore) == "table" then
            local priorProfile, priorRecord = previousBuildRecipe(otherStore, key, recipeID, recipeName, provenance)
            if priorProfile and hasAggregateEvidence(priorRecord) then
                local base = {
                    characterKey = otherKey,
                    build = tonumber(priorProfile.build),
                    token = priorProfile.token or buildToken(priorProfile),
                    record = priorRecord,
                }
                globalContributors[#globalContributors+1] = base
                for bandKey, priorBand in pairs(priorRecord.skillBands or {}) do
                    if hasAggregateEvidence(priorBand) then
                        bandContributors[tostring(bandKey)] = bandContributors[tostring(bandKey)] or {}
                        bandContributors[tostring(bandKey)][#bandContributors[tostring(bandKey)]+1] = {
                            characterKey = otherKey,
                            build = tonumber(priorProfile.build),
                            token = priorProfile.token or buildToken(priorProfile),
                            record = priorBand,
                        }
                    end
                end
            end
        end
    end

    if #globalContributors == 0 then
        return {
            status = "no-prior-account-profiles",
            currentBuildToken = token,
            currentBuild = provenance and tonumber(provenance.build) or nil,
            global = nil,
            bands = {},
            difficulty = {status="current-build-only",transferable=false,plannerEligible=false,reason="verified-difficulty-never-cross-build"},
            materials = {status="learning",compatible=false,transferable=false,plannerEligible=false,diagnosticOnly=true,reason="no-prior-account-profiles"},
            transferableProperty = "skill-up-rate-only",
        }
    end

    local global = consensusRevalidatedRate(
        currentRecord, globalContributors,
        RecipeTelemetry.minAccountBuildConsensusCurrentSamples,
        RecipeTelemetry.minAccountBuildConsensusPriorSamples,
        RecipeTelemetry.minAccountBuildConsensusCharacters,
        RecipeTelemetry.maxAccountBuildConsensusRateSpread,
        RecipeTelemetry.maxAccountBuildConsensusRateDelta
    )
    local bands = {}
    for bandKey, currentBand in pairs(currentRecord.skillBands or {}) do
        local contributors = bandContributors[tostring(bandKey)] or {}
        if #contributors > 0 then
            local out = consensusRevalidatedRate(
                currentBand, contributors,
                RecipeTelemetry.minAccountBuildConsensusBandCurrentSamples,
                RecipeTelemetry.minAccountBuildConsensusBandPriorSamples,
                RecipeTelemetry.minAccountBuildConsensusCharacters,
                RecipeTelemetry.maxAccountBuildConsensusBandRateSpread,
                RecipeTelemetry.maxAccountBuildConsensusBandRateDelta
            )
            out.bandStart = tonumber(currentBand.bandStart) or tonumber(bandKey)
            out.label = bandLabel(out.bandStart)
            bands[tostring(bandKey)] = out
        end
    end
    local materials = accountMaterialConsensus(currentRecord, globalContributors)
    local status = global and global.eligible and "compatible" or (global and global.status or "learning")
    for _, band in pairs(bands) do if band.eligible then status = "compatible" break end end
    return {
        status = status,
        currentBuildToken = token,
        currentBuild = provenance and tonumber(provenance.build) or nil,
        global = global,
        bands = bands,
        difficulty = {status="current-build-only",transferable=false,plannerEligible=false,reason="verified-difficulty-never-cross-build"},
        materials = materials,
        transferableProperty = "skill-up-rate-only",
        evidence = "multi-character-prior-build-consensus-confirmed-by-current-build",
    }
end

local function buildAccountRecipePrior(key, recipeID, recipeName)
    local root = getTelemetryRoot()
    if not root then return nil end
    local currentKey = characterKey()
    local normalizedCurrentKey = string.lower(tostring(currentKey or ""))
    -- Startup placeholders must never cause the real character's persisted store
    -- to be mistaken for "another character" during account-prior construction.
    if normalizedCurrentKey:find("unknowncharacter", 1, true) or normalizedCurrentKey:find("preloginplaceholder", 1, true) then return nil end
    local token = recipeToken(key, recipeID, recipeName)
    local currentToken = currentBuildToken()
    local currentProvenance = currentBuildProvenance()
    local aggregate, contributors = nil, 0
    -- First pass: exact current-build account evidence only. As soon as any
    -- current-build contributor exists, older/unknown build history is excluded
    -- rather than blended into the new profile.
    for otherKey, store in pairs(root.characters or {}) do
        if tostring(otherKey) ~= tostring(currentKey) and type(store) == "table" then
            local profile = currentToken and type(store.buildProfiles) == "table" and store.buildProfiles[currentToken] or nil
            local raw = rawRecipeFrom(profile, key, recipeID, recipeName)
            if hasAggregateEvidence(raw) then
                if not aggregate then
                    aggregate = blankAggregate({token=token,key=key,recipeID=tonumber(recipeID) or raw.recipeID,recipeName=recipeName or raw.recipeName,skillBands={},difficulties={},difficultyTimeline={}})
                end
                mergeRawRecipe(aggregate, raw)
                contributors = contributors + 1
            end
        end
    end
    if aggregate then
        aggregate.contributingCharacters = contributors
        local out = enrich(aggregate, ACCOUNT_POLICY)
        if out then
            out.accountPrior = true
            out.contributingCharacters = contributors
            out.scope = "account-prior"
            markBuildScope(out, "current-build-account", currentProvenance, false)
        end
        return out
    end

    -- No exact current-build evidence exists yet. Preserve older/unknown account
    -- history as a weak generic prior. It can influence only generic skill-up
    -- rates in Planner; difficulty buckets and transitions are not trusted.
    contributors = 0
    for otherKey, store in pairs(root.characters or {}) do
        if tostring(otherKey) ~= tostring(currentKey) and type(store) == "table" then
            local raw = rawRecipeFrom(store, key, recipeID, recipeName)
            if hasAggregateEvidence(raw) then
                if not aggregate then
                    aggregate = blankAggregate({token=token,key=key,recipeID=tonumber(recipeID) or raw.recipeID,recipeName=recipeName or raw.recipeName,skillBands={},difficulties={},difficultyTimeline={}})
                end
                mergeRawRecipe(aggregate, raw)
                contributors = contributors + 1
            end
        end
    end
    if not aggregate then return nil end
    aggregate.contributingCharacters = contributors
    local out = enrich(aggregate, HISTORICAL_ACCOUNT_POLICY)
    if out then
        out.accountPrior = true
        out.contributingCharacters = contributors
        out.scope = "account-historical-prior"
        markBuildScope(out, "historical-account", nil, true)
    end
    return out
end

local function boundedAdaptive(staticRemaining, adaptive)
    if staticRemaining <= 0 then return 0 end
    local lower = math.max(1, math.ceil(staticRemaining * 0.67))
    local upper = math.max(staticRemaining, math.ceil(staticRemaining * 1.50))
    return math.max(lower, math.min(upper, math.max(1, math.ceil(adaptive))))
end

local function blendedRate(staticRate, observedRate, sample, maxWeight, denominator)
    observedRate = tonumber(observedRate)
    sample = math.max(0, tonumber(sample) or 0)
    if not observedRate then return staticRate, 0 end
    observedRate = math.max(0, math.min(1, observedRate))
    local weight = math.min(maxWeight or 0.65, sample / (sample + (denominator or 18)))
    local rate = math.max(0.05, math.min(1, staticRate * (1 - weight) + observedRate * weight))
    return rate, weight
end

function RecipeTelemetry:Initialize()
    self.initialized = true
    getStore()
    if not self.subscribed and JLP.EventBus and JLP.EventBus.On then
        self.subscribed = true
        JLP.EventBus:On("TRANSACTION_LEDGER_UPDATED", function(tx)
            RecipeTelemetry:ObserveTransaction(tx)
        end)
    end
    local ledger = JLP:GetModule("TransactionLedger")
    if ledger and ledger.GetTransactions then
        for _, tx in ipairs(ledger:GetTransactions()) do self:ObserveTransaction(tx, true) end
    end
    return true
end

function RecipeTelemetry:ObserveTransaction(tx, suppressEmit)
    if type(tx) ~= "table" or not tx.id or not tx.key then return false end
    local store = getStore()
    if not store then return false end
    local changed = false
    for index = 1, math.max(0, tonumber(tx.confirmedCount) or 0) do
        local unit = tx.units and tx.units[index] or nil
        local contribution = unitContribution(tx, unit)
        if contribution then
            local previous = store.unitContributions[contribution.unitID]
            if not previous or previous.signature ~= contribution.signature then
                if previous then applyContribution(store, previous, -1) end
                applyContribution(store, contribution, 1)
                store.unitContributions[contribution.unitID] = contribution
                changed = true
            end
        end
    end
    if changed then
        store.updatedAt = epochNow()
        if not suppressEmit and JLP.EventBus and JLP.EventBus.Emit then
            JLP.EventBus:Emit("RECIPE_TELEMETRY_UPDATED", tx.key, tx.recipeName, self:GetRecipe(tx.key, tx.recipeID, tx.recipeName))
        end
    end
    return changed
end

function RecipeTelemetry:GetRecipe(key, recipeID, recipeName)
    local store = getStore()
    if not store then return nil end
    local provenance = currentBuildProvenance()
    local token = currentBuildToken()
    local profile = token and store.buildProfiles and store.buildProfiles[token] or nil
    local record = rawRecipeFrom(profile, key, recipeID, recipeName)
    if hasAggregateEvidence(record) then
        local out = markBuildScope(enrich(record), "current-build-local", provenance, false)
        if out then out.buildCompatibility = buildCrossBuildCompatibility(store, key, recipeID, recipeName) end
        return out
    end
    record = rawRecipeFrom(store, key, recipeID, recipeName)
    if not hasAggregateEvidence(record) then return nil end
    return markBuildScope(enrich(record, HISTORICAL_LOCAL_POLICY), "historical-local", nil, true)
end

function RecipeTelemetry:GetCurrentMaterialEvidence(key, recipeID, recipeName)
    local store = getStore()
    if not store then return nil end
    local provenance = currentBuildProvenance()
    local token = currentBuildToken()
    local profile = token and store.buildProfiles and store.buildProfiles[token] or nil
    local record = rawRecipeFrom(profile, key, recipeID, recipeName)
    if not hasAggregateEvidence(record) then return nil end
    local out = {
        contract = "current-build-exact-material-evidence-v1",
        key = key,
        recipeID = tonumber(recipeID) or tonumber(record.recipeID),
        recipeName = recipeName or record.recipeName,
        buildProvenance = provenance,
        confirmedCrafts = math.max(0, tonumber(record.confirmedCrafts) or 0),
        materials = {},
        materialOrder = {},
        plannerEligible = false,
        diagnosticOnly = true,
    }
    for materialKey, material in pairs(record.materials or {}) do
        local exactUnits = math.max(0, tonumber(material.exactUnits) or 0)
        local reconciledUnits = math.max(0, tonumber(material.reconciledUnits) or 0)
        local expectedTotal = math.max(0, tonumber(material.expectedTotal) or 0)
        local consumedTotal = math.max(0, tonumber(material.consumedTotal) or 0)
        local row = {
            itemID = tonumber(material.itemID) or tonumber(materialKey),
            name = material.name,
            exactUnits = exactUnits,
            reconciledUnits = reconciledUnits,
            expectedTotal = expectedTotal,
            consumedTotal = consumedTotal,
            allReconciledExact = reconciledUnits > 0 and reconciledUnits == exactUnits or false,
            expectedPerCraft = reconciledUnits > 0 and (expectedTotal / reconciledUnits) or nil,
            consumedPerCraft = reconciledUnits > 0 and (consumedTotal / reconciledUnits) or nil,
        }
        local keyToken = tostring(row.itemID or materialKey)
        out.materials[keyToken] = row
        out.materialOrder[#out.materialOrder + 1] = keyToken
    end
    table.sort(out.materialOrder, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

function RecipeTelemetry:GetAccountRecipePrior(key, recipeID, recipeName)
    return buildAccountRecipePrior(key, recipeID, recipeName)
end

function RecipeTelemetry:GetAccountBuildConsensus(key, recipeID, recipeName)
    return buildAccountBuildConsensus(key, recipeID, recipeName)
end

function RecipeTelemetry:GetDifficultyTransitions(key, recipeID, recipeName)
    local telemetry = self:GetRecipe(key, recipeID, recipeName)
    if telemetry and telemetry.historicalBuild then return nil end
    return telemetry and telemetry.difficultyTransitions or nil
end

local function predictWithProfile(profile, currentSkill, currentDifficulty, targetSkill, evidencePrefix)
    local currentToken = normalizeDifficultyToken(type(currentDifficulty) == "table" and currentDifficulty.token or currentDifficulty)
    currentSkill = tonumber(currentSkill)
    targetSkill = tonumber(targetSkill)
    if not currentToken or not currentSkill or not targetSkill or targetSkill < currentSkill then return nil end
    if targetSkill == currentSkill then
        return { token=currentToken, label=DIFFICULTY_LABELS[currentToken], projected=false, evidence="live-current-difficulty", chain={}, profile=profile }
    end
    if not profile or profile.conflict then return nil end
    local token, cursor = currentToken, currentSkill
    local chain = {}
    for _ = 1, #DIFFICULTY_ORDER do
        local range = profile.ranges and profile.ranges[token] or nil
        local transition = profile.byFrom and profile.byFrom[token] or nil
        if range and targetSkill <= (tonumber(range.maxSkill) or -1) and targetSkill >= cursor then
            return {
                token=token,
                label=DIFFICULTY_LABELS[token],
                projected=true,
                evidence="observed-difficulty-range",
                chain=chain,
                profile=profile,
            }
        end
        if not transition or not transition.eligible then return nil end
        if targetSkill <= transition.fromSkill then
            return {
                token=token,
                label=DIFFICULTY_LABELS[token],
                projected=true,
                evidence="verified-transition-stable-side",
                chain=chain,
                transition=transition,
                profile=profile,
            }
        end
        if targetSkill < transition.toSkill then return nil end
        chain[#chain+1] = transition
        token = transition.toToken
        cursor = transition.toSkill
        if targetSkill == cursor then
            return {
                token=token,
                label=DIFFICULTY_LABELS[token],
                projected=true,
                evidence="verified-difficulty-transition",
                chain=chain,
                transition=transition,
                profile=profile,
            }
        end
    end
    return nil
end

function RecipeTelemetry:PredictDifficultyForSkill(key, recipeID, recipeName, currentSkill, currentDifficulty, targetSkill)
    local telemetry = self:GetRecipe(key, recipeID, recipeName)
    if telemetry and telemetry.historicalBuild then return nil end
    return predictWithProfile(telemetry and telemetry.difficultyTransitions or nil, currentSkill, currentDifficulty, targetSkill, "character")
end

function RecipeTelemetry:PredictAccountDifficultyForSkill(key, recipeID, recipeName, currentSkill, currentDifficulty, targetSkill)
    local localProfile = self:GetDifficultyTransitions(key, recipeID, recipeName)
    -- Character-local contradictions are authoritative and intentionally block an
    -- account prior from projecting through behavior this character disputes.
    if localProfile and localProfile.conflict then return nil end
    local accountTelemetry = self:GetAccountRecipePrior(key, recipeID, recipeName)
    if accountTelemetry and accountTelemetry.historicalBuild then return nil end
    local predicted = predictWithProfile(accountTelemetry and accountTelemetry.difficultyTransitions or nil, currentSkill, currentDifficulty, targetSkill, "account")
    if predicted then
        predicted.accountPrior = true
        predicted.evidence = "account-" .. tostring(predicted.evidence or "difficulty-transition")
    end
    return predicted
end

function RecipeTelemetry:GetPlannerEstimate(key, recipeName, staticRemaining, remainingSkill, staticRate, currentSkill, targetSkill, currentDifficulty)
    staticRemaining = math.max(0, math.floor(tonumber(staticRemaining) or 0))
    remainingSkill = math.max(0, tonumber(remainingSkill) or 0)
    staticRate = tonumber(staticRate)
    if not staticRate or staticRate <= 0 then
        staticRate = staticRemaining > 0 and math.min(1, remainingSkill / staticRemaining) or 1
    end
    staticRate = math.max(0.05, math.min(1, staticRate))
    local telemetry = self:GetRecipe(key, nil, recipeName)
    local accountTelemetry = self:GetAccountRecipePrior(key, nil, recipeName)
    local buildCompatibility = telemetry and telemetry.buildCompatibility or nil
    local accountBuildConsensus = telemetry and (self:GetAccountBuildConsensus(key, nil, recipeName)) or nil
    local revalidatedGlobal = buildCompatibility and buildCompatibility.global or nil
    local revalidatedGlobalEligible = revalidatedGlobal and revalidatedGlobal.eligible and tonumber(revalidatedGlobal.revalidatedSkillUpRate) ~= nil
    local consensusGlobal = accountBuildConsensus and accountBuildConsensus.global or nil
    local consensusGlobalEligible = consensusGlobal and consensusGlobal.eligible and tonumber(consensusGlobal.revalidatedSkillUpRate) ~= nil
    local localHistorical = telemetry and telemetry.historicalBuild or false
    local accountHistorical = accountTelemetry and accountTelemetry.historicalBuild or false
    local localBandThreshold = localHistorical and self.minHistoricalBandPlannerSamples or self.minBandPlannerSamples
    local localGlobalThreshold = localHistorical and self.minHistoricalPlannerSamples or self.minPlannerSamples
    local localBandMaxWeight = localHistorical and self.maxHistoricalBandPlannerWeight or self.maxBandPlannerWeight
    local localGlobalMaxWeight = localHistorical and self.maxHistoricalPlannerWeight or self.maxPlannerWeight
    local accountBandThreshold = accountHistorical and self.minHistoricalAccountBandPlannerSamples or self.minAccountBandPlannerSamples
    local accountGlobalThreshold = accountHistorical and self.minHistoricalAccountPlannerSamples or self.minAccountPlannerSamples
    local accountBandMaxWeight = accountHistorical and self.maxHistoricalAccountBandPlannerWeight or self.maxAccountBandPlannerWeight
    local accountGlobalMaxWeight = accountHistorical and self.maxHistoricalAccountPlannerWeight or self.maxAccountPlannerWeight
    local result = {
        source = "route-static",
        sourceDetail = "route-static",
        staticRemainingCrafts = staticRemaining,
        remainingCrafts = staticRemaining,
        remainingSkill = remainingSkill,
        staticSkillUpRate = staticRate,
        telemetry = telemetry,
        accountTelemetry = accountTelemetry,
        currentDifficulty = normalizeDifficultyToken(type(currentDifficulty) == "table" and currentDifficulty.token or currentDifficulty),
        currentDifficultyLabel = type(currentDifficulty) == "table" and currentDifficulty.label or nil,
        currentDifficultyEvidence = type(currentDifficulty) == "table" and currentDifficulty.source or nil,
        plannerEligible = false,
        weight = 0,
        skillBandSize = self.skillBandSize,
        bandEstimates = {},
        difficultyTransitions = telemetry and telemetry.difficultyTransitions or nil,
        usedTransition = false,
        localBuildScope = telemetry and telemetry.buildScope or nil,
        accountBuildScope = accountTelemetry and accountTelemetry.buildScope or nil,
        currentBuildToken = currentBuildToken(),
        buildCompatibility = buildCompatibility,
        accountBuildConsensus = accountBuildConsensus,
        usedBuildRevalidation = false,
        usedAccountBuildConsensus = false,
    }
    if staticRemaining <= 0 or remainingSkill <= 0 or (not telemetry and not accountTelemetry) then return result end

    local globalSample = math.max(0, tonumber(telemetry and telemetry.skillObservedCrafts) or 0)
    local globalRate = tonumber(telemetry and telemetry.skillUpRate)
    local globalEligible = globalSample >= localGlobalThreshold and globalRate ~= nil
    local accountGlobalSample = math.max(0, tonumber(accountTelemetry and accountTelemetry.skillObservedCrafts) or 0)
    local accountGlobalRate = tonumber(accountTelemetry and accountTelemetry.skillUpRate)
    local accountGlobalEligible = accountGlobalSample >= accountGlobalThreshold and accountGlobalRate ~= nil

    currentSkill = tonumber(currentSkill)
    targetSkill = tonumber(targetSkill)
    if not currentSkill or not targetSkill or targetSkill <= currentSkill then
        if globalEligible then
            local rate, weight = blendedRate(staticRate, globalRate, globalSample, localGlobalMaxWeight, localHistorical and 36 or 18)
            result.source = localHistorical and "telemetry-historical-prior" or "telemetry-blended"
            result.sourceDetail = localHistorical and "historical-build-recipe-prior" or "recipe-global-fallback"
            result.remainingCrafts = boundedAdaptive(staticRemaining, remainingSkill / rate)
            result.plannerEligible = true
            result.weight = weight
            result.observedSkillUpRate = globalRate
            result.blendedSkillUpRate = rate
            result.confidence = telemetry and telemetry.confidence or nil
            result.usedHistoricalBuild = localHistorical
            return result
        elseif revalidatedGlobalEligible then
            local effectiveSamples = tonumber(revalidatedGlobal.effectiveSamples) or 0
            local rate, weight = blendedRate(staticRate, revalidatedGlobal.revalidatedSkillUpRate, effectiveSamples, self.maxBuildRevalidationPlannerWeight, 24)
            result.source = "telemetry-build-revalidated"
            result.sourceDetail = "cross-build-revalidated-recipe-skill-rate"
            result.remainingCrafts = boundedAdaptive(staticRemaining, remainingSkill / rate)
            result.plannerEligible = true
            result.weight = weight
            result.observedSkillUpRate = revalidatedGlobal.revalidatedSkillUpRate
            result.blendedSkillUpRate = rate
            result.confidence = "revalidated"
            result.usedBuildRevalidation = true
            result.revalidatedProperty = "skill-up-rate"
            result.revalidatedPreviousBuild = buildCompatibility and buildCompatibility.previousBuild or nil
            result.revalidatedEvidence = revalidatedGlobal
            return result
        elseif accountGlobalEligible and not accountHistorical then
            local rate, weight = blendedRate(staticRate, accountGlobalRate, accountGlobalSample, accountGlobalMaxWeight, 30)
            result.source = "telemetry-account-prior"
            result.sourceDetail = "account-recipe-prior"
            result.remainingCrafts = boundedAdaptive(staticRemaining, remainingSkill / rate)
            result.plannerEligible = true
            result.weight = weight
            result.observedSkillUpRate = accountGlobalRate
            result.blendedSkillUpRate = rate
            result.confidence = accountTelemetry and accountTelemetry.confidence or nil
            result.usedAccountPrior = true
            return result
        elseif consensusGlobalEligible then
            local effectiveSamples = tonumber(consensusGlobal.effectiveSamples) or 0
            local rate, weight = blendedRate(staticRate, consensusGlobal.revalidatedSkillUpRate, effectiveSamples, self.maxAccountBuildConsensusPlannerWeight, 32)
            result.source = "telemetry-account-build-consensus"
            result.sourceDetail = "cross-build-account-consensus-recipe-skill-rate"
            result.remainingCrafts = boundedAdaptive(staticRemaining, remainingSkill / rate)
            result.plannerEligible = true
            result.weight = weight
            result.observedSkillUpRate = consensusGlobal.revalidatedSkillUpRate
            result.blendedSkillUpRate = rate
            result.confidence = "account-build-consensus"
            result.usedAccountBuildConsensus = true
            result.accountConsensusEvidence = consensusGlobal
            return result
        elseif accountGlobalEligible then
            local rate, weight = blendedRate(staticRate, accountGlobalRate, accountGlobalSample, accountGlobalMaxWeight, 48)
            result.source = "telemetry-account-historical"
            result.sourceDetail = "historical-build-account-recipe-prior"
            result.remainingCrafts = boundedAdaptive(staticRemaining, remainingSkill / rate)
            result.plannerEligible = true
            result.weight = weight
            result.observedSkillUpRate = accountGlobalRate
            result.blendedSkillUpRate = rate
            result.confidence = accountTelemetry and accountTelemetry.confidence or nil
            result.usedAccountPrior = true
            result.usedHistoricalAccount = true
            return result
        end
        return result
    end

    local cursor = currentSkill
    local totalCraftsFloat, weightedWeight, weightedSkill = 0, 0, 0
    local usedBand, usedGlobal = false, false
    local usedDifficultyBand, usedRecipeDifficulty = false, false
    local usedAccount, usedAccountTransition = false, false
    local usedHistoricalLocal, usedHistoricalAccount = false, false
    local usedBuildRevalidation = false
    local usedAccountBuildConsensus = false
    local currentBandTelemetry = nil
    while cursor < targetSkill do
        local startSkill = bandStartForSkill(cursor)
        local endExclusive = math.min(targetSkill, (startSkill or cursor) + self.skillBandSize)
        if endExclusive <= cursor then endExclusive = math.min(targetSkill, cursor + self.skillBandSize) end
        local skillSpan = math.max(0, endExclusive - cursor)
        local band = startSkill ~= nil and telemetry and telemetry.skillBands and telemetry.skillBands[bandToken(startSkill)] or nil
        local accountBand = startSkill ~= nil and accountTelemetry and accountTelemetry.skillBands and accountTelemetry.skillBands[bandToken(startSkill)] or nil
        local revalidatedBand = startSkill ~= nil and buildCompatibility and buildCompatibility.bands and buildCompatibility.bands[bandToken(startSkill)] or nil
        local consensusBand = startSkill ~= nil and accountBuildConsensus and accountBuildConsensus.bands and accountBuildConsensus.bands[bandToken(startSkill)] or nil
        local rate, weight, source, sample = staticRate, 0, "route-static", 0
        local difficultyPrediction
        local difficultyToken
        if cursor == currentSkill then
            difficultyToken = result.currentDifficulty
        elseif result.currentDifficulty then
            difficultyPrediction = self:PredictDifficultyForSkill(key, nil, recipeName, currentSkill, result.currentDifficulty, cursor)
            if not difficultyPrediction then
                difficultyPrediction = self:PredictAccountDifficultyForSkill(key, nil, recipeName, currentSkill, result.currentDifficulty, cursor)
            end
            difficultyToken = difficultyPrediction and difficultyPrediction.token or nil
        end
        local projectedDifficulty = difficultyPrediction and difficultyPrediction.projected or false
        local bandDifficulty = (difficultyToken and band and band.difficulties) and band.difficulties[difficultyToken] or nil
        local recipeDifficulty = (difficultyToken and telemetry and telemetry.difficulties) and telemetry.difficulties[difficultyToken] or nil
        local accountBandDifficulty = (difficultyToken and accountBand and accountBand.difficulties) and accountBand.difficulties[difficultyToken] or nil
        local accountRecipeDifficulty = (difficultyToken and accountTelemetry and accountTelemetry.difficulties) and accountTelemetry.difficulties[difficultyToken] or nil
        if (not localHistorical) and bandDifficulty and (tonumber(bandDifficulty.skillObservedCrafts) or 0) >= self.minDifficultyBandPlannerSamples and tonumber(bandDifficulty.skillUpRate) ~= nil then
            sample = tonumber(bandDifficulty.skillObservedCrafts) or 0
            rate, weight = blendedRate(staticRate, bandDifficulty.skillUpRate, sample, self.maxDifficultyBandPlannerWeight, 8)
            source = projectedDifficulty and "skill-band+transition-difficulty" or "skill-band+difficulty"
            usedBand = true
            usedDifficultyBand = true
            result.usedDifficulty = true
            if projectedDifficulty then
                result.usedTransition = true
                result.projectedDifficultyTelemetry = bandDifficulty
                result.projectedDifficulty = difficultyToken
                result.projectedDifficultyLabel = DIFFICULTY_LABELS[difficultyToken]
            else
                result.currentDifficultyTelemetry = bandDifficulty
                currentBandTelemetry = band
            end
        elseif (not localHistorical) and recipeDifficulty and (tonumber(recipeDifficulty.skillObservedCrafts) or 0) >= self.minDifficultyPlannerSamples and tonumber(recipeDifficulty.skillUpRate) ~= nil then
            sample = tonumber(recipeDifficulty.skillObservedCrafts) or 0
            rate, weight = blendedRate(staticRate, recipeDifficulty.skillUpRate, sample, self.maxDifficultyPlannerWeight, 12)
            source = projectedDifficulty and "transition-difficulty" or "recipe-difficulty"
            usedGlobal = true
            usedRecipeDifficulty = true
            result.usedDifficulty = true
            if projectedDifficulty then
                result.usedTransition = true
                result.projectedDifficultyTelemetry = recipeDifficulty
                result.projectedDifficulty = difficultyToken
                result.projectedDifficultyLabel = DIFFICULTY_LABELS[difficultyToken]
            else
                result.currentDifficultyTelemetry = recipeDifficulty
                if cursor == currentSkill then currentBandTelemetry = band end
            end
        elseif band and (tonumber(band.skillObservedCrafts) or 0) >= localBandThreshold and tonumber(band.skillUpRate) ~= nil then
            sample = tonumber(band.skillObservedCrafts) or 0
            rate, weight = blendedRate(staticRate, band.skillUpRate, sample, localBandMaxWeight, localHistorical and 28 or 8)
            source = localHistorical and "historical-skill-band" or "skill-band"
            usedBand = true
            usedHistoricalLocal = localHistorical or usedHistoricalLocal
            if cursor == currentSkill then currentBandTelemetry = band end
        elseif globalEligible then
            sample = globalSample
            rate, weight = blendedRate(staticRate, globalRate, globalSample, localGlobalMaxWeight, localHistorical and 36 or 18)
            source = localHistorical and "historical-recipe-global" or "recipe-global"
            usedGlobal = true
            usedHistoricalLocal = localHistorical or usedHistoricalLocal
        elseif revalidatedBand and revalidatedBand.eligible and tonumber(revalidatedBand.revalidatedSkillUpRate) ~= nil then
            sample = tonumber(revalidatedBand.effectiveSamples) or 0
            rate, weight = blendedRate(staticRate, revalidatedBand.revalidatedSkillUpRate, sample, self.maxBuildRevalidationBandPlannerWeight, 16)
            source = "build-revalidated-skill-band"
            usedBuildRevalidation = true
            if cursor == currentSkill then currentBandTelemetry = band end
        elseif revalidatedGlobalEligible then
            sample = tonumber(revalidatedGlobal.effectiveSamples) or 0
            rate, weight = blendedRate(staticRate, revalidatedGlobal.revalidatedSkillUpRate, sample, self.maxBuildRevalidationPlannerWeight, 24)
            source = "build-revalidated-recipe-global"
            usedBuildRevalidation = true
        elseif (not accountHistorical) and accountBandDifficulty and (tonumber(accountBandDifficulty.skillObservedCrafts) or 0) >= self.minAccountDifficultyBandPlannerSamples and tonumber(accountBandDifficulty.skillUpRate) ~= nil then
            sample = tonumber(accountBandDifficulty.skillObservedCrafts) or 0
            rate, weight = blendedRate(staticRate, accountBandDifficulty.skillUpRate, sample, self.maxAccountDifficultyBandPlannerWeight, 20)
            source = projectedDifficulty and "account-skill-band+transition-difficulty" or "account-skill-band+difficulty"
            usedAccount = true
            usedAccountTransition = projectedDifficulty and difficultyPrediction and difficultyPrediction.accountPrior or false
            if projectedDifficulty then
                result.projectedDifficulty = difficultyToken
                result.projectedDifficultyLabel = DIFFICULTY_LABELS[difficultyToken]
                result.projectedDifficultyTelemetry = accountBandDifficulty
            end
        elseif (not accountHistorical) and accountRecipeDifficulty and (tonumber(accountRecipeDifficulty.skillObservedCrafts) or 0) >= self.minAccountDifficultyPlannerSamples and tonumber(accountRecipeDifficulty.skillUpRate) ~= nil then
            sample = tonumber(accountRecipeDifficulty.skillObservedCrafts) or 0
            rate, weight = blendedRate(staticRate, accountRecipeDifficulty.skillUpRate, sample, self.maxAccountDifficultyPlannerWeight, 24)
            source = projectedDifficulty and "account-transition-difficulty" or "account-recipe-difficulty"
            usedAccount = true
            usedAccountTransition = projectedDifficulty and difficultyPrediction and difficultyPrediction.accountPrior or false
            if projectedDifficulty then
                result.projectedDifficulty = difficultyToken
                result.projectedDifficultyLabel = DIFFICULTY_LABELS[difficultyToken]
                result.projectedDifficultyTelemetry = accountRecipeDifficulty
            end
        elseif (not accountHistorical) and accountBand and (tonumber(accountBand.skillObservedCrafts) or 0) >= accountBandThreshold and tonumber(accountBand.skillUpRate) ~= nil then
            sample = tonumber(accountBand.skillObservedCrafts) or 0
            rate, weight = blendedRate(staticRate, accountBand.skillUpRate, sample, accountBandMaxWeight, 20)
            source = "account-skill-band"
            usedAccount = true
        elseif accountGlobalEligible and not accountHistorical then
            sample = accountGlobalSample
            rate, weight = blendedRate(staticRate, accountGlobalRate, accountGlobalSample, accountGlobalMaxWeight, 30)
            source = "account-recipe-global"
            usedAccount = true
        elseif consensusBand and consensusBand.eligible and tonumber(consensusBand.revalidatedSkillUpRate) ~= nil then
            sample = tonumber(consensusBand.effectiveSamples) or 0
            rate, weight = blendedRate(staticRate, consensusBand.revalidatedSkillUpRate, sample, self.maxAccountBuildConsensusBandPlannerWeight, 28)
            source = "account-build-consensus-skill-band"
            usedAccountBuildConsensus = true
        elseif consensusGlobalEligible then
            sample = tonumber(consensusGlobal.effectiveSamples) or 0
            rate, weight = blendedRate(staticRate, consensusGlobal.revalidatedSkillUpRate, sample, self.maxAccountBuildConsensusPlannerWeight, 32)
            source = "account-build-consensus-recipe-global"
            usedAccountBuildConsensus = true
        elseif accountBand and (tonumber(accountBand.skillObservedCrafts) or 0) >= accountBandThreshold and tonumber(accountBand.skillUpRate) ~= nil then
            sample = tonumber(accountBand.skillObservedCrafts) or 0
            rate, weight = blendedRate(staticRate, accountBand.skillUpRate, sample, accountBandMaxWeight, 40)
            source = "account-historical-skill-band"
            usedAccount = true
            usedHistoricalAccount = true
        elseif accountGlobalEligible then
            sample = accountGlobalSample
            rate, weight = blendedRate(staticRate, accountGlobalRate, accountGlobalSample, accountGlobalMaxWeight, 48)
            source = "account-historical-recipe-global"
            usedAccount = true
            usedHistoricalAccount = true
        end
        totalCraftsFloat = totalCraftsFloat + (skillSpan / math.max(0.05, rate))
        weightedWeight = weightedWeight + weight * skillSpan
        weightedSkill = weightedSkill + skillSpan
        result.bandEstimates[#result.bandEstimates+1] = {
            bandStart = startSkill,
            bandEnd = startSkill and (startSkill + self.skillBandSize - 1) or nil,
            label = startSkill and bandLabel(startSkill) or "unknown",
            fromSkill = cursor,
            toSkill = endExclusive,
            skillSpan = skillSpan,
            source = source,
            sample = sample,
            observedSkillUpRate = (source == "skill-band+difficulty" or source == "skill-band+transition-difficulty") and tonumber(bandDifficulty and bandDifficulty.skillUpRate)
                or (source == "recipe-difficulty" or source == "transition-difficulty") and tonumber(recipeDifficulty and recipeDifficulty.skillUpRate)
                or (source == "skill-band" or source == "historical-skill-band") and tonumber(band and band.skillUpRate)
                or (source == "recipe-global" or source == "historical-recipe-global") and globalRate
                or source == "build-revalidated-skill-band" and tonumber(revalidatedBand and revalidatedBand.revalidatedSkillUpRate)
                or source == "build-revalidated-recipe-global" and tonumber(revalidatedGlobal and revalidatedGlobal.revalidatedSkillUpRate)
                or source == "account-build-consensus-skill-band" and tonumber(consensusBand and consensusBand.revalidatedSkillUpRate)
                or source == "account-build-consensus-recipe-global" and tonumber(consensusGlobal and consensusGlobal.revalidatedSkillUpRate)
                or (source == "account-skill-band+difficulty" or source == "account-skill-band+transition-difficulty") and tonumber(accountBandDifficulty and accountBandDifficulty.skillUpRate)
                or (source == "account-recipe-difficulty" or source == "account-transition-difficulty") and tonumber(accountRecipeDifficulty and accountRecipeDifficulty.skillUpRate)
                or (source == "account-skill-band" or source == "account-historical-skill-band") and tonumber(accountBand and accountBand.skillUpRate)
                or (source == "account-recipe-global" or source == "account-historical-recipe-global") and accountGlobalRate or nil,
            difficulty = difficultyToken,
            difficultyProjected = projectedDifficulty,
            difficultyEvidence = difficultyPrediction and difficultyPrediction.evidence or (cursor == currentSkill and result.currentDifficultyEvidence or nil),
            transitionChain = difficultyPrediction and difficultyPrediction.chain or nil,
            blendedSkillUpRate = rate,
            weight = weight,
        }
        cursor = endExclusive
    end

    if not usedBand and not usedGlobal and not usedAccount and not usedBuildRevalidation and not usedAccountBuildConsensus then return result end
    result.remainingCrafts = boundedAdaptive(staticRemaining, totalCraftsFloat)
    result.plannerEligible = true
    result.weight = weightedSkill > 0 and (weightedWeight / weightedSkill) or 0
    result.currentSkillBand = bandStartForSkill(currentSkill)
    result.currentSkillBandLabel = result.currentSkillBand and bandLabel(result.currentSkillBand) or nil
    result.currentBandTelemetry = currentBandTelemetry or (result.currentSkillBand and telemetry and telemetry.skillBands and telemetry.skillBands[bandToken(result.currentSkillBand)] or nil)
    result.currentAccountBandTelemetry = result.currentSkillBand and accountTelemetry and accountTelemetry.skillBands and accountTelemetry.skillBands[bandToken(result.currentSkillBand)] or nil
    result.usedAccountPrior = usedAccount
    result.usedAccountTransition = usedAccountTransition
    result.usedHistoricalBuild = usedHistoricalLocal
    result.usedHistoricalAccount = usedHistoricalAccount
    result.usedBuildRevalidation = usedBuildRevalidation
    result.usedAccountBuildConsensus = usedAccountBuildConsensus
    if usedBuildRevalidation and not usedBand and not usedGlobal and not result.usedDifficulty then
        result.source = "telemetry-build-revalidated"
        result.sourceDetail = "cross-build-revalidated-skill-rate"
        result.confidence = "revalidated"
        result.observedSkillUpRate = revalidatedGlobal and revalidatedGlobal.revalidatedSkillUpRate or nil
        result.revalidatedProperty = "skill-up-rate"
        result.revalidatedPreviousBuild = buildCompatibility and buildCompatibility.previousBuild or nil
        result.revalidatedEvidence = revalidatedGlobal
    elseif usedAccountBuildConsensus and not usedBand and not usedGlobal and not result.usedDifficulty and not usedAccount then
        result.source = "telemetry-account-build-consensus"
        result.sourceDetail = "cross-build-account-consensus-skill-rate"
        result.confidence = "account-build-consensus"
        result.observedSkillUpRate = consensusGlobal and consensusGlobal.revalidatedSkillUpRate or nil
        result.accountConsensusEvidence = consensusGlobal
    elseif usedAccount and not usedBand and not usedGlobal and not result.usedDifficulty then
        result.source = usedHistoricalAccount and "telemetry-account-historical" or (usedAccountTransition and "telemetry-account-transition" or "telemetry-account-prior")
        result.sourceDetail = usedHistoricalAccount and "historical-build-account-prior" or (usedAccountTransition and "account-transition-prior" or "account-prior")
        result.confidence = accountTelemetry and accountTelemetry.confidence or "account-prior"
        result.observedSkillUpRate = accountGlobalRate
    elseif result.usedDifficulty then
        result.source = result.usedTransition and "telemetry-difficulty-transition" or (usedDifficultyBand and "telemetry-difficulty-band" or "telemetry-difficulty")
        local mixed = {}
        if result.usedTransition then mixed[#mixed+1] = "verified-transition-profile" end
        mixed[#mixed+1] = usedDifficultyBand and "difficulty-band" or "recipe-difficulty"
        -- These flags can also be set by later route segments; record mixed
        -- fallbacks without pretending the current difficulty classified them.
        if usedBand and not usedDifficultyBand then mixed[#mixed+1] = "skill-band" end
        if usedGlobal and not usedRecipeDifficulty then mixed[#mixed+1] = "recipe-fallback" end
        result.sourceDetail = table.concat(mixed, "+")
        local activeDifficultyTelemetry = result.usedTransition and result.projectedDifficultyTelemetry or result.currentDifficultyTelemetry
        result.confidence = activeDifficultyTelemetry and activeDifficultyTelemetry.confidence or "difficulty-mixed"
        result.observedSkillUpRate = activeDifficultyTelemetry and activeDifficultyTelemetry.skillUpRate or nil
    elseif usedHistoricalLocal then
        result.source = "telemetry-historical-prior"
        result.sourceDetail = usedBand and (usedGlobal and "historical-build-skill-band+recipe-fallback" or "historical-build-skill-band") or "historical-build-recipe-prior"
        result.confidence = telemetry and telemetry.confidence or "historical"
        result.observedSkillUpRate = result.currentBandTelemetry and result.currentBandTelemetry.skillUpRate or globalRate
    elseif usedBand then
        result.source = "telemetry-skill-band"
        result.sourceDetail = usedGlobal and "skill-band+recipe-fallback" or "skill-band"
        result.confidence = result.currentBandTelemetry and result.currentBandTelemetry.confidence or "band-mixed"
        result.observedSkillUpRate = result.currentBandTelemetry and result.currentBandTelemetry.skillUpRate or nil
    else
        -- Preserve alpha44's public source value for recipe-wide fallback while
        -- exposing the more precise sourceDetail to diagnostics/UI.
        result.source = "telemetry-blended"
        result.sourceDetail = "recipe-global-fallback"
        result.confidence = telemetry.confidence
        result.observedSkillUpRate = globalRate
    end
    if usedBuildRevalidation and (usedBand or usedGlobal or result.usedDifficulty) then
        result.sourceDetail = tostring(result.sourceDetail or result.source or "telemetry") .. "+cross-build-revalidated-skill-rate"
        result.revalidatedProperty = "skill-up-rate"
        result.revalidatedPreviousBuild = buildCompatibility and buildCompatibility.previousBuild or nil
        result.revalidatedEvidence = revalidatedGlobal
    end
    if usedAccountBuildConsensus and (usedBand or usedGlobal or result.usedDifficulty or usedBuildRevalidation or usedAccount) then
        result.sourceDetail = tostring(result.sourceDetail or result.source or "telemetry") .. "+cross-build-account-consensus"
        result.accountConsensusEvidence = consensusGlobal
    end
    if usedAccount and (usedBand or usedGlobal or result.usedDifficulty or usedBuildRevalidation or usedAccountBuildConsensus) then
        result.sourceDetail = tostring(result.sourceDetail or result.source or "telemetry") .. (usedHistoricalAccount and "+historical-account-prior" or "+account-prior")
    end
    return result
end

function RecipeTelemetry:GetPlanStatus(key, plan)
    if not plan or plan.actionKind ~= "craft" or not plan.step then
        return { contract=self.contract, active=false, label="Not active", tone="muted" }
    end
    local step = plan.step
    local telemetry = step.telemetry or self:GetRecipe(key, nil, step.recipe)
    local estimate = step.telemetryEstimate
    local accountTelemetry = estimate and estimate.accountTelemetry or self:GetAccountRecipePrior(key, nil, step.recipe)
    local displayTelemetry = telemetry or accountTelemetry
    local staticRemaining = tonumber(step.staticRemainingCrafts) or tonumber(step.remainingCrafts) or 0
    local remaining = tonumber(step.remainingCrafts) or staticRemaining
    if not displayTelemetry or (tonumber(displayTelemetry.confirmedCrafts) or 0) <= 0 then
        return { contract=self.contract, active=true, label="Static estimate · no confirmed sample", tone="muted", telemetry=telemetry, accountTelemetry=accountTelemetry }
    end

    local currentBand = estimate and estimate.currentBandTelemetry or nil
    local currentDifficultyTelemetry = estimate and estimate.currentDifficultyTelemetry or nil
    local parts = {}
    if estimate and estimate.usedTransition then
        if estimate.currentDifficulty then
            parts[#parts+1] = tostring(estimate.currentDifficultyLabel or DIFFICULTY_LABELS[estimate.currentDifficulty] or estimate.currentDifficulty) .. " live"
        end
        if estimate.projectedDifficulty then
            parts[#parts+1] = "transition → " .. tostring(estimate.projectedDifficultyLabel or DIFFICULTY_LABELS[estimate.projectedDifficulty] or estimate.projectedDifficulty)
        end
    elseif estimate and estimate.usedAccountTransition then
        if estimate.currentDifficulty then
            parts[#parts+1] = tostring(estimate.currentDifficultyLabel or DIFFICULTY_LABELS[estimate.currentDifficulty] or estimate.currentDifficulty) .. " live"
        end
        if estimate.projectedDifficulty then parts[#parts+1] = "account transition → " .. tostring(estimate.projectedDifficultyLabel or estimate.projectedDifficulty) end
    elseif estimate and estimate.currentDifficulty and step.estimateSource ~= "telemetry-difficulty-band" and step.estimateSource ~= "telemetry-difficulty" then
        parts[#parts+1] = tostring(estimate.currentDifficultyLabel or DIFFICULTY_LABELS[estimate.currentDifficulty] or estimate.currentDifficulty) .. " live"
    end

    if step.estimateSource == "telemetry-difficulty-transition" then
        local projected = estimate and estimate.projectedDifficultyTelemetry or nil
        local sample = projected and (tonumber(projected.skillObservedCrafts) or 0) or 0
        local rate = projected and projected.skillUpRate and math.floor(projected.skillUpRate * 100 + 0.5) or nil
        if sample > 0 then parts[#parts+1] = tostring(sample) .. " projected sample" .. (sample == 1 and "" or "s") end
        if rate then parts[#parts+1] = tostring(rate) .. "% skill-up" end
    elseif (step.estimateSource == "telemetry-difficulty-band" or step.estimateSource == "telemetry-difficulty") and currentDifficultyTelemetry then
        local sample = tonumber(currentDifficultyTelemetry.skillObservedCrafts) or 0
        local rate = currentDifficultyTelemetry.skillUpRate and math.floor(currentDifficultyTelemetry.skillUpRate * 100 + 0.5) or nil
        parts[#parts+1] = tostring(estimate.currentDifficultyLabel or DIFFICULTY_LABELS[estimate.currentDifficulty] or estimate.currentDifficulty or "Difficulty")
        if estimate.currentSkillBandLabel then parts[#parts+1] = "Skill " .. tostring(estimate.currentSkillBandLabel) end
        parts[#parts+1] = tostring(sample) .. " sample" .. (sample == 1 and "" or "s")
        if rate then parts[#parts+1] = tostring(rate) .. "% skill-up" end
    elseif step.estimateSource == "telemetry-skill-band" and currentBand then
        local sample = tonumber(currentBand.skillObservedCrafts) or 0
        local rate = currentBand.skillUpRate and math.floor(currentBand.skillUpRate * 100 + 0.5) or nil
        parts[#parts+1] = "Skill " .. tostring(estimate.currentSkillBandLabel or currentBand.label or "band")
        parts[#parts+1] = tostring(sample) .. " sample" .. (sample == 1 and "" or "s")
        if rate then parts[#parts+1] = tostring(rate) .. "% skill-up" end
    elseif step.estimateSource == "telemetry-build-revalidated" then
        local evidence = estimate and estimate.revalidatedEvidence or nil
        local currentSamples = tonumber(evidence and evidence.currentSamples) or 0
        local priorSamples = tonumber(evidence and evidence.priorSamples) or 0
        local delta = tonumber(evidence and evidence.rateDelta)
        parts[#parts+1] = "Build revalidated · skill rate"
        parts[#parts+1] = tostring(currentSamples) .. " current + " .. tostring(priorSamples) .. " prior samples"
        if delta then parts[#parts+1] = string.format("Δ %.0f%%", delta * 100) end
        if estimate and estimate.revalidatedPreviousBuild then parts[#parts+1] = "prior build " .. tostring(estimate.revalidatedPreviousBuild) end
    elseif step.estimateSource == "telemetry-account-build-consensus" then
        local evidence = estimate and estimate.accountConsensusEvidence or nil
        local currentSamples = tonumber(evidence and evidence.currentSamples) or 0
        local priorSamples = tonumber(evidence and evidence.priorSamples) or 0
        local chars = tonumber(evidence and evidence.contributingCharacters) or 0
        local delta = tonumber(evidence and evidence.rateDelta)
        local spread = tonumber(evidence and evidence.rateSpread)
        parts[#parts+1] = "Account build consensus · skill rate"
        parts[#parts+1] = tostring(chars) .. " chars"
        parts[#parts+1] = tostring(currentSamples) .. " current + " .. tostring(priorSamples) .. " prior samples"
        if spread then parts[#parts+1] = string.format("spread %.0f%%", spread * 100) end
        if delta then parts[#parts+1] = string.format("Δ %.0f%%", delta * 100) end
    elseif step.estimateSource == "telemetry-historical-prior" and currentBand then
        local sample = tonumber(currentBand.skillObservedCrafts) or 0
        local rate = currentBand.skillUpRate and math.floor(currentBand.skillUpRate * 100 + 0.5) or nil
        parts[#parts+1] = "Historical build · Skill " .. tostring(estimate.currentSkillBandLabel or currentBand.label or "band")
        parts[#parts+1] = tostring(sample) .. " sample" .. (sample == 1 and "" or "s")
        if rate then parts[#parts+1] = tostring(rate) .. "% skill-up" end
    else
        local sample = tonumber(displayTelemetry.skillObservedCrafts) or 0
        local rate = displayTelemetry.skillUpRate and math.floor(displayTelemetry.skillUpRate * 100 + 0.5) or nil
        parts[#parts+1] = tostring(sample) .. " skill sample" .. (sample == 1 and "" or "s")
        if rate then parts[#parts+1] = tostring(rate) .. "% skill-up" end
        if displayTelemetry.craftsPerSkill then parts[#parts+1] = string.format("%.2f crafts/skill", displayTelemetry.craftsPerSkill) end
        if step.estimateSource == "telemetry-blended" then parts[#parts+1] = "recipe fallback" end
    end
    if estimate and estimate.usedTransition then parts[#parts+1] = "transition profile" end
    if estimate and estimate.usedBuildRevalidation then
        parts[#parts+1] = "skill-rate only"
        parts[#parts+1] = "difficulty current-build only"
    end
    if estimate and estimate.usedAccountBuildConsensus then
        local evidence = estimate.accountConsensusEvidence or (estimate.accountBuildConsensus and estimate.accountBuildConsensus.global)
        local chars = tonumber(evidence and evidence.contributingCharacters) or 0
        local materialConsensus = estimate.accountBuildConsensus and estimate.accountBuildConsensus.materials or nil
        parts[#parts+1] = "account build consensus" .. (chars > 0 and (" · " .. tostring(chars) .. " chars") or "")
        if materialConsensus and materialConsensus.status == "compatible" then
            parts[#parts+1] = "materials consensus verified (diagnostic)"
        end
        parts[#parts+1] = "skill-rate only"
        parts[#parts+1] = "difficulty current-build only"
    end
    if estimate and estimate.usedHistoricalBuild then parts[#parts+1] = "historical build prior" end
    if estimate and estimate.usedAccountPrior then
        local chars = tonumber(accountTelemetry and accountTelemetry.contributingCharacters) or 0
        local prefix = estimate.usedHistoricalAccount and "historical account prior" or "account prior"
        -- Label current-build evidence with the observed client, never with
        -- the immutable legacy production/source TARGET_BUILD constant.
        if not estimate.usedHistoricalAccount then
            local current=currentBuildProvenance()
            if current and current.quality=="LIVE" and current.build then
                prefix = prefix .. " · build " .. tostring(current.build)
            end
        end
        parts[#parts+1] = prefix .. (chars > 0 and (" · " .. tostring(chars) .. " char" .. (chars == 1 and "" or "s")) or "")
    end
    local adaptive = step.estimateSource == "telemetry-blended" or step.estimateSource == "telemetry-skill-band" or step.estimateSource == "telemetry-difficulty" or step.estimateSource == "telemetry-difficulty-band" or step.estimateSource == "telemetry-difficulty-transition" or step.estimateSource == "telemetry-account-prior" or step.estimateSource == "telemetry-account-transition" or step.estimateSource == "telemetry-historical-prior" or step.estimateSource == "telemetry-account-historical" or step.estimateSource == "telemetry-build-revalidated" or step.estimateSource == "telemetry-account-build-consensus"
    if adaptive and remaining ~= staticRemaining then
        parts[#parts+1] = tostring(remaining) .. " est. (" .. tostring(staticRemaining) .. " static)"
    elseif adaptive then
        parts[#parts+1] = tostring(remaining) .. " est."
    else
        parts[#parts+1] = "learning"
    end
    return {
        contract = self.contract,
        active = true,
        label = table.concat(parts, " · "),
        tone = adaptive and "cyan" or "muted",
        telemetry = telemetry,
        accountTelemetry = accountTelemetry,
        estimateSource = step.estimateSource or "route-static",
        estimateSourceDetail = step.estimateSourceDetail,
        currentBandTelemetry = currentBand,
        currentDifficultyTelemetry = currentDifficultyTelemetry,
        currentDifficulty = estimate and estimate.currentDifficulty or nil,
        projectedDifficulty = estimate and estimate.projectedDifficulty or nil,
        usedTransition = estimate and estimate.usedTransition or false,
        usedAccountPrior = estimate and estimate.usedAccountPrior or false,
        usedHistoricalBuild = estimate and estimate.usedHistoricalBuild or false,
        usedHistoricalAccount = estimate and estimate.usedHistoricalAccount or false,
        usedBuildRevalidation = estimate and estimate.usedBuildRevalidation or false,
        usedAccountBuildConsensus = estimate and estimate.usedAccountBuildConsensus or false,
        buildCompatibility = estimate and estimate.buildCompatibility or nil,
        accountBuildConsensus = estimate and estimate.accountBuildConsensus or nil,
    }
end

function RecipeTelemetry:GetSummary()
    local store = getStore()
    if not store then return "Recipe telemetry unavailable." end
    local root = getTelemetryRoot()
    local currentKey = characterKey()
    local build = currentBuildProvenance()
    local token = currentBuildToken()
    local currentProfile = token and store.buildProfiles and store.buildProfiles[token] or nil
    local activeContainer = currentProfile or store
    local localHistorical = currentProfile == nil
    local accountCharacters, accountRecipeTokens = 0, {}
    local historicalAccountCharacters, historicalAccountRecipeTokens = 0, {}
    for otherKey, otherStore in pairs(root and root.characters or {}) do
        if tostring(otherKey) ~= tostring(currentKey) and type(otherStore) == "table" then
            local exactProfile = token and type(otherStore.buildProfiles) == "table" and otherStore.buildProfiles[token] or nil
            local contributed = false
            for recipeKey, record in pairs(exactProfile and exactProfile.recipes or {}) do
                if type(record) == "table" and (tonumber(record.confirmedCrafts) or 0) > 0 then
                    accountRecipeTokens[tostring(recipeKey)] = true
                    contributed = true
                end
            end
            if contributed then accountCharacters = accountCharacters + 1 end
            local historicalContributed = false
            for recipeKey, record in pairs(otherStore.recipes or {}) do
                local exactRecord = exactProfile and exactProfile.recipes and exactProfile.recipes[recipeKey] or nil
                if hasAggregateEvidence(record) and not hasAggregateEvidence(exactRecord) then
                    historicalAccountRecipeTokens[tostring(recipeKey)] = true
                    historicalContributed = true
                end
            end
            if historicalContributed then historicalAccountCharacters = historicalAccountCharacters + 1 end
        end
    end
    local accountRecipes = 0
    for _ in pairs(accountRecipeTokens) do accountRecipes = accountRecipes + 1 end
    local historicalAccountRecipes = 0
    for _ in pairs(historicalAccountRecipeTokens) do historicalAccountRecipes = historicalAccountRecipes + 1 end
    local historicalLocalRecipes = 0
    for recipeKey, record in pairs(store.recipes or {}) do
        local exactRecord = currentProfile and currentProfile.recipes and currentProfile.recipes[recipeKey] or nil
        if hasAggregateEvidence(record) and not hasAggregateEvidence(exactRecord) then historicalLocalRecipes = historicalLocalRecipes + 1 end
    end
    local rows = {}
    for _, record in pairs(activeContainer and activeContainer.recipes or {}) do
        local telemetry = enrich(record, localHistorical and HISTORICAL_LOCAL_POLICY or nil)
        if telemetry and telemetry.confirmedCrafts > 0 then rows[#rows+1] = telemetry end
    end
    table.sort(rows, function(a,b)
        if (a.updatedAt or 0) ~= (b.updatedAt or 0) then return (a.updatedAt or 0) > (b.updatedAt or 0) end
        return tostring(a.recipeName or a.token) < tostring(b.recipeName or b.token)
    end)
    if #rows == 0 and accountCharacters == 0 and historicalAccountCharacters == 0 then return "Recipe telemetry: no confirmed reconciled craft units yet." end
    local lines = { "Recipe telemetry: build-provenance authority + local/account cross-build revalidation" }
    lines[#lines+1] = string.format(
        "Build · Forever %s · interface %s · local scope %s",
        tostring(build and build.build or "unknown"),
        tostring(build and build.interface or "unknown"),
        localHistorical and "historical/unknown provenance" or "current build"
    )
    lines[#lines+1] = string.format(
        "Scope · active local recipes %d · retained historical local %d · current-build account prior %d other character%s / %d recipe profile%s · historical account %d character%s / %d recipe profile%s",
        #rows, historicalLocalRecipes,
        accountCharacters, accountCharacters == 1 and "" or "s", accountRecipes, accountRecipes == 1 and "" or "s",
        historicalAccountCharacters, historicalAccountCharacters == 1 and "" or "s", historicalAccountRecipes, historicalAccountRecipes == 1 and "" or "s"
    )
    for index = 1, math.min(#rows, 8) do
        local row = rows[index]
        local rate = row.skillUpRate and string.format("%.0f%%", row.skillUpRate * 100) or "n/a"
        local cps = row.craftsPerSkill and string.format("%.2f", row.craftsPerSkill) or "n/a"
        local reagent = row.reagentConsumptionRatio and string.format("%.0f%% expected", row.reagentConsumptionRatio * 100) or "n/a"
        lines[#lines+1] = string.format(
            "%s · %d confirmed · %d skill samples · %s skill-up · %s crafts/skill · reagents %s · %s",
            tostring(row.recipeName or row.recipeID or "unknown recipe"),
            row.confirmedCrafts or 0,
            row.skillObservedCrafts or 0,
            rate,
            cps,
            reagent,
            row.plannerEligible and ("planner " .. tostring(row.confidence)) or "planner learning"
        )
        local bandParts = {}
        for _, token in ipairs(row.skillBandOrder or {}) do
            local band = row.skillBands and row.skillBands[token] or nil
            if band and (tonumber(band.skillObservedCrafts) or 0) > 0 then
                local bandRate = band.skillUpRate and string.format("%.0f%%", band.skillUpRate * 100) or "n/a"
                bandParts[#bandParts+1] = string.format("%s: %d @ %s", tostring(band.label), tonumber(band.skillObservedCrafts) or 0, bandRate)
            end
        end
        if #bandParts > 0 then lines[#lines+1] = "  Bands · " .. table.concat(bandParts, " · ") end
        local difficultyParts = {}
        for _, token in ipairs(row.difficultyOrder or {}) do
            local difficulty = row.difficulties and row.difficulties[token] or nil
            if difficulty and (tonumber(difficulty.skillObservedCrafts) or 0) > 0 then
                local difficultyRate = difficulty.skillUpRate and string.format("%.0f%%", difficulty.skillUpRate * 100) or "n/a"
                difficultyParts[#difficultyParts+1] = string.format("%s: %d @ %s", tostring(difficulty.label or token), tonumber(difficulty.skillObservedCrafts) or 0, difficultyRate)
            end
        end
        if #difficultyParts > 0 then lines[#lines+1] = "  Difficulty · " .. table.concat(difficultyParts, " · ") end
        local transitionParts = {}
        for _, transition in ipairs(row.difficultyTransitions and row.difficultyTransitions.transitions or {}) do
            if transition.eligible then
                local boundary = transition.boundaryMin == transition.boundaryMax and tostring(transition.boundaryMin) or (tostring(transition.boundaryMin) .. "-" .. tostring(transition.boundaryMax))
                transitionParts[#transitionParts+1] = string.format("%s→%s @ %s (%d/%d)", tostring(transition.fromLabel), tostring(transition.toLabel), boundary, tonumber(transition.fromSamples) or 0, tonumber(transition.toSamples) or 0)
            end
        end
        if #transitionParts > 0 and not localHistorical then
            lines[#lines+1] = "  Transitions · " .. table.concat(transitionParts, " · ")
        elseif #transitionParts > 0 and localHistorical then
            lines[#lines+1] = "  Transitions · retained historical evidence (projection disabled)"
        end
        if not localHistorical then
            local compatibility = buildCrossBuildCompatibility(store, row.key, row.recipeID, row.recipeName)
            if compatibility and compatibility.previousBuild then
                local global = compatibility.global
                local delta = global and global.rateDelta and string.format("%.0f%%", global.rateDelta * 100) or "n/a"
                local state = global and global.eligible and "skill rate revalidated" or (global and global.status == "changed" and "skill rate changed" or "skill rate learning")
                lines[#lines+1] = string.format(
                    "  Cross-build local · %s vs build %s · %d current/%d prior · Δ %s · materials %s (diagnostic only) · difficulty current-build only",
                    state, tostring(compatibility.previousBuild), tonumber(global and global.currentSamples) or 0, tonumber(global and global.priorSamples) or 0, delta, tostring(compatibility.materials and compatibility.materials.status or "learning")
                )
            end
            local consensus = buildAccountBuildConsensus(row.key, row.recipeID, row.recipeName)
            local globalConsensus = consensus and consensus.global or nil
            if globalConsensus and (tonumber(globalConsensus.contributingCharacters) or 0) > 0 then
                local delta = globalConsensus.rateDelta and string.format("%.0f%%", globalConsensus.rateDelta * 100) or "n/a"
                local spread = globalConsensus.rateSpread and string.format("%.0f%%", globalConsensus.rateSpread * 100) or "n/a"
                local materialConsensus = consensus and consensus.materials or nil
                lines[#lines+1] = string.format(
                    "  Cross-build account · %s · %d chars / %d build%s · %d current/%d prior · spread %s · Δ %s · materials %s (diagnostic only) · difficulty current-build only",
                    tostring(globalConsensus.status or "learning"), tonumber(globalConsensus.contributingCharacters) or 0,
                    tonumber(globalConsensus.contributingBuilds) or 0, tonumber(globalConsensus.contributingBuilds) == 1 and "" or "s",
                    tonumber(globalConsensus.currentSamples) or 0, tonumber(globalConsensus.priorSamples) or 0, spread, delta,
                    tostring(materialConsensus and materialConsensus.status or "learning")
                )
            end
        end
    end
    lines[#lines+1] = string.format(
        "Planner policy: verified difficulty needs %d samples in the current %d-skill band (or %d recipe-wide difficulty samples). Future difficulty is projected only through a verified adjacent transition with at least %d samples on each side and a gap of at most %d skill; otherwise %d band samples / %d recipe-wide samples remain the fallback. Adaptive estimates remain bounded to 67%%-150%% of static routing.",
        self.minDifficultyBandPlannerSamples, self.skillBandSize, self.minDifficultyPlannerSamples, self.minTransitionSideSamples, self.maxTransitionGap, self.minBandPlannerSamples, self.minPlannerSamples
    )
    lines[#lines+1] = string.format(
        "Account prior: other characters require %d band / %d recipe samples (difficulty %d/%d; transition sides %d) and use lower planner weights. Character-local eligible evidence always wins.",
        self.minAccountBandPlannerSamples, self.minAccountPlannerSamples, self.minAccountDifficultyBandPlannerSamples, self.minAccountDifficultyPlannerSamples, self.minAccountTransitionSideSamples
    )
    lines[#lines+1] = string.format(
        "Build provenance: older/unknown local history requires %d band / %d recipe samples (max %.0f%%/%.0f%% weight); older/unknown account history requires %d/%d (max %.0f%%/%.0f%%). Historical difficulty buckets and transitions are diagnostic only and never projected. Any current-build profile replaces historical history for active planning.",
        self.minHistoricalBandPlannerSamples, self.minHistoricalPlannerSamples, self.maxHistoricalBandPlannerWeight * 100, self.maxHistoricalPlannerWeight * 100,
        self.minHistoricalAccountBandPlannerSamples, self.minHistoricalAccountPlannerSamples, self.maxHistoricalAccountBandPlannerWeight * 100, self.maxHistoricalAccountPlannerWeight * 100
    )
    lines[#lines+1] = string.format(
        "Cross-build revalidation: generic recipe skill rate needs %d current + %d explicit prior-build samples within %.0f%%; skill bands need %d + %d within %.0f%%. Revalidated Planner weight is capped at %.0f%%/%.0f%% (recipe/band). Material signatures require exact per-craft agreement but are diagnostic only; difficulty colors and transitions never transfer between builds.",
        self.minBuildRevalidationCurrentSamples, self.minBuildRevalidationPriorSamples, self.maxBuildRevalidationRateDelta * 100,
        self.minBuildRevalidationBandCurrentSamples, self.minBuildRevalidationBandPriorSamples, self.maxBuildRevalidationBandRateDelta * 100,
        self.maxBuildRevalidationPlannerWeight * 100, self.maxBuildRevalidationBandPlannerWeight * 100
    )
    lines[#lines+1] = string.format(
        "Account build consensus: at least %d other characters and %d prior recipe samples must agree within %.0f%% spread, while %d fresh current-build samples must remain within %.0f%% of consensus. Skill bands require %d prior + %d current samples within %.0f%% spread/%.0f%% delta. Planner weight is capped at %.0f%%/%.0f%% (recipe/band), below same-build and local authority.",
        self.minAccountBuildConsensusCharacters, self.minAccountBuildConsensusPriorSamples, self.maxAccountBuildConsensusRateSpread * 100,
        self.minAccountBuildConsensusCurrentSamples, self.maxAccountBuildConsensusRateDelta * 100,
        self.minAccountBuildConsensusBandPriorSamples, self.minAccountBuildConsensusBandCurrentSamples,
        self.maxAccountBuildConsensusBandRateSpread * 100, self.maxAccountBuildConsensusBandRateDelta * 100,
        self.maxAccountBuildConsensusPlannerWeight * 100, self.maxAccountBuildConsensusBandPlannerWeight * 100
    )
    lines[#lines+1] = string.format(
        "Account material consensus: at least %d other characters need %d exact prior-build units per material and the current build needs %d exact units. Contributor per-craft rates must agree within %.2f and current-build rates within %.2f. Compatible material consensus is diagnostics/evidence only and never changes Planner quantities by itself.",
        self.minAccountBuildConsensusMaterialCharacters, self.minAccountBuildConsensusMaterialPriorUnits,
        self.minAccountBuildConsensusMaterialCurrentUnits, self.maxAccountBuildConsensusMaterialRateSpread,
        self.maxAccountBuildConsensusMaterialRateDelta
    )
    return table.concat(lines, "\n")
end

JLP:RegisterModule("RecipeTelemetry", RecipeTelemetry)
