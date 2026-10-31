local _, JLP = ...
local AcquisitionSession = {}

local SESSION_ORDER = { bank=1, vendor=2, review=3, auction=4, craft=5 }
local LABELS = {
    bank = "Bank Pickup",
    vendor = "Vendor Purchase",
    auction = "Auction House",
    review = "Self-found source review (AH unapproved)",
    craft = "Craft Preparation",
}

local function money(value)
    if type(value)~="number" or value~=value or value<0 or value==math.huge then return "price unknown" end
    local optimizer = JLP:GetModule("CostOptimizer")
    if optimizer and optimizer.Money then return optimizer:Money(tonumber(value) or 0) end
    return tostring(tonumber(value) or 0)
end

local function addRow(session, row)
    session.rows[#session.rows + 1] = row
    session.itemCount = session.itemCount + 1
    session.unitCount = session.unitCount + math.max(0, math.floor(tonumber(row.quantity) or 0))
    if row.priceKnown==true and type(row.cost)=="number" and row.cost>=0 and row.cost<math.huge then
        session.knownCost=session.knownCost+row.cost
        session.pricedRows=session.pricedRows+1
        if (session.kind=="vendor" or session.kind=="auction") and
            (tonumber(row.pricedQuantity) or tonumber(row.requiredQuantity) or tonumber(row.quantity) or 0)<
            (tonumber(row.requiredQuantity) or tonumber(row.quantity) or 0) then session.unpricedRows=session.unpricedRows+1 end
    elseif session.kind=="vendor" or session.kind=="auction" then session.unpricedRows=session.unpricedRows+1 end
    if row.complete == false then session.complete = false end
end

local function makeSession(kind)
    return {
        kind = kind,
        label = LABELS[kind] or kind,
        rows = {},
        itemCount = 0,
        unitCount = 0,
        knownCost = 0,
        pricedRows=0,
        unpricedRows=0,
        complete = true,
    }
end

local function bankRows(plan)
    local rows = {}
    for _, req in ipairs((plan and plan.requirements) or {}) do
        local storage = req.storage or {}
        local bags = storage.bagKnown~=false and tonumber(storage.bags) or nil
        local bank = storage.bankKnown~=false and tonumber(storage.bank) or nil
        local required = tonumber(req.required) or 0
        -- A bank pickup amount is never derived from an unknown bag total.
        -- Keep it out of actionable sessions until the owner checks inventory.
        local retrieve = bags and bank and bags>=0 and bank>=0 and
            math.min(math.floor(bank),math.max(0,required-math.floor(bags))) or 0
        if retrieve > 0 then
            rows[#rows + 1] = {
                itemID = req.itemID,
                name = req.name,
                quantity = retrieve,
                source = "bank",
                complete = true,
                detail = string.format("%d in bags | %d in bank | %d needed for scope", bags, bank, required),
            }
        end
    end
    table.sort(rows, function(a,b) return tostring(a.name) < tostring(b.name) end)
    return rows
end

local function shoppingRows(plan, source)
    local rows = {}
    for _, item in ipairs((plan and plan.shopping) or {}) do
        if (source=="review" and item.exceptionPending) or
            (item.source==source and not item.exceptionPending) then
            rows[#rows + 1] = {
                itemID = item.itemID,
                name = item.name,
                quantity = item.purchasedQuantity or item.missing,
                requiredQuantity=item.missing,
                excessQuantity=item.excessQuantity,
                source = source,
                originalSource = item.source,
                cost = item.cost,
                priceKnown=item.priceKnown==true and type(item.cost)=="number" and item.cost==item.cost and item.cost>=0 and item.cost<math.huge,
                pricedQuantity=item.pricedQuantity,
                complete = item.complete,
                note = item.note,
                exceptionPending = item.exceptionPending == true,
                approvalGranted = item.approvalGranted == true,
                detail = item.storage and ("Bags "..tostring(item.storage.bags or "unknown")..
                    " | bank "..tostring(item.storage.bankKnown==false and "unknown" or (item.storage.bank or "unknown"))..
                    " | owned counts subject to verification") or nil,
            }
        end
    end
    table.sort(rows, function(a,b) return tostring(a.name) < tostring(b.name) end)
    return rows
end

local function craftRows(plan)
    local rows = {}
    for _, action in ipairs((plan and plan.actions) or {}) do
        if action.kind == "craft-intermediate" or action.kind == "craft-tool" or action.kind == "tailoring-disenchant" then
            rows[#rows + 1] = {
                itemID = action.itemID or action.materialID,
                name = action.name or "Craft preparation",
                quantity = tonumber(action.quantity) or tonumber(action.crafts) or 1,
                source = "craft",
                complete = true,
                detail = action.expected and string.format("Expected output: %.2f", tonumber(action.expected) or 0) or nil,
            }
        end
    end
    return rows
end

local function stationMatchesSession(station, kind)
    station = tostring(station or "world")
    if kind == "bank" then return station == "bank" end
    if kind == "vendor" then return station == "vendor" end
    if kind == "auction" then return station == "auction" end
    if kind == "craft" then return station:match("^craft:") ~= nil end
    return false
end

function AcquisitionSession:QualifySources(plan)
    local resolver=JLP:GetModule("PriceResolver")
    local quote=nil
    if type(resolver)=="table" and type(resolver.QualifySnapshot)=="function" then
        local ok,result=pcall(resolver.QualifySnapshot,resolver)
        if ok and type(result)=="table" then quote=result end
    end
    quote=quote or {status="UNKNOWN",usable=false,readOnly=true,
        trustedForCostEstimate=false,displayableAdvisory=false}
    local unknownBank,unknownBags,knownBank,knownBags,required=0,0,0,0,0
    for _,req in ipairs(type(plan)=="table" and type(plan.requirements)=="table" and plan.requirements or {}) do
        if type(req)=="table" then
        local storage=type(req.storage)=="table" and req.storage or {}
        local availability=type(req.availability)=="table" and req.availability or nil
        required=required+math.max(0,tonumber(req.required) or 0)
        -- RequirementPlan is the owner of per-step availability. Use its
        -- qualified values when present, not an inconsistent second estimate.
        local bagValue=storage.bags
        local bankValue=storage.bank
        if availability~=nil then bagValue=availability.bags; bankValue=availability.bank end
        local bagUnknown=availability~=nil and availability.unknownBags==true or
            (availability==nil and storage.bagKnown==false)
        local bankUnknown=availability~=nil and availability.unknownBank==true or
            (availability==nil and storage.bankKnown==false)
        if bagUnknown or type(bagValue)~="number" or bagValue~=bagValue or bagValue<0 or bagValue==math.huge then unknownBags=unknownBags+1
        else knownBags=knownBags+math.floor(bagValue) end
        if bankUnknown or type(bankValue)~="number" or bankValue~=bankValue or bankValue<0 or bankValue==math.huge then unknownBank=unknownBank+1
        else knownBank=knownBank+math.floor(bankValue) end
        end
    end
    return {contract="jlp-acquisition-source-qualification-v1",readOnly=true,
        nativeDispatchAllowed=false,auction=quote,bankUnknownTypes=unknownBank,
        bankKnownUnits=knownBank,bags=knownBags,bagUnknownTypes=unknownBags,requiredUnits=required,
        altBankCountsAsAvailable=false,quotePolicy=quote.trustedForCostEstimate and "COST_ESTIMATE" or
            (quote.displayableAdvisory and "ADVISORY_ONLY" or "DO_NOT_QUOTE"),
        nextManualAction=unknownBags>0 and "Verify bag quantities manually" or
            unknownBank>0 and "Open current character bank manually" or
            (not quote.trustedForCostEstimate and "Manually verify Auction House scan and material sources" or
                "Review qualified sources before any manual acquisition")}
end
function AcquisitionSession:FormatSources(model)
    if type(model)~="table" then return "Sources unavailable; verify materials manually" end
    local quote=type(model.auction)=="table" and model.auction or {}
    local scope=quote.realm and (tostring(quote.realm).." / "..tostring(quote.faction or "unknown faction")) or "no AH snapshot"
    local bank=(tonumber(model.bankUnknownTypes) or 0)>0 and (tostring(model.bankUnknownTypes).." bank type(s) unknown") or
        (tostring(model.bankKnownUnits or 0).." units in known bank")
    local policy=quote.trustedForCostEstimate and "verified cost estimate" or
        (quote.displayableAdvisory and "advisory quote only; manual verification needed" or "quote unavailable")
    local bags=(tonumber(model.bagUnknownTypes) or 0)>0 and (" | "..tostring(model.bagUnknownTypes).." bag type(s) unknown") or ""
    return "Source quality: AH "..tostring(quote.status or "UNKNOWN").." ("..scope..") | "..bank..bags..
        " | "..policy.." | Next: "..tostring(model.nextManualAction or "Review sources manually")..
        " | other characters advisory only"
end
function AcquisitionSession:FormatRouteCoverage(model)
    if type(model)~="table" or model.routeCoverageIncomplete~=true then return nil end
    local parts={}
    for _,issue in ipairs(model.routeCoverageIssues or {}) do
        parts[#parts+1]=tostring(issue.profession or "Primary profession")..
            ": "..tostring(issue.reason or issue.status or "route unavailable")..
            ". Next: "..tostring(issue.nextAction or "Verify profession data")
    end
    for _,gap in ipairs(model.routeCoverageGaps or {}) do
        parts[#parts+1]=string.format("%s skill %d-%d: %s. Next: verify qualified progression steps.",
            tostring(gap.profession or "Profession"),tonumber(gap.fromSkill) or 0,
            tonumber(gap.toSkill) or 0,tostring(gap.reason or "NO_QUALIFIED_ROUTE_STEP"))
    end
    return #parts>0 and table.concat(parts,"; ") or
        "Unqualified route coverage. Next: verify profession route data."
end

function AcquisitionSession:Build(plan)
    local acquisition = JLP:GetModule("AcquisitionPlanner")
    plan = plan or (acquisition and acquisition:BuildSelected())
    if not plan then return { status="unavailable", sessions={}, currentIndex=0 } end

    local byKind = {
        bank = makeSession("bank"),
        vendor = makeSession("vendor"),
        auction = makeSession("auction"),
        review = makeSession("review"),
        craft = makeSession("craft"),
    }

    for _, row in ipairs(bankRows(plan)) do addRow(byKind.bank, row) end
    for _, row in ipairs(shoppingRows(plan, "vendor")) do addRow(byKind.vendor, row) end
    for _, row in ipairs(shoppingRows(plan, "auction")) do addRow(byKind.auction, row) end
    for _, row in ipairs(shoppingRows(plan, "review")) do addRow(byKind.review, row) end
    for _, row in ipairs(craftRows(plan)) do addRow(byKind.craft, row) end

    local sessions = {}
    for kind, session in pairs(byKind) do
        if #session.rows > 0 then
            if kind=="review" and plan.strategy=="self_found" then
                for _,row in ipairs(session.rows) do
                    if row.exceptionPending then
                        session.exceptionPending=true
                        session.complete=false
                        session.label="Self-found: source review (AH unapproved)"
                        break
                    end
                end
            end
            sessions[#sessions + 1] = session
        end
    end
    table.sort(sessions, function(a,b) return (SESSION_ORDER[a.kind] or 99) < (SESSION_ORDER[b.kind] or 99) end)

    local flow = JLP:GetModule("ExecutionFlow")
    local station = flow and flow:GetCurrentStation() or "world"
    local currentIndex = (#sessions > 0) and 1 or 0
    local currentReason = #sessions > 0 and "next" or "complete"

    -- A session is derived from live requirements. When its rows are satisfied it
    -- disappears on the next rebuild, which advances the model without manual state.
    -- If the player is already at a useful station, prefer that pending session now.
    for i, session in ipairs(sessions) do
        session.station = session.kind=="review" and "world" or session.kind
        session.availableHere = not session.exceptionPending and stationMatchesSession(station, session.kind) or false
        session.status = "pending"
        if session.availableHere then
            currentIndex = i
            currentReason = "here-now"
            break
        end
    end
    if sessions[currentIndex] then sessions[currentIndex].status = "current" end

    local totalKnownCost, unresolved,pricedRows,unpricedRows = 0, 0,0,0
    for _, session in ipairs(sessions) do
        totalKnownCost = totalKnownCost + (session.knownCost or 0)
        pricedRows=pricedRows+session.pricedRows;unpricedRows=unpricedRows+session.unpricedRows
        session.priceKnown=session.pricedRows>0
        session.priceComplete=session.pricedRows>0 and session.unpricedRows==0
        if not session.complete then unresolved = unresolved + 1 end
    end

    local noPrimary=#(plan.routeCoverageIssues or {})==1 and
        plan.routeCoverageIssues[1].status=="NO_ACTIVE_PRIMARY_PROFESSION"
    if #sessions==0 and plan.routeCoverageIncomplete then
        currentReason=noPrimary and "select-profession" or "verify-route"
    end
    return {
        status = #sessions > 0 and "active" or noPrimary and "profession-unavailable" or
            plan.routeCoverageIncomplete and "route-incomplete" or "complete",
        scope = plan.scope,
        scopeLabel = plan.scopeLabel,
        strategy = plan.strategy,
        sessions = sessions,
        currentIndex = currentIndex,
        current = sessions[currentIndex],
        currentReason = currentReason,
        currentStation = station,
        totalKnownCost = totalKnownCost,
        priceKnown=pricedRows>0,
        priceComplete=pricedRows>0 and unpricedRows==0,
        costKnowledge={status=pricedRows==0 and "UNKNOWN" or unpricedRows>0 and "PARTIAL" or "COMPLETE",knownCost=totalKnownCost,pricedRows=pricedRows,unpricedRows=unpricedRows},
        unresolvedSessions = unresolved,
        remainingSessions = #sessions,
        progressive = true,
        locationAware = true,
        plan = plan,
        sourceQualification = self:QualifySources(plan),
        routeCoverageIncomplete=plan.routeCoverageIncomplete==true,
        routeCoverageGaps=plan.routeCoverageGaps or {},
        routeCoverageIssues=plan.routeCoverageIssues or {},
        contract = "progressive-location-aware-acquisition-sessions",
    }
end

function AcquisitionSession:FormatCompact(model)
    model = model or self:Build()
    if not model or model.status == "unavailable" then return "Acquisition sessions: unavailable" end
    if model.status == "complete" then return "Acquisition sessions: complete - no material stops required" end
    if model.status == "route-incomplete" or model.status == "profession-unavailable" then
        return (model.status=="profession-unavailable" and "Acquisition sessions: no active primary - " or
            "Acquisition sessions: route incomplete - ")..
            tostring(self:FormatRouteCoverage(model) or "verify profession data")
    end
    local current = model.current
    local reason = model.currentReason == "here-now" and "available here now" or "next stop"
    return string.format(
        "Acquisition sessions: %d remaining | %s: %s",
        #model.sessions,
        reason,
        current and current.label or "Complete"
    ) .. (model.routeCoverageIncomplete and (" | ROUTE INCOMPLETE: "..
        tostring(self:FormatRouteCoverage(model))) or "")
end

function AcquisitionSession:Format(model, maxRows)
    model = model or self:Build()
    if not model or model.status == "unavailable" then return "ACQUISITION SESSIONS\nUnavailable." end
    if model.status == "complete" then return "ACQUISITION SESSIONS\nNo material acquisition stops are required for this scope." end
    if model.status == "route-incomplete" or model.status == "profession-unavailable" then
        return "ACQUISITION SESSIONS\nRoute incomplete; "..
            tostring(self:FormatRouteCoverage(model))
    end
    maxRows = math.max(1, math.floor(tonumber(maxRows) or 3))
    local lines = {
        "ACQUISITION SESSIONS",
        string.format("Scope: %s | %d session%s remaining | %s", tostring(model.scopeLabel or "Current Segment"), #model.sessions, #model.sessions == 1 and "" or "s", model.currentReason == "here-now" and "current location can complete this stop" or "next stop selected"),
    }
    if model.routeCoverageIncomplete then
        lines[#lines+1]="Warning: the selected route does not cover the full skill target; remaining material sessions are advisory only. "..
            tostring(self:FormatRouteCoverage(model))
    end
    for i, session in ipairs(model.sessions) do
        local marker = i == model.currentIndex and ">" or " "
        local cost=""
        if session.kind=="vendor" or session.kind=="auction" then
            cost=" | "..(session.pricedRows==0 and "price unknown" or
                money(session.knownCost)..(session.unpricedRows>0 and " known; additional prices unknown" or ""))
        end
        lines[#lines + 1] = string.format("%s %d. %s | %d item%s | %d unit%s%s", marker, i, session.label, session.itemCount, session.itemCount == 1 and "" or "s", session.unitCount, session.unitCount == 1 and "" or "s", cost)
        for rowIndex, row in ipairs(session.rows) do
            if rowIndex > maxRows then
                lines[#lines + 1] = string.format("    + %d more item%s", #session.rows - maxRows, (#session.rows - maxRows) == 1 and "" or "s")
                break
            end
            local suffix = row.exceptionPending and (" | "..tostring(row.note or "AH exception pending")) or
                row.priceKnown==true and (" | " .. money(row.cost)..(row.complete==false and " known (partial)" or "")) or
                (row.source=="vendor" or row.source=="auction") and (" | price unknown"..(row.note and (": "..tostring(row.note)) or "")) or
                row.note and (" | "..tostring(row.note)) or ""
            if (tonumber(row.excessQuantity) or 0)>0 then suffix=suffix.." | "..tostring(row.excessQuantity).." excess from whole listings" end
            lines[#lines + 1] = string.format("    %s x%d%s", tostring(row.name or "Item"), math.max(1, math.floor(tonumber(row.quantity) or 1)), suffix)
        end
    end
    return table.concat(lines, "\n")
end

function AcquisitionSession:GetSummary()
    return self:Format(self:Build(), 2)
end

JLP:RegisterModule("AcquisitionSession", AcquisitionSession)
