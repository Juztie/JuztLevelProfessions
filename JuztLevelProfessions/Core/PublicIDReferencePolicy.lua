local _, JLP = ...

-- Build-independent, read-only data identity assessment. A published Forever
-- reference may establish an ID match without a client observation. It never
-- asserts recipe learned, native availability or permission to dispatch.
local Policy = {
    contract = "wowhead-reference-id-validation-v1",
    nativeDispatchAllowed = false,
    persisted = false,
}

local function positiveID(value)
    local n = tonumber(value)
    return n and n > 0 and math.floor(n) == n
end

local function ingredientMap(items, indexed)
    local out, count = {}, 0
    if type(items) ~= "table" then return nil end
    for _, item in ipairs(items) do
        local id = indexed and item[1] or item.itemID
        local quantity = indexed and item[2] or item.quantity
        id, quantity = tonumber(id), tonumber(quantity)
        if not positiveID(id) or not positiveID(quantity) or out[id] then return nil end
        out[id] = quantity
        count = count + 1
    end
    return out, count
end

local function exactMaterials(step, row)
    local actual, n = ingredientMap(step.materials, false)
    local expected, m = ingredientMap(row.materials, true)
    if not actual or not expected or n ~= m then return false end
    for id, count in pairs(expected) do
        if actual[id] ~= count then return false end
    end
    return true
end

function Policy:AssessProfession(key)
    local reg = JLP:GetModule("ProfessionRegistry")
    local datasetProvider = JLP:GetModule("ProfessionDatasetProvider")
    local def = reg and reg:Get(key) or nil
    if not def then return {state="UNREGISTERED",accepted=false} end
    local skill = tonumber(def.skillLineID)
    local skillURL = skill and ("https://www.wowhead.com/forever/skill="..skill) or nil
    local evidenceRoot = JLP.data and JLP.data.currentBuildEvidence
    local dataset = datasetProvider and datasetProvider:GetRegisteredDataset(def.key) or nil
    local ev = evidenceRoot and evidenceRoot.professions and evidenceRoot.professions[def.key]
    local rows = ev and ev.rows or {}
    local byID = {}
    for _, step in ipairs(dataset and (dataset.route or dataset.steps) or {}) do
        if positiveID(step.recipeID) and not byID[tonumber(step.recipeID)] then
            byID[tonumber(step.recipeID)] = step
        end
    end
    local match, errors, used = 0, {}, {}
    local fingerprintParts = {}
    for index, row in ipairs(rows) do
        local id = tonumber(row.recipeID)
        local source = evidenceRoot and evidenceRoot.sources and evidenceRoot.sources[row.sourceKey]
        local url = source and source.url
        local step = byID[id]
        local acceptable = positiveID(id) and not used[id] and step and
            type(url)=="string" and url:match("^https://www%.wowhead%.com/forever/") and
            tonumber(ev.build)==tonumber(row.capturedBuild) and
            exactMaterials(step,row)
        if acceptable and row.requiredToolItemID ~= nil then
            acceptable = positiveID(row.requiredToolItemID) and type(step.requiredTool)=="table" and
                tonumber(step.requiredTool.itemID)==tonumber(row.requiredToolItemID)
        end
        if acceptable and row.targetSlot ~= nil then
            acceptable = type(row.targetSlot)=="string" and
                tostring(step.targetSlot or ""):upper()==row.targetSlot:upper()
        end
        if acceptable then
            match = match + 1
            local ingredients = {}
            for ingredientID, amount in pairs(ingredientMap(row.materials, true) or {}) do
                ingredients[#ingredients+1] = tostring(ingredientID).."x"..tostring(amount)
            end
            table.sort(ingredients)
            fingerprintParts[#fingerprintParts+1] = tostring(id)..":"..table.concat(ingredients,",")..":"..
                tostring(row.requiredToolItemID or "-")..":"..tostring(row.targetSlot or "-")
        else errors[#errors+1]="reference-row-mismatch:"..index end
        if id then used[id]=true end
    end
    local routeCount = dataset and #(dataset.route or dataset.steps or {}) or 0
    table.sort(fingerprintParts)
    local accepted = ev ~= nil and ev.publicComplete == true and match == routeCount and
        #rows == routeCount and routeCount > 0 and #errors == 0
    return {
        contract=self.contract, professionKey=def.key, skillLineID=skill,
        skillReference=skillURL, state=accepted and "WOWHEAD_ID_MATCH_ACCEPTED" or
            (ev and "REFERENCE_INCOMPLETE" or "NO_RECIPE_REFERENCE_DATA"),
        accepted=accepted, matchedRecipes=match, routeCount=routeCount,
        referenceBuild=ev and ev.build or nil, errors=errors,
        referenceFingerprint=accepted and ("wowhead-forever-v1:"..tostring(ev.build)..":"..table.concat(fingerprintParts,"|")) or nil,
         nativeDispatchAllowed=false, persisted=false,
    }
end

-- Skill line identity can be accepted from the registry's exact Wowhead
-- profession URL without requiring in-client observation.
function Policy:AssessSkillLine(key, id)
    local reg = JLP:GetModule("ProfessionRegistry")
    local def = reg and reg:Get(key)
    local match = def and positiveID(id) and tonumber(def.skillLineID)==tonumber(id) or false
    return {accepted=match, state=match and "WOWHEAD_SKILL_ID_MATCH" or "SKILL_ID_MISMATCH",
        reference=match and ("https://www.wowhead.com/forever/skill="..tostring(id)) or nil,
         nativeDispatchAllowed=false}
end

JLP:RegisterModule("PublicIDReferencePolicy", Policy)
