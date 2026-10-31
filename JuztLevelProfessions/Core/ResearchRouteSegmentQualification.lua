local _, JLP = ...

-- Validates provisional research route segments against the current character's
-- live profession state. Structural promotion/closure evidence remains owned by
-- the preceding research layers; this module adds only live relevance and
-- qualification. It never grants Planner or execution authority.
local ResearchRouteSegmentQualification = {
    contract = "live-route-segment-qualification-v1",
    authority = "route-segment-qualification-staging-only",
    plannerEligible = false,
    executionEligible = false,
    transferable = false,
    -- Qualification is evidence, never a native dispatch credential. A separate
    -- Planner bridge may consume an explicitly qualified, session-stable row.
    plannerHandoffEligible = false,
}

local function normalizeMode(mode)
    return mode == "aggressive" and "aggressive" or "normal"
end

local function currentBuild()
    local buildInfo = JLP:GetModule("ClientBuildInfo")
    local liveBuild = buildInfo and buildInfo:GetBuildNumber() or nil
    return liveBuild, liveBuild and "live-client" or "unknown"
end

local function playerLevel()
    if type(UnitLevel) ~= "function" then return nil end
    local ok, value = pcall(UnitLevel, "player")
    if not ok then ok, value = pcall(UnitLevel) end
    return ok and tonumber(value) or nil
end

local function readProfessionState(professionKey, override)
    if type(override) == "table" then
        return {
            key = professionKey,
            name = override.name or professionKey,
            skill = tonumber(override.skill) or 0,
            maxSkill = tonumber(override.maxSkill) or 0,
            skillLine = tonumber(override.skillLine),
            cached = override.cached == true,
            detected = override.detected ~= false,
            source = "diagnostic-profession-override",
            simulatedState = true,
        }
    end

    local api = JLP:GetModule("ProfessionAPI")
    local detected = api and api.GetDetected and api:GetDetected() or {}
    local row = detected and detected[professionKey]
    if type(row) == "table" then
        return {
            key = professionKey,
            name = row.name or professionKey,
            skill = tonumber(row.skill) or 0,
            maxSkill = tonumber(row.maxSkill) or 0,
            skillLine = tonumber(row.skillLine),
            cached = row.cached == true,
            detected = true,
            source = row.cached and "persistent-cache" or "live-profession-api",
        }
    end
    return {
        key = professionKey,
        name = professionKey,
        skill = 0,
        maxSkill = 0,
        cached = false,
        detected = false,
        source = "not-detected",
    }
end

local function copySegmentRef(segment)
    return {
        segmentIndex = segment.segmentIndex,
        segmentID = segment.segmentID,
        startSkill = tonumber(segment.startSkill),
        endSkill = tonumber(segment.endSkill),
        startRouteStepIndex = tonumber(segment.startRouteStepIndex),
        endRouteStepIndex = tonumber(segment.endRouteStepIndex),
        status = segment.status,
        segmentCandidateEligible = segment.segmentCandidateEligible == true,
    }
end

local function overlapMap(segments)
    local out = {}
    for i = 1, #(segments or {}) do
        local a = segments[i]
        local aStart, aEnd = tonumber(a.startSkill), tonumber(a.endSkill)
        if aStart and aEnd then
            for j = i + 1, #(segments or {}) do
                local b = segments[j]
                local bStart, bEnd = tonumber(b.startSkill), tonumber(b.endSkill)
                if bStart and bEnd and aStart < bEnd and bStart < aEnd then
                    out[a.segmentIndex] = out[a.segmentIndex] or {}
                    out[b.segmentIndex] = out[b.segmentIndex] or {}
                    out[a.segmentIndex][#out[a.segmentIndex] + 1] = b.segmentIndex
                    out[b.segmentIndex][#out[b.segmentIndex] + 1] = a.segmentIndex
                end
            end
        end
    end
    return out
end

local function recipeState(professionKey, segment, activeBuild)
    local cache = JLP:GetModule("KnowledgeCache")
    local out = {
        total = 0,
        knownCurrentBuild = 0,
        knownHistorical = 0,
        notKnown = 0,
        unknown = 0,
        ready = true,
        recipes = {},
    }
    for _, step in ipairs(segment.steps or {}) do
        out.total = out.total + 1
        local state = cache and cache.GetRecipeKnowledgeState and cache:GetRecipeKnowledgeState(step.recipe, professionKey) or nil
        local knowledge = state and state.knowledge or "unknown"
        local currentObserved = state and state.currentBuildObserved == true
        local observedBuild = state and tonumber(state.observedBuild) or nil
        local buildMatches = activeBuild ~= nil and observedBuild ~= nil and tonumber(activeBuild) == observedBuild
        local currentReady = knowledge == "known" and currentObserved and buildMatches and not (state and state.sessionIdentityConflict == true)
        if currentReady then
            out.knownCurrentBuild = out.knownCurrentBuild + 1
        elseif knowledge == "known" then
            out.knownHistorical = out.knownHistorical + 1
            out.ready = false
        elseif knowledge == "not-known" then
            out.notKnown = out.notKnown + 1
            out.ready = false
        else
            out.unknown = out.unknown + 1
            out.ready = false
        end
        out.recipes[#out.recipes + 1] = {
            routeStepIndex = step.routeStepIndex,
            recipe = step.recipe,
            knowledge = knowledge,
            currentBuildObserved = currentObserved,
            sessionIdentityConflict = state and state.sessionIdentityConflict == true or false,
            observedBuild = observedBuild,
            currentBuild = state and tonumber(state.currentBuild) or activeBuild,
            ready = currentReady,
        }
    end
    return out
end

local function trainerRankState(segment, profession, level)
    local out = {
        required = #(segment.trainerGates or {}) > 0,
        ready = true,
        gates = {},
    }
    for _, gate in ipairs(segment.trainerGates or {}) do
        local requiredCap = tonumber(gate.skillCapTo)
        local requiredLevel = tonumber(gate.minCharacterLevel) or 0
        local capReady = requiredCap == nil or (tonumber(profession.maxSkill) or 0) >= requiredCap
        local levelReady = level == nil or level >= requiredLevel
        local sourceReady = gate.ready == true
        local ready = capReady and levelReady and sourceReady
        if not ready then out.ready = false end
        out.gates[#out.gates + 1] = {
            routeStepIndex = gate.routeStepIndex,
            tier = gate.tier,
            requiredSkill = gate.requiredSkill,
            requiredCap = requiredCap,
            requiredLevel = requiredLevel,
            currentCap = tonumber(profession.maxSkill) or 0,
            currentLevel = level,
            capReady = capReady,
            levelReady = levelReady,
            sourceReady = sourceReady,
            ready = ready,
        }
    end
    return out
end

local function relevanceFor(segment, profession)
    if not profession.detected then return "unavailable" end
    local skill = tonumber(profession.skill) or 0
    local startSkill = tonumber(segment.startSkill) or 0
    local endSkill = tonumber(segment.endSkill) or startSkill
    if skill >= endSkill then return "already-passed" end
    if skill < startSkill then return "not-yet-relevant" end
    return "active"
end

local function classify(row)
    if row.segment.segmentCandidateEligible ~= true then
        return "blocked", "blocked-structural-segment"
    end
    if not row.overlap.free then
        return "blocked", "blocked-segment-overlap"
    end
    -- Caller-supplied profession/level data may be used for a read-only
    -- diagnostic view, but cannot qualify a route for Planner authority.
    if row.simulatedState == true then
        return "blocked", "blocked-unverified-simulated-live-state"
    end
    if not row.liveProfession.detected then
        return "blocked", "blocked-profession-not-detected"
    end
    if row.liveProfession.cached then
        return "blocked", "awaiting-live-profession-state"
    end
    if row.relevance == "already-passed" then
        return "already-passed", "segment-already-passed"
    end
    if row.relevance == "not-yet-relevant" then
        return "not-yet-relevant", "segment-not-yet-relevant"
    end
    -- An empty recipe list cannot be interpreted as a fully verified segment.
    if (row.recipes.total or 0) == 0 then
        return "blocked", "blocked-segment-without-recipes"
    end
    if not row.recipes.ready then
        if row.recipes.notKnown > 0 then return "blocked", "blocked-live-recipe-not-known" end
        if row.recipes.knownHistorical > 0 then return "blocked", "awaiting-current-build-recipe-revalidation" end
        return "blocked", "awaiting-live-recipe-availability"
    end
    if not row.trainerRank.ready then
        for _, gate in ipairs(row.trainerRank.gates or {}) do
            if not gate.levelReady then return "blocked", "blocked-live-character-level" end
            if not gate.capReady then return "blocked", "blocked-live-trainer-rank" end
            if not gate.sourceReady then return "blocked", "blocked-live-trainer-source" end
        end
        return "blocked", "blocked-live-trainer-rank"
    end
    if row.currentBuild == nil or row.segmentBuild ~= row.currentBuild then
        -- This compares two LIVE observations, not a historical source build.
        -- A changed session must be re-observed, not unlocked by a build ID.
        return "blocked", "awaiting-live-session-revalidation"
    end
    if not row.runtimeCapabilitiesReady then
        return "blocked", "awaiting-profession-recipe-api-capabilities"
    end
    return "qualified", "qualified-live-route-segment"
end

function ResearchRouteSegmentQualification:Build(professionKey, mode, options)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode)
    options = type(options) == "table" and options or {}

    local bridge = JLP:GetModule("ResearchRouteSegmentBridge")
    local bridgeModel = bridge and bridge:Build(professionKey, mode)
    if not bridgeModel then return nil end

    local activeBuild, buildSource = currentBuild()
    local runtime=JLP:GetModule("RuntimeCompatibility")
    local panelCapabilities=runtime and runtime.AssessFeature
        and runtime:AssessFeature("PROFESSION_PANEL") or nil
    local recipeCapabilities=runtime and runtime.AssessFeature
        and runtime:AssessFeature("RECIPE_IDENTITY") or nil
    local runtimeCapabilitiesReady=panelCapabilities ~= nil and panelCapabilities.available==true
        and recipeCapabilities ~= nil and recipeCapabilities.available==true
    local initialSession=runtime and runtime.GetSessionReceipt and runtime:GetSessionReceipt() or nil
    local profession = readProfessionState(professionKey, options.professionState)
    local level = tonumber(options.playerLevel) or playerLevel()
    local overlaps = overlapMap(bridgeModel.segments)
    local model = {
        contract = self.contract,
        professionKey = professionKey,
        mode = mode,
        authority = self.authority,
        plannerEligible = false,
        executionEligible = false,
        transferable = false,
        plannerHandoffEligible = false,
        currentBuild = activeBuild,
        currentBuildSource = buildSource,
        playerLevel = level,
        liveProfession = profession,
        segments = {},
        segmentByIndex = {},
        stats = {
            segments = 0,
            qualified = 0,
            notYetRelevant = 0,
            alreadyPassed = 0,
            blocked = 0,
            overlapSegments = 0,
            activeSegments = 0,
            currentBuildRecipes = 0,
            requiredRecipes = 0,
        },
    }

    for _, segment in ipairs(bridgeModel.segments or {}) do
        local overlapWith = overlaps[segment.segmentIndex] or {}
        local row = {
            segmentIndex = segment.segmentIndex,
            segmentID = segment.segmentID,
            professionKey = professionKey,
            mode = mode,
            authority = self.authority,
            segment = copySegmentRef(segment),
            liveProfession = profession,
            playerLevel = level,
            simulatedState = type(options.professionState) == "table" or options.playerLevel ~= nil,
            currentBuild = activeBuild,
            runtimeCapabilitiesReady = runtimeCapabilitiesReady,
            runtimeCapabilities = {professionPanel=panelCapabilities,recipeIdentity=recipeCapabilities},
            segmentBuild = segment.buildProvenance and tonumber(segment.buildProvenance.currentBuild) or nil,
            relevance = relevanceFor(segment, profession),
            recipes = recipeState(professionKey, segment, activeBuild),
            trainerRank = trainerRankState(segment, profession, level),
            overlap = {
                free = #overlapWith == 0,
                segmentIndices = overlapWith,
                count = #overlapWith,
            },
            plannerEligible = false,
            executionEligible = false,
            transferable = false,
            plannerHandoffEligible = false,
            qualificationEligible = false,
        }
        local class, status = classify(row)
        row.qualificationClass = class
        row.status = status
        row.qualificationEligible = class == "qualified"
        model.segments[#model.segments + 1] = row
        model.segmentByIndex[row.segmentIndex] = row
        model.stats.segments = model.stats.segments + 1
        model.stats.requiredRecipes = model.stats.requiredRecipes + row.recipes.total
        model.stats.currentBuildRecipes = model.stats.currentBuildRecipes + row.recipes.knownCurrentBuild
        if row.relevance == "active" then model.stats.activeSegments = model.stats.activeSegments + 1 end
        if not row.overlap.free then model.stats.overlapSegments = model.stats.overlapSegments + 1 end
        if class == "qualified" then model.stats.qualified = model.stats.qualified + 1
        elseif class == "not-yet-relevant" then model.stats.notYetRelevant = model.stats.notYetRelevant + 1
        elseif class == "already-passed" then model.stats.alreadyPassed = model.stats.alreadyPassed + 1
        else model.stats.blocked = model.stats.blocked + 1 end
    end

    -- The client can change the profession panel, interface or APIs while the
    -- individual recipe observations above are being evaluated. A qualifying
    -- row must survive a final live capability / session recheck.
    local lastPanel=runtime and runtime.AssessFeature and runtime:AssessFeature("PROFESSION_PANEL") or nil
    local lastRecipe=runtime and runtime.AssessFeature and runtime:AssessFeature("RECIPE_IDENTITY") or nil
    local finalSession=runtime and runtime.GetSessionReceipt and runtime:GetSessionReceipt() or nil
    local stable=initialSession~=nil and finalSession==initialSession
        and lastPanel~=nil and lastPanel.available==true
        and lastRecipe~=nil and lastRecipe.available==true
        and currentBuild()==activeBuild
    model.runtimeCapabilitySessionStable=stable==true
    if not stable then
        for _,row in ipairs(model.segments) do
            if row.qualificationEligible then
                row.qualificationEligible=false
                row.qualificationClass="blocked"
                row.status="awaiting-live-session-capability-revalidation"
                model.stats.qualified=model.stats.qualified-1
                model.stats.blocked=model.stats.blocked+1
            end
        end
    end
    if options.includeReadOnlyPreview==true then
    -- P1-177: independent volatile preview. Segment authority above is
    -- intentionally unmodified: observed read-only recipes are NEVER counted
    -- in stats.qualified, currentBuildRecipes or plannerHandoffEligible.
    local api=JLP:GetModule("ProfessionAPI")
    local cache=JLP:GetModule("KnowledgeCache")
    local observedPanel=api and type(api.GetReadOnlyProfessionObservation)=="function"
        and api:GetReadOnlyProfessionObservation() or nil
    local readOnlyPanelOK=observedPanel and observedPanel.observed==true
        and observedPanel.professionKey==professionKey
        and not (type(options.professionState)=="table" or options.playerLevel~=nil)
    local readOnlyPreview={contract="research-segment-volatile-preview-v1",
        readOnly=true,nativeDispatchAllowed=false,executionEligible=false,
        plannerEligible=false,plannerHandoffEligible=false,
        persistentReceiptEligible=false,observed=readOnlyPanelOK and true or false,
        reason=readOnlyPanelOK and "LIVE_PANEL_READ_ONLY" or
            ((type(options.professionState)=="table" or options.playerLevel~=nil)
             and "SIMULATED_OVERRIDE" or
            (observedPanel and observedPanel.reason or "LIVE_PANEL_UNAVAILABLE")),
        observationQuality=readOnlyPanelOK and observedPanel.observationQuality or nil,
        observedRecipes=0,unlearnedRecipes=0,unverifiedRecipes=0}
    for _,row in ipairs(model.segments) do
        local preview={readOnly=true,plannerHandoffEligible=false,
            nativeDispatchAllowed=false,observedRecipes=0,unlearnedRecipes=0,
            unverifiedRecipes=0,recipes={}}
        local original=bridgeModel.segments and bridgeModel.segments[row.segmentIndex]
        -- Segment indices are not guaranteed dense; never use the index as
        -- an array offset into the original bridge model.
        if not original or original.segmentIndex~=row.segmentIndex then
            original=nil
            for _,candidate in ipairs(bridgeModel.segments or {}) do
                if candidate.segmentIndex==row.segmentIndex then original=candidate;break end
            end
        end
        for _,step in ipairs(original and original.steps or {}) do
            local evidence=readOnlyPanelOK and cache and
                type(cache.GetReadOnlyRecipeKnowledgeState)=="function" and
                cache:GetReadOnlyRecipeKnowledgeState(step.recipe,professionKey,step.recipeID) or nil
            local item={recipe=step.recipe,routeStepIndex=step.routeStepIndex,
                recipeID=evidence and evidence.recipeID or nil,
                readOnlyObserved=evidence and evidence.readOnlyObserved==true or false,
                learned=evidence and evidence.readOnlyObserved==true and evidence.learned or nil,
                reason=evidence and evidence.reason or "LIVE_PANEL_UNAVAILABLE"}
            if evidence and evidence.readOnlyObserved==true then
                item.learned=evidence.learned -- preserve explicit learned=false
            end
            preview.recipes[#preview.recipes+1]=item
            if item.readOnlyObserved then
                if item.learned then preview.observedRecipes=preview.observedRecipes+1
                else preview.unlearnedRecipes=preview.unlearnedRecipes+1 end
            else preview.unverifiedRecipes=preview.unverifiedRecipes+1 end
        end
        row.readOnlyPreview=preview
        readOnlyPreview.observedRecipes=readOnlyPreview.observedRecipes+preview.observedRecipes
        readOnlyPreview.unlearnedRecipes=readOnlyPreview.unlearnedRecipes+preview.unlearnedRecipes
        readOnlyPreview.unverifiedRecipes=readOnlyPreview.unverifiedRecipes+preview.unverifiedRecipes
    end
    -- One last panel read prevents aggregating a preview across a panel switch.
    -- No native or planner authority is ever derived from this evidence.
    if readOnlyPanelOK then
        local finalPanel=api:GetReadOnlyProfessionObservation()
        if not finalPanel or finalPanel.observed~=true or
            finalPanel.observationToken~=observedPanel.observationToken or
            finalPanel.skill~=observedPanel.skill or
            finalPanel.maxSkill~=observedPanel.maxSkill or
            finalPanel.observationQuality~=observedPanel.observationQuality then
            readOnlyPreview.observed=false
            readOnlyPreview.reason="READ_ONLY_PANEL_CHANGED"
            readOnlyPreview.observedRecipes=0
            readOnlyPreview.unlearnedRecipes=0
            for _,row in ipairs(model.segments) do
                local preview=row.readOnlyPreview
                preview.unverifiedRecipes=#(preview.recipes or {})
                preview.observedRecipes=0;preview.unlearnedRecipes=0
                for _,item in ipairs(preview.recipes) do
                    item.readOnlyObserved=false;item.learned=nil
                    item.reason="READ_ONLY_PANEL_CHANGED"
                end
            end
            readOnlyPreview.unverifiedRecipes=(function()
                local count=0
                for _,row in ipairs(model.segments) do count=count+row.readOnlyPreview.unverifiedRecipes end
                return count
            end)()
        end
    end
    model.readOnlyPreview=readOnlyPreview
    end -- opt-in only; never trigger repeated live recipe reads on ordinary route builds
    -- A qualified row is an explicit Planner *handoff candidate*, not an
    -- executable route. A complete authority/readiness/parity check takes
    -- place in ResearchRouteAuthorityBridge before Planner sees any dataset.
    -- Never treat a test override or a partially qualified segment as proof.
    for _,row in ipairs(model.segments) do
        row.plannerHandoffEligible = stable == true
            and row.qualificationEligible == true
            and row.qualificationClass == "qualified"
            and row.simulatedState ~= true
        if row.plannerHandoffEligible then model.plannerHandoffEligible = true end
    end
    if not profession.detected then
        model.state = "live-profession-not-detected"
    elseif profession.cached then
        model.state = "awaiting-live-profession-state"
    elseif model.stats.blocked > 0 then
        model.state = "live-route-segments-partially-blocked"
    elseif model.stats.qualified > 0 then
        model.state = "live-route-segment-qualified"
    else
        model.state = "live-route-segments-contextualized"
    end
    return model
end

-- Explicit opt-in avoids expensive live recipe scans during ordinary Planner
-- builds. Both the preview and its enclosing strict qualification retain their
-- independent, non-transferable authority classifications.
function ResearchRouteSegmentQualification:BuildReadOnlyPreview(professionKey,mode,options)
    local query={includeReadOnlyPreview=true}
    for key,value in pairs(type(options)=="table" and options or {}) do
        if key~="includeReadOnlyPreview" then query[key]=value end
    end
    local model=self:Build(professionKey,mode,query)
    return model and model.readOnlyPreview or nil,model
end

function ResearchRouteSegmentQualification:GetSegment(professionKey, mode, selector, options)
    local model = self:Build(professionKey, mode, options)
    if not model then return nil, nil end
    local index = tonumber(selector)
    if index then return model.segmentByIndex[index], model end
    local wanted = tostring(selector or ""):lower()
    if wanted ~= "" then
        for _, row in ipairs(model.segments or {}) do
            local bridge = JLP:GetModule("ResearchRouteSegmentBridge")
            local segment = bridge and bridge:GetSegment(professionKey, mode, row.segmentIndex) or nil
            for _, step in ipairs(segment and segment.steps or {}) do
                if tostring(step.recipe or ""):lower() == wanted then return row, model end
            end
        end
    end
    return nil, model
end

function ResearchRouteSegmentQualification:Validate()
    local errors, warnings = {}, {}
    local root = JLP.data and JLP.data.professionResearchRoutes
    if not root then return {"profession research unavailable"}, warnings end
    for professionKey, modes in pairs(root.professions or {}) do
        if professionKey ~= "HARNESS" and professionKey ~= "HARNESSCLOSURE" and professionKey ~= "HARNESSSEGMENT" and professionKey ~= "HARNESSQUAL" then
            for _, mode in ipairs({"normal", "aggressive"}) do
                if modes[mode] then
                    local model = self:Build(professionKey, mode)
                    if not model then
                        errors[#errors + 1] = professionKey .. "/" .. mode .. ": route segment qualification unavailable"
                    else
                        for _, row in ipairs(model.segments or {}) do
                            if row.plannerEligible ~= false or row.executionEligible ~= false or row.transferable ~= false then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": qualification escaped staging authority"
                            end
                            if row.plannerHandoffEligible and (row.qualificationEligible ~= true
                                or row.qualificationClass ~= "qualified" or row.simulatedState == true) then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": invalid Planner handoff candidate"
                            end
                            if row.qualificationEligible and row.qualificationClass ~= "qualified" then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": eligible segment has invalid qualification class"
                            end
                            if row.qualificationEligible and (not row.recipes.ready or not row.trainerRank.ready or not row.overlap.free) then
                                errors[#errors + 1] = professionKey .. "/" .. mode .. ": qualified segment retained a live-state gate failure"
                            end
                        end
                    end
                end
            end
        end
    end
    return errors, warnings
end

local function formatRow(row)
    if not row then return "Live route-segment qualification unavailable." end
    local p = row.liveProfession or {}
    local lines = {
        string.format("Live route-segment qualification %d: %s / %s", tonumber(row.segmentIndex) or 0, tostring(row.professionKey), tostring(row.mode)),
        "Status: " .. tostring(row.status),
        "Class: " .. tostring(row.qualificationClass),
        string.format("Segment skill: %d-%d · live skill %d/%d", tonumber(row.segment.startSkill) or 0, tonumber(row.segment.endSkill) or 0, tonumber(p.skill) or 0, tonumber(p.maxSkill) or 0),
        string.format("Recipes: %d/%d known on current build", tonumber(row.recipes.knownCurrentBuild) or 0, tonumber(row.recipes.total) or 0),
        string.format("Trainer rank: %s · overlap-free: %s", tostring(row.trainerRank.ready == true), tostring(row.overlap.free == true)),
        string.format("Build: segment %s · current %s", tostring(row.segmentBuild or "unknown"), tostring(row.currentBuild or "unknown")),
        "Qualification candidate: " .. tostring(row.qualificationEligible == true),
        "Planner handoff candidate: " .. tostring(row.plannerHandoffEligible == true),
        "Planner/native authority: separate downstream gates",
    }
    if not row.overlap.free then
        local parts = {}
        for _, index in ipairs(row.overlap.segmentIndices or {}) do parts[#parts + 1] = tostring(index) end
        lines[#lines + 1] = "Overlaps segment(s): " .. table.concat(parts, ", ")
    end
    for _, gate in ipairs(row.trainerRank.gates or {}) do
        lines[#lines + 1] = string.format("· trainer %s · cap %s/%s · level %s/%s · %s", tostring(gate.tier or "unknown"), tostring(gate.currentCap or "?"), tostring(gate.requiredCap or "?"), tostring(gate.currentLevel or "?"), tostring(gate.requiredLevel or "?"), tostring(gate.ready == true and "ready" or "blocked"))
    end
    return table.concat(lines, "\n")
end

function ResearchRouteSegmentQualification:GetSummary(professionKey, mode, selector)
    professionKey = tostring(professionKey or "ENGINEERING"):upper()
    mode = normalizeMode(mode)
    if selector and tostring(selector) ~= "" then
        return formatRow(self:GetSegment(professionKey, mode, selector))
    end
    local model = self:Build(professionKey, mode)
    if not model then return "Live route-segment qualification unavailable." end
    local s, p = model.stats, model.liveProfession
    local lines = {
        string.format("Live route-segment qualification: %s / %s", professionKey, mode),
        string.format("State: %s · Planner handoff: %s · native authority separate", tostring(model.state), tostring(model.plannerHandoffEligible == true)),
        string.format("Profession: %s · skill %d/%d · source %s", tostring(p.name or professionKey), tonumber(p.skill) or 0, tonumber(p.maxSkill) or 0, tostring(p.source or "unknown")),
        string.format("Segments: %d · qualified %d · future %d · passed %d · blocked %d", tonumber(s.segments) or 0, tonumber(s.qualified) or 0, tonumber(s.notYetRelevant) or 0, tonumber(s.alreadyPassed) or 0, tonumber(s.blocked) or 0),
        string.format("Recipes current-build: %d/%d · overlap segments %d", tonumber(s.currentBuildRecipes) or 0, tonumber(s.requiredRecipes) or 0, tonumber(s.overlapSegments) or 0),
    }
    for _, row in ipairs(model.segments or {}) do
        lines[#lines + 1] = string.format("· segment %d %d-%d · %s", tonumber(row.segmentIndex) or 0, tonumber(row.segment.startSkill) or 0, tonumber(row.segment.endSkill) or 0, tostring(row.status))
    end
    lines[#lines + 1] = "Qualification grants a revocable Planner handoff candidate only; bridge/readiness/parity decide Planner publication, native execution has independent gates."
    return table.concat(lines, "\n")
end

JLP:RegisterModule("ResearchRouteSegmentQualification", ResearchRouteSegmentQualification)
