local _, JLP = ...
local TrainerOptimizer = {
    contract = "travel-aware-early-rank-training-v1",
}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetWorkflowKeys("trainer") or {}
end

local function playerLevel()
    if type(UnitLevel) ~= "function" then return 0 end
    local ok, value = pcall(UnitLevel, "player")
    if not ok then ok, value = pcall(UnitLevel) end
    return ok and (tonumber(value) or 0) or 0
end

local function normalized(value)
    return string.lower(tostring(value or "")):gsub("^%s+", ""):gsub("%s+$", "")
end

local function distance(a, b)
    if not a or not b or not a.x or not a.y or not b.x or not b.y then return nil end
    local dx, dy = tonumber(a.x) - tonumber(b.x), tonumber(a.y) - tonumber(b.y)
    if not dx or not dy then return nil end
    return math.sqrt(dx * dx + dy * dy)
end

local function threshold()
    local travel = JLP.data and JLP.data.travel
    local early = travel and travel.earlyTrainer
    return tonumber(early and early.maxNormalizedDetour) or 0.12
end

local function currentTrainerMatches(source)
    if not source then return false end
    local flow = JLP:GetModule("ExecutionFlow")
    local context = flow and flow.GetCurrentContext and flow:GetCurrentContext() or nil
    if not context or context.station ~= "trainer" then return false end
    local observed = normalized(context.trainerName or context.actorName)
    local expected = normalized(source.name)
    return observed ~= "" and expected ~= "" and observed == expected
end

function TrainerOptimizer:Evaluate(key, professionState, gate)
    local skill = tonumber(professionState and professionState.skill) or 0
    local cap = tonumber(professionState and professionState.maxSkill) or 0
    local requiredSkill = tonumber(gate and gate.requiredSkill) or tonumber(gate and gate.cap) or 0
    local minLevel = tonumber(gate and gate.minCharacterLevel) or 0
    local level = playerLevel()
    local mandatory = gate ~= nil and cap > 0 and skill >= cap
    local skillEligible = gate ~= nil and skill >= requiredSkill
    local levelEligible = gate ~= nil and level >= minLevel

    local resolver = JLP:GetModule("SourceResolver")
    local router = JLP:GetModule("TravelRouter")
    local origin = router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
    local source = resolver and resolver.GetBestTrainerForGate and resolver:GetBestTrainerForGate(key, gate, nil, origin)
        or (resolver and resolver.GetTrainerForGate and resolver:GetTrainerForGate(key, gate) or nil)
    if key=="TAILORING" and gate and (gate.cap==75 or gate.cap==150 or gate.cap==225) then
        source=resolver and resolver.GetOwnerTrainerForRank and resolver:GetOwnerTrainerForRank(key,gate.rank) or nil
    end
    local location = router and source and router:GetSourceLocation(source) or nil
    local travelCost = router and location and router:Cost(origin, location) or nil
    local sameMap = origin and location and origin.mapID and location.mapID and tonumber(origin.mapID) == tonumber(location.mapID) or false
    local normalizedDistance = sameMap and distance(origin, location) or nil
    local exactTrainer = currentTrainerMatches(source)
    local nearby = sameMap and normalizedDistance ~= nil and normalizedDistance <= threshold()
    local eligible = skillEligible and levelEligible

    local recommendEarly = false
    local reason = "not-eligible"
    if mandatory then
        reason = levelEligible and "rank-cap-reached" or "rank-cap-level-blocked"
    elseif not skillEligible then
        reason = "skill-requirement-not-met"
    elseif not levelEligible then
        reason = "character-level-requirement-not-met"
    elseif exactTrainer then
        recommendEarly = true
        reason = "already-at-exact-trainer"
    elseif nearby then
        recommendEarly = true
        reason = "nearby-same-map-opportunity"
    elseif sameMap and normalizedDistance == nil then
        reason = "same-map-position-unavailable"
    elseif sameMap then
        reason = "same-map-detour-too-large"
    else
        reason = "no-low-detour-opportunity"
    end

    return {
        contract = self.contract,
        profession = key,
        gate = gate,
        skill = skill,
        skillCap = cap,
        playerLevel = level,
        requiredSkill = requiredSkill,
        minCharacterLevel = minLevel,
        mandatory = mandatory,
        eligible = eligible,
        skillEligible = skillEligible,
        levelEligible = levelEligible,
        recommendEarly = recommendEarly,
        early = recommendEarly and not mandatory or false,
        reason = reason,
        sourceInfo = source,
        origin = origin,
        location = location,
        sameMap = sameMap,
        distanceNormalized = normalizedDistance,
        maxNormalizedDetour = threshold(),
        travelCost = travelCost,
        evidence = recommendEarly and "live-map-low-detour-opportunity" or "conservative-no-detour-policy",
    }
end

function TrainerOptimizer:Format(decision)
    if not decision or not decision.gate then return "Trainer optimization: no pending rank gate." end
    local resolver = JLP:GetModule("SourceResolver")
    local source = decision.sourceInfo and resolver and resolver:Format(decision.sourceInfo, false) or "trainer source unavailable"
    local distanceText = decision.distanceNormalized and string.format("%.3f normalized", decision.distanceNormalized) or "distance unavailable"
    return string.format(
        "Trainer optimization: %s | skill %d/%d | req %d + L%d | %s | %s | %s",
        tostring(decision.gate.rank or "next rank"),
        tonumber(decision.skill) or 0,
        tonumber(decision.skillCap) or 0,
        tonumber(decision.requiredSkill) or 0,
        tonumber(decision.minCharacterLevel) or 0,
        tostring(decision.reason or "unknown"),
        source,
        distanceText
    )
end

function TrainerOptimizer:GetSummary()
    local planner = JLP:GetModule("Planner")
    local api = JLP:GetModule("ProfessionAPI")
    local lines = { "Travel-aware early rank training: conservative low-detour policy" }
    for _, key in ipairs(productionKeys()) do
        local profession = api and api:Get(key) or nil
        local dataset = planner and planner:GetDataset(key) or nil
        local gate
        if profession and dataset then
            for _, row in ipairs(dataset.trainerGates or {}) do
                if tonumber(row.cap) == tonumber(profession.maxSkill) then gate = row break end
            end
        end
        lines[#lines + 1] = self:Format(self:Evaluate(key, profession, gate))
    end
    return table.concat(lines, "\n")
end

JLP:RegisterModule("TrainerOptimizer", TrainerOptimizer)
