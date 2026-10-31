local _, JLP = ...

-- Authoritative profession identity/capability registry.
-- A profession can be known and workflow-enabled without holding native production authority.
-- progressionStrategies describe domain semantics; maturity controls which
-- historic production maturity is NOT a generic workflow availability filter.
local ProfessionRegistry = {
    contract = "profession-registry-multi-strategy-v1",
    runtimeScopeContract = "profession-registry-runtime-scope-v1",
    stateEnvelopeContract = "generic-profession-state-envelope-v1",
    stableIdentityContract = "profession-stable-identity-v1",
}

local DEFINITIONS = {
    TAILORING = {
        key="TAILORING", order=10, label="Tailoring", category="PRIMARY", professionEnum=7, skillLineID=197, datasetKey="tailoring",
        progressionStrategies={"RECIPE_CRAFTING"},
        capabilities={recipeCrafting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=true, craftOne=true, craftAll=true, autoRoute=true},
        maturity={declared=true, research=true, production=true},
    },
    ENCHANTING = {
        key="ENCHANTING", order=20, label="Enchanting", category="PRIMARY", professionEnum=9, skillLineID=333, datasetKey="enchanting",
        progressionStrategies={"TARGETED_CRAFTING","DISENCHANT"},
        capabilities={targetedCrafting=true, disenchant=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=true, craftOne=true, assistedSequencePlanning=true, assistedSequenceNative=false, autoRoute=false},
        maturity={declared=true, research=true, production=true},
    },
    ALCHEMY = {
        key="ALCHEMY", order=30, label="Alchemy", category="PRIMARY", professionEnum=3, skillLineID=171, datasetKey="alchemy",
        progressionStrategies={"RECIPE_CRAFTING"},
        capabilities={recipeCrafting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=false, productionCandidatePlanning=true},
        maturity={declared=true, research=true, candidate=true, production=false},
    },
    BLACKSMITHING = {
        key="BLACKSMITHING", order=40, label="Blacksmithing", category="PRIMARY", professionEnum=1, skillLineID=164, datasetKey="blacksmithing",
        progressionStrategies={"RECIPE_CRAFTING"},
        capabilities={recipeCrafting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=false},
        maturity={declared=true, research=true, candidate=true, production=false},
    },
    ENGINEERING = {
        key="ENGINEERING", order=50, label="Engineering", category="PRIMARY", professionEnum=8, skillLineID=202, datasetKey="engineering",
        progressionStrategies={"RECIPE_CRAFTING"},
        capabilities={recipeCrafting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=false},
        maturity={declared=true, research=true, candidate=true, production=false},
    },
    LEATHERWORKING = {
        key="LEATHERWORKING", order=60, label="Leatherworking", category="PRIMARY", professionEnum=2, skillLineID=165, datasetKey="leatherworking",
        progressionStrategies={"RECIPE_CRAFTING"},
        capabilities={recipeCrafting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=false},
        maturity={declared=true, research=true, candidate=true, production=false},
    },
    HERBALISM = {
        key="HERBALISM", order=70, label="Herbalism", category="PRIMARY", professionEnum=4, skillLineID=182,
        progressionStrategies={"NODE_GATHERING"}, utilityStrategies={"RECIPE_CRAFTING"},
        capabilities={mapRoutes=true, recipeCrafting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=false},
        maturity={declared=true, research=false, production=false},
    },
    MINING = {
        key="MINING", order=80, label="Mining", category="PRIMARY", professionEnum=6, skillLineID=186,
        progressionStrategies={"NODE_GATHERING"}, advisoryProgressionStrategies={"SMELTING"}, utilityStrategies={"SMELTING","RECIPE_CRAFTING"},
        capabilities={mapRoutes=true, recipeCrafting=true, smelting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=false},
        maturity={declared=true, research=false, production=false},
    },
    SKINNING = {
        key="SKINNING", order=90, label="Skinning", category="PRIMARY", professionEnum=11, skillLineID=393,
        progressionStrategies={"AREA_GATHERING"}, utilityStrategies={"RECIPE_CRAFTING"},
        capabilities={mapAreas=true, recipeCrafting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=false},
        maturity={declared=true, research=false, production=false},
    },
    COOKING = {
        key="COOKING", order=100, label="Cooking", category="SECONDARY", professionEnum=5, skillLineID=185, datasetKey="cooking",
        progressionStrategies={"RECIPE_CRAFTING"},
        capabilities={recipeCrafting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=false},
        maturity={declared=true, research=true, candidate=true, production=false},
    },
    FIRST_AID = {
        key="FIRST_AID", order=110, label="First Aid", category="SECONDARY", professionEnum=0, skillLineID=129, datasetKey="first_aid",
        progressionStrategies={"RECIPE_CRAFTING"},
        capabilities={recipeCrafting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=false},
        maturity={declared=true, research=true, candidate=true, production=false},
    },
    FISHING = {
        key="FISHING", order=120, label="Fishing", category="SECONDARY", professionEnum=10, skillLineID=356,
        progressionStrategies={"FISHING_AREA"}, utilityStrategies={"RECIPE_CRAFTING"},
        capabilities={mapAreas=true, recipeCrafting=true, acquisition=true, trainer=true, checkpoint=true, executionFlow=true, nativeDispatch=false},
        maturity={declared=true, research=false, production=false},
    },
}


-- Historical build70450 SkillLine lineage: fallback evidence only.
-- A matching CURRENT CLIENT GetTradeSkillLineForRecipe observation, from a
-- verified profession-panel session, takes priority over historical mappings.
-- Untrusted/historical callers must not promote arbitrary parent IDs.
local DB70450_SKILL_LINE_PARENT = {
    [2934]=2933,
    [2937]=171,
    [2938]=164,
    [2939]=185,
    [2940]=333,
    [2941]=202,
    [2942]=129,
    [2943]=356,
    [2944]=182,
    [2945]=165,
    [2946]=186,
    [2947]=393,
    [2948]=197,
    [2988]=40,
}
-- Corroborated on the five-character / thirteen-snapshot Forever probe. A
-- shared appearance is NOT evidence of learned=true in another profession.
local VERIFIED_SHARED_RECIPE = { [461692] = {LEATHERWORKING=true, TAILORING=true} }

-- liveSource is intentionally opt-in: only the modules that actually called
-- the client API during a verified, stable panel observation may supply it.
-- Static CSV lineage is *historical reference*, not a current-build allowlist.
function ProfessionRegistry:ResolveRecipeLineage(professionKey, recipeSkillLineID, parentSkillLineID, recipeID, liveSource)
    local def=self:Get(professionKey)
    if not def then return "UNKNOWN_IDENTITY" end
    local base=tonumber(def.skillLineID)
    local line=tonumber(recipeSkillLineID)
    if parentSkillLineID~=nil and type(parentSkillLineID)~="number" then
        return "CONFLICTING_IDENTITY"
    end
    local parent=tonumber(parentSkillLineID)
    -- Some clients use 0 for an absent parent. It is not a trusted edge.
    if parent==0 then parent=nil end
    local function valid(v)
        return type(v)=="number" and v==v and v>0 and v==math.floor(v) and v<2147483648
    end
    if not valid(base) or not valid(line) then return "UNKNOWN_IDENTITY" end
    if parent~=nil and not valid(parent) then return "CONFLICTING_IDENTITY" end
    local csvParent=DB70450_SKILL_LINE_PARENT[line]
    local currentClient = liveSource == "LIVE_PANEL_RECIPE_API"
    if line==base then
        if parent and parent~=base then return "CONFLICTING_IDENTITY" end
        return "EXACT_BASE_MATCH"
    end
    -- The live parent is a current-session client observation, not a value
    -- read from cached recipe descriptions or historical DB2 snapshots.
    if currentClient and parent then
        if parent==line then return "CONFLICTING_IDENTITY" end
        if parent==base then return "VERIFIED_DESCENDANT_MATCH" end
        -- A one-hop observation may connect to a known older hierarchy.
        -- A cycle, unknown ancestry or an unrelated base never authorizes.
        local visited={[line]=true}
        local node=parent
        for _=1,24 do
            if visited[node] then return "CONFLICTING_IDENTITY" end
            visited[node]=true
            if node==base then return "VERIFIED_DESCENDANT_MATCH" end
            local nextParent=DB70450_SKILL_LINE_PARENT[node]
            if not valid(nextParent) then break end
            node=nextParent
        end
        if VERIFIED_SHARED_RECIPE[tonumber(recipeID)] and
            VERIFIED_SHARED_RECIPE[tonumber(recipeID)][def.key] then
            return "EXPLICIT_SHARED_REFERENCE"
        end
        return "FOREIGN_IDENTITY"
    end
    -- Without a verified live source, only historical lineage can be
    -- considered; caller-supplied parent cannot manufacture a descendant.
    if parent and csvParent and parent~=csvParent then return "CONFLICTING_IDENTITY" end
    local visited={}
    local node=line
    for _=1,24 do
        if visited[node] then return "CONFLICTING_IDENTITY" end
        visited[node]=true
        local nextParent=DB70450_SKILL_LINE_PARENT[node]
        if not valid(nextParent) then break end
        if nextParent==base then return "VERIFIED_DESCENDANT_MATCH" end
        node=nextParent
    end
    if VERIFIED_SHARED_RECIPE[tonumber(recipeID)] and
        VERIFIED_SHARED_RECIPE[tonumber(recipeID)][def.key] and
        (csvParent or parent) and (csvParent or parent)~=base then
        return "EXPLICIT_SHARED_REFERENCE"
    end
    if csvParent then return "FOREIGN_IDENTITY" end
    return "UNKNOWN_IDENTITY"
end

function ProfessionRegistry:GetLineageParent(skillLineID)
    return DB70450_SKILL_LINE_PARENT[tonumber(skillLineID)]
end

local ORDERED_KEYS = {
    "TAILORING","ENCHANTING","ALCHEMY","BLACKSMITHING","ENGINEERING","LEATHERWORKING",
    "HERBALISM","MINING","SKINNING","COOKING","FIRST_AID","FISHING",
}

local STRATEGIES = {
    RECIPE_CRAFTING=true,
    TARGETED_CRAFTING=true,
    DISENCHANT=true,
    NODE_GATHERING=true,
    SMELTING=true, -- public-band advisory only; execution still disabled
    AREA_GATHERING=true,
    FISHING_AREA=true,
}

local function normalizeKey(key)
    key = tostring(key or ""):upper():gsub("[%s%-]+", "_")
    if key == "FIRSTAID" then key = "FIRST_AID" end
    return key ~= "" and key or nil
end


function ProfessionRegistry:NormalizeKey(key)
    local normalized = normalizeKey(key)
    return normalized and DEFINITIONS[normalized] and normalized or nil
end

function ProfessionRegistry:IsKnown(key)
    return self:NormalizeKey(key) ~= nil
end

function ProfessionRegistry:Get(key)
    local normalized = self:NormalizeKey(key)
    return normalized and DEFINITIONS[normalized] or nil
end


function ProfessionRegistry:GetBySkillLineID(skillLineID)
    local id = tonumber(skillLineID)
    if not id then return nil end
    for _, key in ipairs(ORDERED_KEYS) do
        local def = DEFINITIONS[key]
        if tonumber(def.skillLineID) == id then return def end
    end
    return nil
end

function ProfessionRegistry:GetByProfessionEnum(professionEnum)
    local id = tonumber(professionEnum)
    if id == nil then return nil end
    for _, key in ipairs(ORDERED_KEYS) do
        local def = DEFINITIONS[key]
        if tonumber(def.professionEnum) == id then return def end
    end
    return nil
end

function ProfessionRegistry:GetProfessionEnum(key)
    local def = self:Get(key)
    return def and tonumber(def.professionEnum) or nil
end

function ProfessionRegistry:GetSkillLineID(key)
    local def = self:Get(key)
    if not def then return nil end
    local enum = tonumber(def.professionEnum)
    if enum ~= nil and C_TradeSkillUI and type(C_TradeSkillUI.GetProfessionSkillLineID) == "function" then
        local ok, value = pcall(C_TradeSkillUI.GetProfessionSkillLineID, enum)
        value = ok and tonumber(value) or nil
        if value and value > 0 then return value end
    end
    return tonumber(def.skillLineID)
end

function ProfessionRegistry:ResolveStableIdentity(skillLineID, professionEnum)
    local bySkill = self:GetBySkillLineID(skillLineID)
    local byEnum = self:GetByProfessionEnum(professionEnum)
    if bySkill and byEnum and bySkill.key ~= byEnum.key then
        return nil, "stable-identity-conflict"
    end
    local def = bySkill or byEnum
    return def and def.key or nil, def and nil or "stable-identity-unknown"
end

function ProfessionRegistry:GetDisplayName(key)
    local def = self:Get(key)
    return def and def.label or nil
end


function ProfessionRegistry:GetDisplayNameOrKey(key)
    local def = self:Get(key)
    if def and def.label then return def.label end
    local raw = tostring(key or ""):gsub("_", " ")
    if raw == "" then return "Unknown profession" end
    return raw
end

function ProfessionRegistry:GetStateKeys()
    -- State/checkpoint support is deliberately broader than production execution.
    -- Staged professions must be representable without becoming execution-eligible.
    return self:GetKeys({capability="checkpoint"})
end

function ProfessionRegistry:ResolveAvailability(key, capability, requireProduction)
    local normalized = self:NormalizeKey(key)
    if not normalized then
        return {known=false, key=nil, state="unsupported-profession", terminalReason="UNSUPPORTED_PROFESSION"}
    end
    local def = DEFINITIONS[normalized]
    -- Maturity is evaluated before a production-only capability. A known staged
    -- profession must report NOT_PRODUCTION_ENABLED instead of looking like an
    -- unsupported/unknown execution domain. This keeps identity and maturity
    -- orthogonal while still allowing production professions to fail on a
    -- genuinely unsupported capability.
    if requireProduction and not (def.maturity and def.maturity.production) then
        return {known=true, key=normalized, definition=def, state="not-production-enabled", terminalReason="NOT_PRODUCTION_ENABLED"}
    end
    if capability and not (def.capabilities and def.capabilities[capability]) then
        return {known=true, key=normalized, definition=def, state="unsupported-capability", terminalReason="UNSUPPORTED_CAPABILITY"}
    end
    return {known=true, key=normalized, definition=def, state="available", terminalReason=nil}
end

function ProfessionRegistry:BuildStateEnvelope(key, options)
    options = type(options)=="table" and options or {}
    local normalized = self:NormalizeKey(key)
    if not normalized then return nil, "UNSUPPORTED_PROFESSION" end
    local def = DEFINITIONS[normalized]
    local strategy = options.strategyKey
    if strategy ~= nil and not self:HasStrategy(normalized, strategy) then return nil, "UNSUPPORTED_STRATEGY" end
    return {
        contract = self.stateEnvelopeContract,
        professionKey = normalized,
        professionLabel = def.label,
        category = def.category,
        strategyKey = strategy,
        skill = tonumber(options.skill),
        stage = options.stage,
        routeRef = options.routeRef,
        checkpoint = options.checkpoint,
        payload = type(options.payload)=="table" and options.payload or {},
        productionEnabled = def.maturity and def.maturity.production == true or false,
    }
end

function ProfessionRegistry:ValidateStateEnvelope(envelope)
    if type(envelope)~="table" or envelope.contract~=self.stateEnvelopeContract then return false, "invalid-contract" end
    local key=self:NormalizeKey(envelope.professionKey)
    if not key then return false, "unsupported-profession" end
    local def=DEFINITIONS[key]
    -- Immutable registry-derived fields must not be trusted merely because the
    -- caller supplied a valid envelope contract and profession key.
    if envelope.professionKey~=key or envelope.professionLabel~=def.label
        or envelope.category~=def.category
        or type(envelope.productionEnabled)~="boolean"
        or envelope.productionEnabled~=(def.maturity and def.maturity.production==true or false) then
        return false, "registry-identity-or-maturity-mismatch"
    end
    if not envelope.productionEnabled and envelope.stage=="production-enabled" then
        return false, "unauthorized-production-stage"
    end
    if envelope.strategyKey and not self:HasStrategy(key,envelope.strategyKey) then return false, "unsupported-strategy" end
    if type(envelope.payload)~="table" then return false, "invalid-payload" end
    return true, nil
end

function ProfessionRegistry:GetOrder(key)
    local def = self:Get(key)
    return def and tonumber(def.order) or 9999
end

function ProfessionRegistry:GetKeys(options)
    options = type(options) == "table" and options or {}
    local out = {}
    for _, key in ipairs(ORDERED_KEYS) do
        local def = DEFINITIONS[key]
        local include = true
        if options.category and def.category ~= options.category then include = false end
        if options.researchEnabled ~= nil and (def.maturity.research and true or false) ~= (options.researchEnabled and true or false) then include = false end
        if options.productionEnabled ~= nil and (def.maturity.production and true or false) ~= (options.productionEnabled and true or false) then include = false end
        if options.capability and not def.capabilities[options.capability] then include = false end
        if options.strategy then
            local found = false
            for _, strategy in ipairs(def.progressionStrategies or {}) do if strategy == options.strategy then found = true; break end end
            if not found then include = false end
        end
        if include then out[#out + 1] = key end
    end
    return out
end

-- P0-164: Generic workflow participation is based on a declared functional
-- capability, never the release maturity of a particular static dataset.
-- This is NOT native crafting approval. Production-only consumers continue
-- to use GetProductionKeys and the original dataset/ledger/policy gates.
function ProfessionRegistry:GetWorkflowKeys(capability)
    return self:GetKeys({capability=capability or "executionFlow"})
end

function ProfessionRegistry:IsWorkflowEnabled(key, capability)
    return self:HasCapability(key, capability or "executionFlow")
end

function ProfessionRegistry:ResolveWorkflowAvailability(key, capability)
    return self:ResolveAvailability(key, capability or "executionFlow", false)
end

function ProfessionRegistry:GetProductionKeys(capability)
    return self:GetKeys({productionEnabled=true, capability=capability})
end

function ProfessionRegistry:IsProductionEnabled(key)
    local def = self:Get(key)
    return def and def.maturity and def.maturity.production == true or false
end

function ProfessionRegistry:IsResearchEnabled(key)
    local def = self:Get(key)
    return def and def.maturity and def.maturity.research == true or false
end

function ProfessionRegistry:HasCapability(key, capability)
    local def = self:Get(key)
    return def and def.capabilities and def.capabilities[tostring(capability or "")] == true or false
end

function ProfessionRegistry:HasStrategy(key, strategy)
    local def = self:Get(key)
    if not def then return false end
    for _, value in ipairs(def.progressionStrategies or {}) do
        if value == strategy then return true end
    end
    return false
end

function ProfessionRegistry:OrderKeys(keys)
    local unique, out = {}, {}
    if type(keys) == "table" then
        for k, value in pairs(keys) do
            local candidate = type(k) == "number" and value or k
            local normalized = self:NormalizeKey(candidate)
            if normalized and not unique[normalized] then unique[normalized]=true; out[#out+1]=normalized end
        end
    end
    table.sort(out, function(a,b)
        local ar, br = self:GetOrder(a), self:GetOrder(b)
        if ar ~= br then return ar < br end
        return tostring(a) < tostring(b)
    end)
    return out
end

function ProfessionRegistry:Validate()
    local errors = {}
    local seenOrder = {}
    local seenEnum = {}
    local seenSkillLine = {}
    for _, key in ipairs(ORDERED_KEYS) do
        local def = DEFINITIONS[key]
        if not def then errors[#errors+1] = "missing-definition:"..tostring(key) else
            if def.key ~= key then errors[#errors+1] = "key-mismatch:"..tostring(key) end
            if def.category ~= "PRIMARY" and def.category ~= "SECONDARY" then errors[#errors+1] = "invalid-category:"..tostring(key) end
            if type(def.label) ~= "string" or def.label == "" then errors[#errors+1] = "missing-label:"..tostring(key) end
            if seenOrder[def.order] then errors[#errors+1] = "duplicate-order:"..tostring(def.order) end
            seenOrder[def.order] = true
            local professionEnum = tonumber(def.professionEnum)
            local skillLineID = tonumber(def.skillLineID)
            if professionEnum == nil then errors[#errors+1] = "missing-profession-enum:"..tostring(key)
            elseif seenEnum[professionEnum] then errors[#errors+1] = "duplicate-profession-enum:"..tostring(professionEnum)
            else seenEnum[professionEnum] = key end
            if not skillLineID or skillLineID <= 0 then errors[#errors+1] = "missing-skill-line-id:"..tostring(key)
            elseif seenSkillLine[skillLineID] then errors[#errors+1] = "duplicate-skill-line-id:"..tostring(skillLineID)
            else seenSkillLine[skillLineID] = key end
            if type(def.progressionStrategies) ~= "table" or #def.progressionStrategies == 0 then errors[#errors+1] = "missing-strategy:"..tostring(key) end
            for _, strategy in ipairs(def.progressionStrategies or {}) do
                if not STRATEGIES[strategy] then errors[#errors+1] = "unknown-strategy:"..tostring(key)..":"..tostring(strategy) end
            end
            if type(def.capabilities) ~= "table" then errors[#errors+1] = "missing-capabilities:"..tostring(key) end
            if type(def.maturity) ~= "table" then errors[#errors+1] = "missing-maturity:"..tostring(key) end
        end
    end
    if #ORDERED_KEYS ~= 12 then errors[#errors+1] = "profession-count:"..tostring(#ORDERED_KEYS) end
    return errors
end


function ProfessionRegistry:IsProductionCandidate(key)
    local def = self:Get(key)
    return def and def.maturity and def.maturity.candidate == true or false
end

function ProfessionRegistry:GetSummary()
    local production = self:GetProductionKeys()
    local primary = self:GetKeys({category="PRIMARY"})
    local secondary = self:GetKeys({category="SECONDARY"})
    return string.format("Profession Registry: %d total · %d primary · %d secondary · %d production-enabled", #ORDERED_KEYS, #primary, #secondary, #production)
end

JLP:RegisterModule("ProfessionRegistry", ProfessionRegistry)
