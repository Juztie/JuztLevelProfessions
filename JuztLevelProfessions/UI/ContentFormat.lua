local _, JLP = ...

local Format = {}

local function safe(value)
    if JLP.SafeText then return JLP:SafeText(value) end
    return tostring(value or "")
end

local function hex(tone)
    local r,g,b = JLP.UITheme:Color(tone or "text")
    local function channel(v)
        v = math.max(0, math.min(1, tonumber(v) or 0))
        return math.floor(v * 255 + 0.5)
    end
    return string.format("%02x%02x%02x", channel(r), channel(g), channel(b))
end

function Format:Tone(value, tone)
    return "|cff" .. hex(tone or "text") .. safe(value) .. "|r"
end

function Format:Label(label, value, valueTone)
    return self:Tone(tostring(label or "") .. ":", "muted") .. " " .. self:Tone(value or "-", valueTone or "text")
end

function Format:Entity(value)
    return self:Tone(value or "-", "cyan")
end

function Format:SourceKind(source)
    local kind = tostring(source and source.kind or "source")
    local labels = {
        trainer = "Trainer",
        vendor = "Vendor",
        ["vendor-pattern"] = "Pattern Vendor",
        ["vendor-formula"] = "Formula Vendor",
        ["drop-pattern"] = "Pattern Source",
    }
    return labels[kind] or "Source"
end

function Format:SourceInline(source)
    if not source then return self:Tone("Source unavailable", "muted") end
    local parts = {}
    if source.name then parts[#parts + 1] = self:Entity(source.name) end
    local place = source.zone or source.area
    if place then parts[#parts + 1] = self:Tone(place, "text") end
    if type(source.nav) == "table" and tonumber(source.nav.x) and tonumber(source.nav.y) then
        parts[#parts + 1] = self:Tone(string.format("%.1f, %.1f", tonumber(source.nav.x) * 100, tonumber(source.nav.y) * 100), "cyan")
    elseif source.dungeon then
        parts[#parts + 1] = self:Tone("Dungeon", "warn")
    end
    return table.concat(parts, " | ")
end

function Format:Source(source, compact)
    if not source then return self:Tone("Source details are not available yet.", "muted") end
    if compact then return self:SourceInline(source) end
    local lines = {}
    if source.name then
        lines[#lines + 1] = self:Label(self:SourceKind(source), source.name, "cyan")
    end
    if source.area then lines[#lines + 1] = self:Label("Area", source.area, "text") end
    if source.zone and source.zone ~= source.area then lines[#lines + 1] = self:Label("Zone", source.zone, "text") end
    if type(source.nav) == "table" and tonumber(source.nav.x) and tonumber(source.nav.y) then
        lines[#lines + 1] = self:Label("Coordinates", string.format("%.1f, %.1f", tonumber(source.nav.x) * 100, tonumber(source.nav.y) * 100), "cyan")
    elseif source.dungeon then
        lines[#lines + 1] = self:Label("Navigation", "Dungeon source - no internal waypoint assumed", "warn")
    end
    if source.note and not compact then lines[#lines + 1] = self:Tone(source.note, "muted") end
    return table.concat(lines, "\n")
end

local SOURCE_LABELS = {
    vendor = "Vendor",
    auction = "Auction House",
    crafted = "Craft",
    ["disenchant-or-auction"] = "AH / Disenchant",
    bank = "Bank",
}

function Format:Material(row, index, compact)
    row = row or {}
    local lines = {}
    local name = tostring(row.name or "Material")
    local source = SOURCE_LABELS[row.source] or tostring(row.source or "Source")
    local heading = (index and (tostring(index) .. ". ") or "") .. self:Entity(name) .. "  " .. self:Tone("[" .. source .. "]", "text")
    lines[#lines + 1] = heading

    local missingTone = row.missingKnown==false and "warn" or ((tonumber(row.missing) or 0) > 0 and "warn" or "good")
    lines[#lines + 1] = table.concat({
        self:Label("Need", row.required or 0),
        self:Label("Observed stock", row.inventoryUnknown and "PARTIAL/UNKNOWN" or (row.owned or 0), (tonumber(row.owned) or 0) > 0 and "good" or "text"),
        self:Label("Missing (estimated)", row.missingKnown==false and "UNKNOWN" or (row.missing or 0), missingTone),
    }, "   ")

    if not compact and row.storage then
        lines[#lines + 1] = self:Tone("Storage", "muted") .. "  " ..
            self:Label("Bags", row.storage.bagKnown==true and (row.storage.observedBags or 0) or "UNKNOWN", "text") .. "   " ..
            self:Label("Bank (last known)", row.storage.bankKnown==true and (row.storage.observedBank or 0) or "UNKNOWN", "text")
    end

    if row.craftedFrom and (tonumber(row.missing) or 0) > 0 then
        local raw = row.craftedFrom
        local rawName = raw.name or (raw.itemID and ("Item " .. tostring(raw.itemID))) or "Raw material"
        lines[#lines + 1] = self:Tone("Prepare from", "muted") .. " " .. self:Entity(rawName)
        local rawMissing = raw.missingKnown==false and nil or math.max(0, (tonumber(raw.required) or 0) - (tonumber(raw.owned) or 0))
        lines[#lines + 1] = table.concat({
            self:Label("Need", raw.required or 0),
            self:Label("Owned", raw.owned or 0, (tonumber(raw.owned) or 0) > 0 and "good" or "text"),
            self:Label("Missing", rawMissing~=nil and rawMissing or "UNKNOWN", rawMissing==nil and "warn" or (rawMissing>0 and "warn" or "good")),
        }, "   ")
        if not compact and raw.storage then
            lines[#lines + 1] = self:Tone("Raw storage", "muted") .. "  " ..
                self:Label("Bags", raw.storage.bagKnown==true and (raw.storage.observedBags or 0) or "UNKNOWN") .. "   " .. self:Label("Bank", raw.storage.bankKnown==true and (raw.storage.observedBank or 0) or "UNKNOWN")
        end
    end
    return table.concat(lines, "\n")
end

function Format:Materials(materials, limit, compact)
    if not materials or #materials == 0 then return self:Tone("No materials are required for the current action.", "muted") end
    limit = math.max(1, math.floor(tonumber(limit) or 6))
    local lines = {}
    for i,row in ipairs(materials) do
        if i > limit then
            lines[#lines + 1] = self:Tone(string.format("+ %d more material%s", #materials - limit, (#materials - limit) == 1 and "" or "s"), "muted")
            break
        end
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = self:Material(row, i, compact)
    end
    return table.concat(lines, "\n")
end

local ACTION_VERBS = {
    ["retrieve-material"] = "Retrieve",
    ["retrieve-raw"] = "Retrieve",
    ["retrieve-tool"] = "Retrieve",
    ["retrieve-tool-material"] = "Retrieve",
    ["acquire-material"] = "Acquire",
    ["acquire-raw"] = "Acquire",
    ["acquire-tool-material"] = "Acquire",
    ["craft-intermediate"] = "Craft",
    ["craft-tool"] = "Craft",
    ["craft-leveling"] = "Craft",
    ["verify-recipe"] = "Verify",
    ["learn-recipe"] = "Learn",
    ["train-rank"] = "Train",
}

function Format:Action(action, plan, compact)
    if not action and plan and plan.actionKind=="reference" then
        return self:Tone(plan.action or "Inspect the advisory profession reference.","gold")
    end
    if not action then return self:Tone("No pending action.", "muted") end
    local kind = tostring(action.kind or "")
    local quantity = math.max(1, math.floor(tonumber(action.quantity) or 1))
    local item = action.itemName
    local verb = ACTION_VERBS[kind]
    local lines = {}

    if kind == "train-rank" then
        local gate = plan and plan.step and plan.step.trainer
        local rank = gate and gate.rank or "next profession rank"
        lines[#lines + 1] = self:Tone("Train", "gold") .. " " .. self:Entity(rank)
        if gate and gate.nextCap then lines[#lines + 1] = self:Label("Result", "Unlock skill cap " .. tostring(gate.nextCap), "good") end
        local source = action.sourceInfo or (plan and plan.step and plan.step.sourceInfo)
        if source then lines[#lines + 1] = self:Tone("Trainer:", "muted") .. " " .. self:SourceInline(source) end
        return table.concat(lines, "\n")
    end

    if verb and item then
        lines[#lines + 1] = self:Tone(verb, "gold") .. " " .. self:Entity(item) .. (quantity > 1 and (" " .. self:Tone("x" .. tostring(quantity), "text")) or "")
        if kind:match("^retrieve") then
            lines[#lines + 1] = self:Label("From", "Bank", "cyan")
            if not compact then lines[#lines + 1] = self:Tone("Move the required amount to your bags. The queue advances automatically after inventory refresh.", "muted") end
        elseif kind:match("^acquire") then
            local label = action.source == "vendor" and "Vendor" or action.source == "auction" and "Auction House" or action.source == "disenchant-or-auction" and "Auction House or Disenchant" or "External source"
            lines[#lines + 1] = self:Label("Source", label, action.source == "vendor" and "gold" or "cyan")
        elseif kind == "craft-intermediate" then
            lines[#lines + 1] = self:Tone("Preparation step for the current leveling batch.", "muted")
        elseif kind == "craft-tool" then
            lines[#lines + 1] = self:Tone("Reusable profession tool. Craft it once, then keep it in your bags while enchanting.", "muted")
        elseif kind == "craft-leveling" then
            local target = plan and plan.step and plan.step.skillTarget
            if target then lines[#lines + 1] = self:Label("Goal", "Continue toward skill " .. tostring(target), "good") end
        end
        return table.concat(lines, "\n")
    end

    if kind == "verify-recipe" then
        lines[#lines + 1] = self:Tone("Open the profession window", "gold")
        lines[#lines + 1] = self:Tone("Recipe knowledge will be verified automatically when the profession list becomes available.", "muted")
        return table.concat(lines, "\n")
    elseif kind == "learn-recipe" then
        local recipe = plan and plan.step and plan.step.recipe or action.itemName or "required recipe"
        lines[#lines + 1] = self:Tone("Learn", "gold") .. " " .. self:Entity(recipe)
        local source = action.sourceInfo or (plan and plan.step and plan.step.sourceInfo)
        if source then lines[#lines + 1] = self:Tone("Source:", "muted") .. " " .. self:SourceInline(source) end
        return table.concat(lines, "\n")
    end

    return safe(action.text or "Continue the current profession plan.")
end

function Format:Readiness(readiness, trackerStatus, flow)
    local lines = {}
    if not readiness then return self:Tone("Readiness data unavailable.", "muted") end
    if readiness.blocker == "trainer" then
        lines[#lines + 1] = self:Label("State", "Profession rank training required", "warn")
    elseif readiness.status == "complete" then
        lines[#lines + 1] = self:Label("State", "Profession route complete", "good")
    elseif readiness.recipe then
        local recipe = readiness.recipeKnowledge == "known" and "Learned" or readiness.recipeKnowledge == "not-known" and "Not learned" or "Not verified"
        local recipeTone = readiness.recipeKnowledge == "known" and "good" or readiness.recipeKnowledge == "not-known" and "bad" or "warn"
        lines[#lines + 1] = self:Label("Recipe", recipe, recipeTone)
        local bagText=readiness.immediateBagsKnown == false and "UNKNOWN" or tostring(readiness.immediateBags or 0)
        local bankText=readiness.preparedStorageKnown == false and "UNKNOWN" or tostring(readiness.preparedStorage or 0)
        lines[#lines + 1] = self:Label("Bag availability (estimate)", bagText, readiness.immediateBagsKnown == false and "warn" or "text") .. "   " .. self:Label("Bags + bank (estimate)", bankText)
    else
        lines[#lines + 1] = self:Tone(readiness.action or "Readiness unavailable.", "muted")
    end

    if trackerStatus then
        if trackerStatus.actionKind == "craft" then
            lines[#lines + 1] = self:Label("Live", string.format("%d crafts observed | +%d skill", trackerStatus.stepCraftsObserved or 0, trackerStatus.stepSkillGains or 0), "text")
        elseif trackerStatus.actionKind == "train" then
            lines[#lines + 1] = self:Label("Live", "Waiting for profession rank update", "muted")
        end
    end
    if flow then
        if (flow.availableHereCount or 0) > 0 then
            lines[#lines + 1] = self:Label("Workspace", string.format("%s | %d action%s available here", flow.currentContext and flow.currentContext.label or "Current", flow.availableHereCount, flow.availableHereCount == 1 and "" or "s"), "cyan")
        else
            lines[#lines + 1] = self:Label("Next workspace", flow.nextStationLabel or "Other", "cyan") .. "   " .. self:Label("Switches", flow.switchCount or 0)
        end
    end
    return table.concat(lines, "\n")
end

local STEP_STATUS = {
    completed = { label = "DONE", tone = "good" },
    current = { label = "NOW", tone = "gold" },
    upcoming = { label = "NEXT", tone = "muted" },
    reference = { label = "REF", tone = "gold" },
}

-- P1 QAFix: render the existing Planner/GuideSteps envelope; never
-- recalculate dataset or recipe authority in this presentation layer.
function Format:StepCoverage(model, compact)
    local evidence=model and model.coverageEnvelope
    if type(evidence)~="table" then return "" end
    if evidence.coverageStatus=="COMPLETE" and evidence.nextActionCode=="COMPLETE" then
        return self:Label("Skill 1-300", "COMPLETE", "good")
    end
    local status=tostring(evidence.datasetStatus or "UNKNOWN").." / "..
        tostring(evidence.coverageStatus or "UNKNOWN")
    local action=tostring(evidence.nextActionCode or "VERIFY")
    local nextText=tostring(evidence.nextAction or "Verify profession route evidence.")
    if compact then
        return self:Label("Coverage",status,"warn").." | "..
            self:Label("Next",action.." - "..nextText,"warn")
    end
    return self:Label("Coverage",status,"warn").."\n"..
        self:Label("Next",action.." - "..nextText,"warn")
end

local function appendCoverage(text,coverage,compact)
    if not coverage or coverage=="" then return text end
    return text .. (compact and " | " or "\n") .. coverage
end

function Format:StepProgression(model)
    if not model then return self:Tone("Route-step data unavailable.", "muted") end
    local coverage=self:StepCoverage(model,false)
    if model.status == "unavailable" then
        return appendCoverage(self:Tone("Route-step data unavailable.", "muted"),coverage,false)
    end
    if model.status == "complete" then
        return appendCoverage(self:Tone(string.format("Route complete - %d/%d steps finished.", model.total or 0, model.total or 0), "good"),coverage,false)
    end
    local lines = {}
    local upcomingSeen = 0
    for _, row in ipairs(model.window or {}) do
        local def = (row.kind == "reference" or row.readOnlyRouteFallback == true) and
            STEP_STATUS.reference or STEP_STATUS[row.status] or STEP_STATUS.upcoming
        if row.status == "upcoming" and row.kind ~= "reference" and row.readOnlyRouteFallback ~= true then
            upcomingSeen = upcomingSeen + 1
            if upcomingSeen > 1 then def = { label = "LATER", tone = "muted" } end
        end
        local status = self:Tone(def.label, def.tone)
        local title = self:Entity(row.title or "Profession step")
        local detail
        if row.kind == "train" then
            detail = string.format("Cap %d -> %d", tonumber(row.cap) or 0, tonumber(row.nextCap) or 300)
        else
            detail = string.format("Skill %d -> %d", tonumber(row.fromSkill) or 0, tonumber(row.toSkill) or 0)
        end
        lines[#lines + 1] = status .. "  " .. title
        lines[#lines + 1] = "      " .. self:Tone(detail, "muted")
    end
    if #lines == 0 then
        if model.status=="reference-only" then
            return appendCoverage(self:Tone("Reference available; no complete verified skill-step route documented.","gold"),coverage,false)
        end
        return appendCoverage(self:Tone("No route steps available.", "muted"),coverage,false)
    end
    return appendCoverage(table.concat(lines, "\n"),coverage,false)
end

function Format:StepProgressionCompact(model)
    if not model then return self:Tone("Route unavailable", "muted") end
    local coverage=self:StepCoverage(model,true)
    if model.status == "unavailable" then
        return appendCoverage(self:Tone("Route unavailable", "muted"),coverage,true)
    end
    if model.status == "complete" then
        return appendCoverage(self:Tone("Route complete", "good"),coverage,true)
    end
    if model.status=="reference-only" and (model.total or 0)==0 then
        return appendCoverage(self:Tone("Guide reference only - verify live steps", "gold"),coverage,true)
    end
    local current = model.current
    local title = current and current.title or "Current step"
    local label=model.status=="reference-only" and "Reference band" or "Route"
    return appendCoverage(self:Label(label, string.format("Step %d/%d", model.currentIndex or 0, model.total or 0), "cyan") .. "   " .. self:Tone(title, "muted"),coverage,true)
end

JLP.UIContentFormat = Format
