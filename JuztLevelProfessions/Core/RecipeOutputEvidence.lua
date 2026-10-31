local _, JLP = ...

-- Build-aware recipe output-yield evidence. External Forever references can
-- resolve dependency quantities, but live current-build observations are the
-- primary authority and can corroborate or invalidate those references.
local RecipeOutputEvidence = {
    contract = "build-aware-recipe-output-yield-evidence-v1",
    storeSchema = 1,
    plannerEligible = false,
}

local function normalize(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[%c%p%s]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

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
local function characterKey()
    local identity = JLP:GetModule("CharacterIdentity")
    if identity and identity.GetKey then return identity:GetKey() end
    return "UnknownRealm:UnknownCharacter"
end

local function epochNow()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function referenceRoot()
    return JLP.data and JLP.data.recipeOutputYields or nil
end

local function referenceBuildState()
    local root = referenceRoot()
    local metadata = root and root.sourceMetadata or nil
    local provenance = currentBuildProvenance()
    local capturedBuild = metadata and tonumber(metadata.capturedAgainstBuild) or nil
    local currentBuild = provenance and tonumber(provenance.build) or nil
    -- Missing provenance is UNKNOWN, never proof of same-build authority.
    local matches = capturedBuild ~= nil and currentBuild ~= nil and currentBuild == capturedBuild
    return {
        capturedBuild = capturedBuild,
        currentBuild = currentBuild,
        matches = matches and true or false,
        provenance = provenance,
    }
end

local function getReference(recipeName, recipeID)
    local root = referenceRoot()
    if not root then return nil end
    recipeID = tonumber(recipeID)
    if recipeID then
        for _, row in pairs(root.recipes or {}) do
            if tonumber(row.spellID) == recipeID then return row end
        end
        -- An explicit missing SpellID is not permission to reuse a
        -- same-named output contract from another recipe.
        return nil
    end
    local wanted = normalize(recipeName)
    if wanted == "" then return nil end
    for name, row in pairs(root.recipes or {}) do
        if normalize(name) == wanted or normalize(row.recipe) == wanted then return row end
    end
    return nil
end

local function getStore(create)
    if not JLP.DB then return nil end
    JLP.DB.account = JLP.DB.account or {}
    local root = JLP.DB.account.recipeOutputEvidence
    if type(root) ~= "table" then
        if not create then return nil end
        root = { schema=RecipeOutputEvidence.storeSchema, characters={} }
        JLP.DB.account.recipeOutputEvidence = root
    end
    root.schema = RecipeOutputEvidence.storeSchema
    root.characters = type(root.characters) == "table" and root.characters or {}
    local key = characterKey()
    local character = root.characters[key]
    if type(character) ~= "table" then
        if not create then return root, nil, key end
        character = { builds={} }
        root.characters[key] = character
    end
    character.builds = type(character.builds) == "table" and character.builds or {}
    return root, character, key
end

local function getBuildStore(create)
    local root, character, key = getStore(create)
    if not root or not character then return root, nil, key, nil end
    local provenance = currentBuildProvenance()
    -- "unknown" tokens are not qualified live sessions. Never reuse or
    -- persist live evidence under a fabricated cross-build cache bucket.
    if not provenance or provenance.quality ~= "LIVE" or
       type(provenance.build) ~= "number" or provenance.build <= 0 then
        return root, nil, key, provenance
    end
    local actual = provenance.build
    if actual ~= math.floor(actual) or actual == math.huge or
       actual > 9007199254740991 then return root, nil end
    local expectedToken = string.format("forever:%s|interface:%s",
        tostring(actual), tostring(provenance.interface or "unknown"))
    local token = provenance.token
    if token ~= expectedToken then return root, nil, key, provenance end
    local build = character.builds[token]
    if type(build) ~= "table" then
        if not create then return root, nil, key, provenance end
        build = { provenance=provenance, recipes={} }
        character.builds[token] = build
    end
    -- P0/F1: the lookup key alone cannot establish the provenance of a
    -- persisted SavedVariables bucket. Do not promote legacy/contradictory
    -- buckets into LIVE evidence, and never silently rewrite their receipt.
    local stored = build.provenance
    if type(stored) ~= "table" or stored.quality ~= "LIVE" or
       stored.build ~= actual or stored.token ~= token or
       stored.interface ~= provenance.interface or
       stored.source ~= provenance.source then
        return root, nil, key, provenance
    end
    build.recipes = type(build.recipes) == "table" and build.recipes or {}
    return root, build, key, provenance
end

local function outputNameFromResult(data, fallback)
    if type(data) ~= "table" then return fallback end
    if data.outputName and data.outputName ~= "" then return tostring(data.outputName) end
    local link = data.hyperlink or data.itemLink
    if type(link) == "string" then
        local name = link:match("%[(.-)%]")
        if name and name ~= "" then return name end
    end
    local itemID = tonumber(data.itemID)
    if itemID and type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
        local ok, name = pcall(C_Item.GetItemInfo, itemID)
        if ok and name and name ~= "" then return name end
    end
    if itemID and type(GetItemInfo) == "function" then
        local ok, name = pcall(GetItemInfo, itemID)
        if ok and name and name ~= "" then return name end
    end
    return fallback
end

function RecipeOutputEvidence:ObserveCraftResult(payload)
    if type(payload) ~= "table" then return false, "invalid-payload" end
    -- Never train the live yield catalogue from an unconfirmed or aggregate
    -- TRADE_SKILL_ITEM_CRAFTED_RESULT. This gate is independent of client build.
    if payload.qualifiedOutputReceipt~=true or payload.confirmedCraftCount~=1 or
       type(payload.ledgerID)~="string" or payload.ledgerID=="" then
        return false,"output-receipt-not-transaction-qualified"
    end
    local recipeName = payload.recipeName
    local recipeID = tonumber(payload.recipeID)
    local data = payload.result or payload.data or payload
    local quantity = data and data.quantity
    local itemID = data and data.itemID
    if not recipeName or recipeName == "" or type(quantity)~="number" or
        quantity<=0 or quantity~=math.floor(quantity) or quantity>=9007199254740991 or
        type(itemID)~="number" or itemID<=0 or itemID~=math.floor(itemID) then
        return false, "invalid-result-item-or-quantity"
    end

    local _, build, _, provenance = getBuildStore(true)
    if not build or not provenance then return false, "build-unavailable" end
    -- operationID=0 is a placeholder in observed Forever result payloads.
    -- Never promote an anonymous result to a verified live yield sample.
    local operationID = data and data.operationID
    if operationID==nil or tostring(operationID)=="" or tostring(operationID)=="0" then operationID=nil end
    local itemGUID = data and data.itemGUID
    if itemGUID==nil or tostring(itemGUID)=="" or tostring(itemGUID)=="0" then itemGUID=nil end
    if operationID==nil and itemGUID==nil then return false, "result-identity-unverified" end
    local key = normalize(recipeName)
    if key == "" then return false, "recipe-unavailable" end
    local row = build.recipes[key]
    if type(row) ~= "table" then
        row = {
            recipeName = tostring(recipeName),
            recipeID = recipeID,
            outputItemID = tonumber(data.itemID),
            outputName = outputNameFromResult(data, recipeName),
            samples = 0,
            min = nil,
            max = nil,
            counts = {},
            firstObservedAt = epochNow(),
        }
        build.recipes[key] = row
    end
    -- A different output item for the same recipe is not a second sample of
    -- the same per-item yield. Preserve existing history and flag the drift.
    if row.outputItemID and tonumber(row.outputItemID)~=tonumber(itemID) then
        row.outputIdentityConflict=true
        return false,"output-item-identity-conflict"
    end
    if row.recipeID and recipeID and tonumber(row.recipeID)~=recipeID then
        return false,"recipe-identity-conflict"
    end
    row.recipeID = row.recipeID or recipeID
    row.outputItemID = row.outputItemID or tonumber(data.itemID)
    row.outputName = row.outputName or outputNameFromResult(data, recipeName)
    row.evidenceIndex = type(row.evidenceIndex) == "table" and row.evidenceIndex or {}
    local evidenceID = operationID or itemGUID
    if evidenceID ~= nil and evidenceID ~= "" then
        local evidenceKey = tostring(evidenceID)
        if row.evidenceIndex[evidenceKey] then return false, "duplicate-result" end
        row.evidenceIndex[evidenceKey] = true
    end
    row.samples = math.max(0, tonumber(row.samples) or 0) + 1
    row.min = row.min and math.min(row.min, quantity) or quantity
    row.max = row.max and math.max(row.max, quantity) or quantity
    row.counts = type(row.counts) == "table" and row.counts or {}
    local quantityKey = tostring(quantity)
    row.counts[quantityKey] = math.max(0, tonumber(row.counts[quantityKey]) or 0) + 1
    row.lastQuantity = quantity
    row.lastObservedAt = epochNow()
    row.buildToken = provenance.token
    row.build = provenance.build
    row.interface = provenance.interface
    row.source = "live-crafted-result"
    row.confidence = row.samples >= 2 and row.min == row.max and "verified" or "observed"
    local graph = JLP:GetModule("ProfessionDependencyGraph")
    if graph and graph.Invalidate then graph:Invalidate() end
    local supplemental = JLP:GetModule("ResearchSupplementPlanner")
    if supplemental and supplemental.Invalidate then supplemental:Invalidate() end
    -- ResearchCandidateVerifier intentionally rebuilds from current graph,
    -- supplemental and recipe-knowledge state and therefore has no stale cache
    -- to invalidate here.
    if JLP.EventBus and JLP.EventBus.Emit then JLP.EventBus:Emit("RECIPE_OUTPUT_EVIDENCE_UPDATED", row) end
    return true, row
end

function RecipeOutputEvidence:GetLive(recipeName, recipeID)
    local _, build = getBuildStore(false)
    if not build then return nil end
    recipeID = tonumber(recipeID)
    if recipeID then
        for _, row in pairs(build.recipes or {}) do
            if tonumber(row.recipeID) == recipeID then return row end
        end
        -- A name-only sample (or one for a different SpellID) cannot
        -- qualify the explicitly requested recipe in this session/build.
        return nil
    end
    return build.recipes and build.recipes[normalize(recipeName)] or nil
end

function RecipeOutputEvidence:GetReference(recipeName, recipeID)
    return getReference(recipeName, recipeID)
end

-- Current open-panel schematic: volatile, non-persisted and read-only.
-- A stable panel/recipe and TWO identical schematic reads are prerequisites;
-- this never substitutes for ledger, protected-click or native dispatch gates.
local function exactQuantity(value)
    return type(value)=="number" and value==value and value>=1 and
        value<2147483647 and value==math.floor(value)
end
function RecipeOutputEvidence:ObserveCurrentSchematic(recipeID,expectedProfessionKey)
    local out={contract="volatile-schematic-output-203",status="UNKNOWN",
        recipeID=tonumber(recipeID),readOnly=true,plannerEligible=false,
        nativeDispatchAllowed=false,executionEligible=false,
        reason="LIVE_SCHEMATIC_UNAVAILABLE"}
    if not exactQuantity(out.recipeID) then
        out.status="INVALID";out.reason="RECIPE_ID_INVALID";return out
    end
    local prof=JLP:GetModule("ProfessionAPI")
    local api=C_TradeSkillUI
    if not prof or type(prof.GetReadOnlyRecipeObservation)~="function" or
       type(api)~="table" or type(api.GetRecipeSchematic)~="function" then
        return out
    end
    local fn=api.GetRecipeSchematic
    local before=prof:GetReadOnlyRecipeObservation(out.recipeID,expectedProfessionKey)
    if not before or before.readOnlyObserved~=true or before.recipeID~=out.recipeID then
        out.reason=before and before.reason or "RECIPE_NOT_OBSERVED";return out
    end
    local function capture()
        if C_TradeSkillUI~=api or api.GetRecipeSchematic~=fn then
            return nil,"SCHEMATIC_PROVIDER_CHANGED"
        end
        local ok,result=pcall(fn,out.recipeID,false)
        if not ok then return nil,"SCHEMATIC_API_EXCEPTION" end
        if type(result)~="table" then return nil,"SCHEMATIC_NOT_RETURNED" end
        local id,minValue,maxValue=result.outputItemID,result.quantityMin,result.quantityMax
        if id==nil or minValue==nil or maxValue==nil then
            return nil,"SCHEMATIC_OUTPUT_FIELDS_UNKNOWN"
        end
        if not exactQuantity(id) or not exactQuantity(minValue) or
           not exactQuantity(maxValue) or minValue>maxValue then
            return nil,"SCHEMATIC_OUTPUT_FIELDS_INVALID"
        end
        return {itemID=id,min=minValue,max=maxValue},nil
    end
    local first,why=capture()
    if not first then out.reason=why;return out end
    local second,why2=capture()
    if not second then out.reason=why2;return out end
    if first.itemID~=second.itemID or first.min~=second.min or first.max~=second.max then
        out.status="CONFLICT";out.reason="SCHEMATIC_OUTPUT_CHANGED";return out
    end
    local after=prof:GetReadOnlyRecipeObservation(out.recipeID,expectedProfessionKey)
    if not after or after.readOnlyObserved~=true or
       after.panelToken~=before.panelToken or
       after.professionKey~=before.professionKey or
       after.learned~=before.learned or after.name~=before.name or
       C_TradeSkillUI~=api or api.GetRecipeSchematic~=fn then
        out.status="CONFLICT";out.reason="SCHEMATIC_PANEL_CHANGED";return out
    end
    out.status=first.min==first.max and "OBSERVED_FIXED" or "OBSERVED_VARIABLE"
    out.reason="CURRENT_PANEL_SCHEMATIC_READ_ONLY"
    out.recipeName=before.name;out.professionKey=before.professionKey
    out.learned=before.learned;out.outputItemID=first.itemID
    out.outputMin=first.min;out.outputMax=first.max
    out.panelToken=before.panelToken;out.readOnlyObserved=true
    return out
end

function RecipeOutputEvidence:Resolve(recipeName, recipeID)
    local reference = getReference(recipeName, recipeID)
    local live = self:GetLive(recipeName, recipeID)
    local referenceBuild = referenceBuildState()
    local out = {
        recipeName = recipeName,
        recipeID = tonumber(recipeID) or (reference and tonumber(reference.spellID)) or (live and tonumber(live.recipeID)),
        plannerEligible = false,
        dependencyQuantityEligible = false,
        external = reference,
        live = live,
        referenceCapturedBuild = referenceBuild.capturedBuild,
        currentBuild = referenceBuild.currentBuild,
        referenceBuildMatch = referenceBuild.matches,
        planningUsable = false,
        planningOnly = true,
        planningQuantity = nil,
    }

    -- Only an explicit exact SpellID can request current panel evidence.
    -- A caller asking about a different profession/closed panel gets UNKNOWN.
    -- A transient schematic neither modifies historical source rows nor grants
    -- a native action. A contradictory live ID/yield is NOT silently ignored.
    local schematic = recipeID and self:ObserveCurrentSchematic(recipeID) or nil
    -- Explicit product policy is expected output, never a receipt or skill-up.
    -- Preserve contradictory observations separately; require review rather
    -- than silently overriding this contract with a newer sample.
    if reference and reference.productFixedOutput==true then
        out.source=reference.source
        out.outputItemID=reference.outputItemID
        out.outputQuantity=reference.outputQuantity
        out.expectedOutputQuantity=reference.outputQuantity
        out.outputMin=reference.outputQuantity;out.outputMax=reference.outputQuantity
        out.fixed=true;out.liveVerified=false;out.nativeDispatchAllowed=false
        out.productFixedOutput=true;out.confidence="explicit-product-contract"
        local conflict=live and (live.outputIdentityConflict==true or
            (tonumber(live.outputItemID) and tonumber(live.outputItemID)~=out.outputItemID) or
            (tonumber(live.samples) or 0)>0 and
             (tonumber(live.min)~=out.outputQuantity or tonumber(live.max)~=out.outputQuantity))
        if schematic and schematic.readOnlyObserved==true then
            out.currentSchematic=schematic;out.readOnlyObserved=true
            conflict=conflict or schematic.outputItemID~=out.outputItemID or
                schematic.outputMin~=out.outputQuantity or schematic.outputMax~=out.outputQuantity
        elseif schematic and schematic.status=="CONFLICT" then conflict=true end
        if conflict then
            out.status="USER_FIXED_OUTPUT_CONFLICT_REVIEW_REQUIRED"
            out.productContractConflict=true;out.outputConflict=true
            out.confidence="conflict"
            return out
        end
        out.status="USER_FIXED_OUTPUT_REFERENCE"
        -- An observed unlearned recipe remains unavailable. Static output
        -- qualification alone does not prove learning or grant a native action.
        out.planningUsable=not (schematic and schematic.readOnlyObserved==true and schematic.learned~=true)
        out.planningQuantity=out.planningUsable and out.outputQuantity or nil
        out.dependencyQuantityEligible=out.planningUsable
        return out
    end
    if schematic and schematic.readOnlyObserved==true then
        out.currentSchematic={status=schematic.status,outputItemID=schematic.outputItemID,
            outputMin=schematic.outputMin,outputMax=schematic.outputMax,
            learned=schematic.learned,readOnly=true,nativeDispatchAllowed=false}
        out.source="live-current-panel-schematic"
        out.outputItemID=schematic.outputItemID
        out.outputMin=schematic.outputMin;out.outputMax=schematic.outputMax
        out.fixed=schematic.status=="OBSERVED_FIXED"
        out.liveVerified=false;out.readOnlyObserved=true
        out.plannerEligible=false;out.nativeDispatchAllowed=false
        local identityConflict=reference and tonumber(reference.outputItemID) and
             tonumber(reference.outputItemID)~=schematic.outputItemID
        -- External yield rows often omit the numeric output ID. Never assume
        -- an identical quantity means the output item is also identical.
        local curated=JLP.data and JLP.data.foreverIntermediateOutputs
        if curated and type(curated.rows)=="table" then
            for _,r in ipairs(curated.rows) do
                if tonumber(r.recipeID)==out.recipeID and
                   (r.professionKey==schematic.professionKey or
                    schematic.professionKey==nil) and
                   tonumber(r.outputItemID)~=schematic.outputItemID then
                    identityConflict=true
                end
            end
        end
        local liveConflict=live and (live.outputIdentityConflict==true or
             (tonumber(live.outputItemID) and tonumber(live.outputItemID)~=schematic.outputItemID) or
             (tonumber(live.samples) or 0)>=2 and tonumber(live.min) and
              (tonumber(live.min)~=schematic.outputMin or tonumber(live.max)~=schematic.outputMax))
        local quantityConflict=reference and tonumber(reference.outputQuantity) and
             (tonumber(reference.outputQuantity)~=schematic.outputMin or
              tonumber(reference.outputQuantity)~=schematic.outputMax)
        if identityConflict or liveConflict or quantityConflict then
            out.status="live-schematic-reference-conflict"
            out.confidence="conflict";out.outputConflict=true
            out.dependencyQuantityEligible=false;out.planningUsable=false
            return out
        end
        if schematic.status=="OBSERVED_VARIABLE" then
            out.status="live-schematic-variable";out.confidence="observed-range"
            out.dependencyQuantityEligible=false;out.planningUsable=false
            return out
        end
        out.status=schematic.learned==true and "live-schematic-fixed-learned" or
             "live-schematic-fixed-unlearned"
        out.confidence="volatile-current-panel"
        out.outputQuantity=schematic.outputMin
        out.planningUsable=schematic.learned==true
        out.planningQuantity=out.planningUsable and schematic.outputMin or nil
        out.dependencyQuantityEligible=schematic.learned==true
        out.planningOnly=true
        return out
    end

    if live then
        if live.outputIdentityConflict==true then
            out.status="live-output-item-identity-conflict"
            out.source="live-current-build"
            out.outputItemConflict=true
            out.confidence="conflict"
            return out
        end
        local samples = math.max(0, tonumber(live.samples) or 0)
        local minValue = tonumber(live.min)
        local maxValue = tonumber(live.max)
        local fixedLive = samples >= 2 and minValue and maxValue and minValue == maxValue and
            live.outputIdentityConflict~=true
        local referenceQuantity = reference and tonumber(reference.outputQuantity) or nil
        if fixedLive then
            out.outputQuantity = minValue
            out.outputMin = minValue
            out.outputMax = maxValue
            out.fixed = true
            out.dependencyQuantityEligible = true
            out.planningUsable = true
            out.planningOnly = false
            out.planningQuantity = minValue
            out.liveVerified = true
            if referenceQuantity and referenceQuantity ~= minValue then
                out.status = "live-current-build-override"
                out.source = "live-current-build"
                out.referenceConflict = true
            else
                out.status = referenceQuantity and "live-current-build-verified+external" or "live-current-build-verified"
                out.source = "live-current-build"
            end
            out.confidence = "verified"
            return out
        end

        if samples >= 1 and minValue and maxValue and minValue ~= maxValue then
            out.status = "live-current-build-variable"
            out.source = "live-current-build"
            out.outputMin = minValue
            out.outputMax = maxValue
            out.fixed = false
            out.liveVerified = true
            out.confidence = "variable"
            -- A lower bound is informative, but variable-output recipes are not
            -- promoted to fixed dependency quantities without a distribution.
            return out
        end

        if samples >= 1 and minValue and referenceQuantity then
            if minValue == referenceQuantity and referenceBuild.matches then
                out.status = "live-current-build-corroborated"
                out.source = "live+external"
                out.outputQuantity = referenceQuantity
                out.outputMin = referenceQuantity
                out.outputMax = referenceQuantity
                out.fixed = true
                out.dependencyQuantityEligible = true
                out.planningUsable = true
                out.planningOnly = false
                out.planningQuantity = referenceQuantity
                out.liveVerified = false
                out.confidence = "corroborated"
                return out
            end
            out.status = minValue == referenceQuantity and
                "live-crossbuild-reference-not-yet-qualified" or "live-reference-conflict-learning"
            out.source = "live-current-build"
            out.referenceConflict = minValue ~= referenceQuantity
            out.outputMin = minValue
            out.outputMax = maxValue
            out.fixed = false
            out.confidence = "conflict"
            return out
        end

        if samples >= 1 and minValue then
            out.status = "live-current-build-observed-single"
            out.source = "live-current-build"
            out.outputMin = minValue
            out.outputMax = maxValue
            out.fixed = minValue == maxValue
            out.confidence = "observed"
            return out
        end
    end

    if reference then
        -- Planning estimates are explicitly separated from fixed, qualified
        -- dependency quantities used by the recursive production path.
        local referenceQuantity = tonumber(reference.outputQuantity)
        local fixedQuantity = reference.fixed ~= false and referenceQuantity
            and referenceQuantity > 0 and referenceQuantity == math.floor(referenceQuantity)
        out.planningUsable = fixedQuantity and reference.dependencyQuantityEligible == true or false
        out.planningQuantity = out.planningUsable and referenceQuantity or nil
        out.status = referenceBuild.matches and "external-forever-reference" or "external-forever-reference-stale-build"
        out.source = reference.source
        out.outputQuantity = tonumber(reference.outputQuantity)
        out.outputMin = tonumber(reference.outputMin) or out.outputQuantity
        out.outputMax = tonumber(reference.outputMax) or out.outputQuantity
        out.fixed = reference.fixed ~= false
        out.dependencyQuantityEligible = referenceBuild.matches and reference.dependencyQuantityEligible == true or false
        out.externalVerified = true
        out.confidence = referenceBuild.matches and "external-verified" or "external-build-unverified"
        return out
    end

    out.status = "yield-unresolved"
    out.source = "nominal-fallback"
    out.outputQuantity = nil
    out.fixed = false
    out.confidence = "unknown"
    return out
end

function RecipeOutputEvidence:Validate()
    local errors, warnings = {}, {}
    local root = referenceRoot()
    if not root or root.contract ~= "forever-recipe-output-yield-reference-v1" then
        errors[#errors + 1] = "recipe output yield reference unavailable"
        return errors, warnings
    end
    local metadata = root.sourceMetadata or {}
    if tonumber(metadata.capturedAgainstBuild) == nil then
        errors[#errors + 1] = "recipe output reference missing captured-against build provenance"
    end
    if metadata.buildPinned ~= false then
        errors[#errors + 1] = "external output reference must not claim build-pinned authority"
    end
    local seenSpell = {}
    for name, row in pairs(root.recipes or {}) do
        if not tonumber(row.spellID) then errors[#errors + 1] = tostring(name) .. ": missing spellID" end
        if not tonumber(row.outputQuantity) or tonumber(row.outputQuantity) <= 0 then errors[#errors + 1] = tostring(name) .. ": invalid output quantity" end
        if row.plannerEligible ~= false or row.dependencyQuantityEligible ~= true then errors[#errors + 1] = tostring(name) .. ": authority policy mismatch" end
        local spellID = tonumber(row.spellID)
        if spellID and seenSpell[spellID] then errors[#errors + 1] = tostring(name) .. ": duplicate spellID" end
        if spellID then seenSpell[spellID] = true end
    end
    return errors, warnings
end

function RecipeOutputEvidence:GetSummary(recipeName)
    local root = referenceRoot()
    if not root then return "Recipe output yield evidence unavailable." end
    if recipeName and tostring(recipeName) ~= "" then
        local resolved = self:Resolve(recipeName)
        if not resolved then return "Recipe output yield evidence unavailable." end
        local quantity = resolved.outputQuantity and tostring(resolved.outputQuantity)
            or (resolved.outputMin and resolved.outputMax and string.format("%s-%s", tostring(resolved.outputMin), tostring(resolved.outputMax)) or "unknown")
        local liveSamples = resolved.live and tonumber(resolved.live.samples) or 0
        return table.concat({
            "Recipe output yield: " .. tostring(recipeName),
            "Status: " .. tostring(resolved.status),
            "Output / craft: " .. quantity,
            "Live current-build samples: " .. tostring(liveSamples),
            "Dependency quantity eligible: " .. tostring(resolved.dependencyQuantityEligible == true),
            "Historical planning quantity (read-only): " .. tostring(resolved.planningQuantity or "unresolved"),
            "Planner authority: disabled",
        }, "\n")
    end

    local count = 0
    for _ in pairs(root.recipes or {}) do count = count + 1 end
    local _, build = getBuildStore(false)
    local liveCount = 0
    for _ in pairs(build and build.recipes or {}) do liveCount = liveCount + 1 end
    return table.concat({
        "Recipe output yield evidence:",
        string.format("External Forever references: %d", count),
        string.format("Current-build live recipe profiles: %d", liveCount),
        "Authority: live current-build > corroborated external > same-build external Forever reference > unresolved",
        string.format("External reference captured against build: %s", tostring(root.sourceMetadata and root.sourceMetadata.capturedAgainstBuild or "unknown")),
        "On a later client build, external-only yield data is suspended until live corroboration; Planner authority remains disabled.",
    }, "\n")
end

JLP:RegisterModule("RecipeOutputEvidence", RecipeOutputEvidence)
