local _, JLP = ...

-- Verified recipe-difficulty resolver for Forever profession telemetry.
-- Difficulty is guidance/telemetry evidence only: if the client does not expose
-- a recognized value, callers receive nil and must fall back to skill-band data.
local RecipeDifficulty = {
    contract = "verified-recipe-difficulty-v1",
}

local RELATIVE = {
    [0] = { token="orange", apiName="Optimal", label="Orange" },
    [1] = { token="yellow", apiName="Medium", label="Yellow" },
    [2] = { token="green",  apiName="Easy", label="Green" },
    [3] = { token="gray",   apiName="Trivial", label="Gray" },
}

local TEXT = {
    optimal="orange", orange="orange",
    medium="yellow", yellow="yellow",
    easy="green", green="green",
    trivial="gray", gray="gray", grey="gray",
}

local LABEL = { orange="Orange", yellow="Yellow", green="Green", gray="Gray" }
local API_NAME = { orange="Optimal", yellow="Medium", green="Easy", gray="Trivial" }

local function normalizeText(value)
    value = string.lower(tostring(value or ""))
    value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return value
end

local function stamp()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

function RecipeDifficulty:Normalize(value)
    if value == nil then return nil end
    local numeric = tonumber(value)
    if numeric ~= nil and numeric==numeric and numeric>=0 and numeric<=3 and
        numeric==math.floor(numeric) and RELATIVE[numeric] then
        local row = RELATIVE[numeric]
        return {
            token = row.token,
            label = row.label,
            apiName = row.apiName,
            relativeDifficulty = numeric,
        }
    end
    local token = TEXT[normalizeText(value)]
    if not token then return nil end
    local relativeDifficulty
    for id, row in pairs(RELATIVE) do if row.token == token then relativeDifficulty = id break end end
    return {
        token = token,
        label = LABEL[token],
        apiName = API_NAME[token],
        relativeDifficulty = relativeDifficulty,
    }
end

local function fromInfo(self, info, source)
    if type(info) ~= "table" then return nil end
    -- relativeDifficulty is the authoritative modern field.  The compatibility
    -- fields are accepted only when their value maps to the same closed enum.
    local candidates = {
        { value=info.relativeDifficulty, field="relativeDifficulty" },
        { value=info.difficulty, field="difficulty" },
        { value=info.difficultyID, field="difficultyID" },
        { value=info.skillType, field="skillType" },
    }
    for _, candidate in ipairs(candidates) do
        local normalized = self:Normalize(candidate.value)
        if normalized then
            normalized.source = tostring(source or "recipe-info") .. "." .. candidate.field
            normalized.confidence = "verified"
            normalized.canSkillUp = info.canSkillUp
            normalized.maxTrivialLevel = tonumber(info.maxTrivialLevel)
            normalized.observedAt = stamp()
            return normalized
        end
    end
    return nil
end

local function legacyDifficulty(self, recipeID, recipeName)
    if normalizeText(recipeName) == "" or type(GetNumTradeSkills) ~= "function" or type(GetTradeSkillInfo) ~= "function" then return nil end
    -- Name-only legacy rows are not proof of a specific RecipeID. When an
    -- identity is requested, a legacy recipe link must independently match.
    if recipeID and type(GetTradeSkillRecipeLink) ~= "function" then return nil end
    local ok, count = pcall(GetNumTradeSkills)
    if not ok or not tonumber(count) then return nil end
    local wanted = normalizeText(recipeName)
    for index = 1, math.max(0, math.floor(tonumber(count) or 0)) do
        local rowOK, name, skillType = pcall(GetTradeSkillInfo, index)
        if rowOK and normalizeText(name) == wanted then
            local exact = recipeID == nil
            if recipeID then
                local linkOK, link = pcall(GetTradeSkillRecipeLink, index)
                if linkOK and type(link)=="string" then
                    local kind, linkedID=link:match("|H([%a]+):(%d+)")
                    if not linkedID then kind,linkedID=link:match("^([%a]+):(%d+)") end
                    exact=(kind=="enchant" or kind=="spell") and tonumber(linkedID)==recipeID
                end
            end
            if exact then
            local normalized = self:Normalize(skillType)
            if normalized then
                normalized.source = "GetTradeSkillInfo.skillType"
                normalized.confidence = recipeID and "verified-recipe-link" or "advisory-name-only"
                normalized.observedAt = stamp()
                return normalized
            end
            end
        end
    end
    return nil
end

function RecipeDifficulty:Get(recipeID, recipeName)
    recipeID = tonumber(recipeID)
    if recipeID and type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.GetRecipeInfo) == "function" then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok then
            local result = fromInfo(self, info, "C_TradeSkillUI.GetRecipeInfo")
            if result then
                result.recipeID = recipeID
                result.recipeName = (type(info) == "table" and info.name) or recipeName
                return result
            end
        end
    end
    local legacy = legacyDifficulty(self, recipeID, recipeName)
    if legacy then
        legacy.recipeID = recipeID
        legacy.recipeName = recipeName
        return legacy
    end
    return nil
end

function RecipeDifficulty:GetForRecipe(key, recipeID, recipeName)
    if not tonumber(recipeID) and recipeName then
        local crafting = JLP:GetModule("Crafting")
        if crafting and crafting.ResolveRecipeID then recipeID = crafting:ResolveRecipeID(key, recipeName) end
    end
    return self:Get(recipeID, recipeName)
end

-- P0.2A: independent advisory skill gate. The 70450 SkillLineAbility
-- MinSkillLineRank and yellow/grey difficulty bounds are NOT attestations of
-- the actual minimum skill to learn/use a recipe. Never conflate these fields.
-- Only a specifically qualified minimum requirement can exclude a route step.
local VERIFIED_MINIMUM={WOWHEAD_FOREVER=true,CURRENT_BUILD_VERIFIED=true}
local function positiveInteger(v)
    return type(v)=="number" and v>0 and v==math.floor(v) and v<math.huge
end
function RecipeDifficulty:AssessProgression(key,step,fromSkill,toSkill)
    local result={contract="recipe-skill-eligibility-v1",professionKey=key,
        recipeID=type(step)=="table" and step.recipeID or nil,
        status="MINIMUM_SKILL_UNVERIFIED",minimumSkill=nil,
        minimumSkillEvidence="UNKNOWN",eligibleFromSkill=nil,
        progressionAllowed=true,progressionQualified=false,
        learnedState="UNKNOWN",rankState="UNKNOWN",yieldState="UNKNOWN",
        difficultyState="NOT_A_MINIMUM_SKILL_REQUIREMENT",
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false}
    if type(step)~="table" then result.status="STEP_UNAVAILABLE";result.progressionAllowed=false;return result end
    local minimum,authority=step.requiredSkill,step.requiredSkillAuthority
    -- An exact qualified Forever recipe reference can supply a requirement
    -- if the route step itself lacks an independently qualified minimum.
    if not VERIFIED_MINIMUM[authority] then
        minimum=nil
        local reference=JLP:GetModule("ForeverRecipeAuthority")
        if reference and type(reference.GetReference)=="function" then
            local row=reference:GetReference(key,step.recipeID,step.recipe)
            if row and row.skillBasis=="WOWHEAD_FOREVER" then
                minimum=row.requiredSkill;authority="WOWHEAD_FOREVER"
            end
        end
    end
    if minimum~=nil and not positiveInteger(minimum) then
        result.status="INVALID_MINIMUM_SKILL_EVIDENCE"
        result.progressionAllowed=false
        return result
    end
    if minimum==nil then return result end
    result.minimumSkill=minimum
    result.minimumSkillEvidence=authority
    result.eligibleFromSkill=minimum
    local from=tonumber(fromSkill)
    local finish=tonumber(toSkill)
    if minimum>=300 then
        result.status="MINIMUM_SKILL_300_OR_HIGHER"
        result.progressionAllowed=false
    elseif finish and finish<=minimum then
        result.status="MINIMUM_NOT_REACHED_IN_BAND"
        result.progressionAllowed=false
    elseif from and from<minimum then
        result.status="BAND_START_BELOW_REQUIRED_SKILL"
        result.progressionAllowed=false
    else
        result.status="MINIMUM_SKILL_SOURCE_QUALIFIED"
        result.progressionQualified=true -- minimum only; NOT learned/rank/yield/access
    end
    return result
end

function RecipeDifficulty:Format(value)
    local row = type(value) == "table" and value or self:Normalize(value)
    return row and row.label or "Unknown"
end

JLP:RegisterModule("RecipeDifficulty", RecipeDifficulty)
