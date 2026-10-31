local _, JLP = ...
local ActionAssist = {}

local function registry() return JLP:GetModule("ProfessionRegistry") end
local function productionKeys()
    local reg=registry()
    return reg and reg:GetWorkflowKeys("executionFlow") or {}
end

local AH_KINDS = {
    ["acquire-material"] = true,
    ["acquire-raw"] = true,
    ["acquire-tool-material"] = true,
}

local BANK_KINDS = {
    ["retrieve-material"] = true,
    ["retrieve-raw"] = true,
    ["retrieve-tool"] = true,
    ["retrieve-tool-material"] = true,
}

local function professionLabel(key, plan)
    if plan and plan.profession and plan.profession.name then return plan.profession.name end
    local reg=registry()
    return reg and reg:GetDisplayNameOrKey(key) or tostring(key or "Unknown profession")
end

local function resolveSource(key, plan, action)
    if action and action.sourceInfo then return action.sourceInfo end
    if not plan or not plan.step then return nil end
    local resolver = JLP:GetModule("SourceResolver")
    if plan.actionKind == "train" then
        return plan.step.sourceInfo or (resolver and resolver:GetTrainerForGate(key, plan.step.trainer))
    end
    if plan.actionKind == "craft" and action and action.kind == "learn-recipe" then
        return plan.step.sourceInfo or (resolver and resolver:GetRecipeSource(key, plan.step.recipe))
    end
    if action and tostring(action.source or "") == "vendor" and resolver and resolver.GetVendorSource then
        return resolver:GetVendorSource(key, action.itemName)
    end
    return nil
end

local function bankDetail(action)
    local quantity = math.max(1, math.floor(tonumber(action and action.quantity) or 1))
    local name = action and action.itemName or nil
    if not name and action and action.text then
        name = tostring(action.text):match("Retrieve (.-) x%d+ from the bank") or tostring(action.text):match("Retrieve (.-) from the bank")
    end
    return string.format(
        "Bank retrieval required: %s x%d. Open your bank and move the item to your bags; the action queue will advance automatically.",
        tostring(name or "required item"), quantity
    )
end

local function craftDetail(action, plan)
    local quantity = math.max(1, math.floor(tonumber(action and action.quantity) or 1))
    if action and action.kind == "craft-intermediate" then
        return string.format(
            "Intermediate batch: craft %d now. This batch is sized for the currently executable leveling batch and will be recalculated after inventory changes.",
            quantity
        )
    end
    if action and action.kind == "craft-tool" then
        return "Craft this profession tool once; it is treated as a reusable prerequisite rather than a per-craft material."
    end
    if action and action.kind == "craft-leveling" then
        local remaining = plan and plan.step and tonumber(plan.step.remainingCrafts) or quantity
        return string.format(
            "Leveling batch: up to %d craft%s in the current executable batch. Route estimate remaining: %d. Skill gains are tracked live.",
            quantity, quantity == 1 and "" or "s", math.max(0, math.floor(remaining or 0))
        )
    end
    return action and action.detail or nil
end

function ActionAssist:Get(key, plan, queue)
    local api=JLP:GetModule("ProfessionAPI")
    local ownership=api and api.GetOwnership and api:GetOwnership(key)
    if not (ownership and ownership.owned==true) then
        local state=ownership and ownership.state or "PROFESSION_OWNERSHIP_UNKNOWN"
        local reg=JLP:GetModule("ProfessionRegistry")
        local label=reg and reg:GetDisplayNameOrKey(key) or tostring(key)
        local text=state=="PROFESSION_NOT_LEARNED" and
            ("Learn "..label.." before JuztLevel can plan this profession.") or
            ("Verify learned "..label.." ownership before JuztLevel can plan this profession.")
        return {key=key,status=state,guidance=text,readOnly=true,nativeDispatchAllowed=false}
    end
    if queue == nil then
        local queueModule = JLP:GetModule("ActionQueue")
        queue = queueModule and queueModule:Build(key, plan) or nil
    end
    local action = queue and queue.actions and queue.actions[queue.currentIndex] or nil
    if not action then
        return {
            key = key,
            status = queue and queue.status or "unavailable",
            action = nil,
            queue = queue,
            detail = queue and queue.status == "complete" and "Profession route complete." or "No execution action is available.",
        }
    end

    local source = resolveSource(key, plan, action)
    local navigation = JLP:GetModule("Navigation")
    local canMap = source and navigation and navigation:CanNavigate(source,{category="CURRENT_STEP"}) and true or false
    local canAH = AH_KINDS[action.kind] and (action.source == "auction" or action.source == "disenchant-or-auction" or action.source == "unknown") and true or false
    local detail = action.detail
    local stateLabel = "Action"

    if BANK_KINDS[action.kind] then
        stateLabel = "Bank"
        detail = bankDetail(action)
    elseif action.kind == "craft-intermediate" or action.kind == "craft-leveling" or action.kind == "craft-tool" then
        stateLabel = "Craft"
        detail = craftDetail(action, plan)
    elseif canAH then
        stateLabel = "Acquisition"
        detail = string.format(
            "Auction guidance available for item %s x%d. Open the addon's Auction House page to compare the current shopping plan against the last successful snapshot.",
            tostring(action.itemID or "?"), math.max(1, math.floor(tonumber(action.quantity) or 1))
        )
    elseif action.kind == "verify-recipe" then
        stateLabel = "Recipe"
        detail = "Open the profession window manually. Once recipe knowledge is scanned, this verification action will clear automatically."
    elseif action.kind == "learn-recipe" then
        stateLabel = "Recipe source"
        detail = action.detail or "Obtain and learn the required recipe before continuing."
    elseif action.kind == "train-rank" then
        stateLabel = "Trainer"
        detail = action.detail or tostring(action.text)
    end

    return {
        key = key,
        profession = professionLabel(key, plan),
        status = "active",
        stateLabel = stateLabel,
        action = action,
        queue = queue,
        detail = detail,
        source = source,
        canMap = canMap,
        canAH = canAH,
        ahItemID = canAH and action.itemID or nil,
        ahQuantity = canAH and action.quantity or nil,
    }
end

function ActionAssist:OpenAHGuidance(assist)
    assist = assist or self.lastAssist
    if not assist or not assist.canAH then return false, "The current action has no Auction House guidance." end
    local acquisition = JLP:GetModule("AcquisitionPlanner")
    if acquisition then acquisition:SetSelectedScope("current") end
    if JLP.MainWindow then
        JLP.MainWindow:Create():Show()
        JLP.MainWindow:ShowPage("Auction House")
    end
    return true, "Opened Auction House guidance for the current acquisition action."
end

function ActionAssist:ShowSource(assist)
    assist = assist or self.lastAssist
    if not assist or not assist.canMap or not assist.source then return false, "The current action has no audited map source." end
    local navigation = JLP:GetModule("Navigation")
    if not navigation then return false, "Navigation unavailable." end
    return navigation:ShowSource(assist.source, { routeBound=true, sourceCategory="CURRENT_STEP" })
end

function ActionAssist:FormatCompact(assist)
    if not assist then return "Execution: unavailable" end
    if assist.status == "complete" then return "Execution: route complete" end
    local action = assist.action
    if not action then return "Execution: no current action" end
    local suffix = assist.canAH and " - AH guidance available" or assist.canMap and " - map source available" or ""
    return "Execution: " .. tostring(assist.stateLabel or "Action") .. suffix
end

function ActionAssist:Format(assist)
    if not assist then return "EXECUTION ASSISTANCE\nUnavailable." end
    if assist.status == "complete" then return "EXECUTION ASSISTANCE\nProfession route complete." end
    if not assist.action then return "EXECUTION ASSISTANCE\nNo current action." end
    local lines = {
        "EXECUTION ASSISTANCE",
        "Current: " .. tostring(assist.action.text or "Continue."),
    }
    if assist.detail and assist.detail ~= "" then lines[#lines + 1] = tostring(assist.detail) end
    if assist.canMap then lines[#lines + 1] = "Control: Show Source on Map" end
    if assist.canAH then lines[#lines + 1] = "Control: Open AH Guidance" end
    return table.concat(lines, "\n")
end

function ActionAssist:GetSummary()
    local planner = JLP:GetModule("Planner")
    local lines = {}
    for _, key in ipairs(productionKeys()) do
        local plan = planner and planner:GetProfessionPlan(key) or nil
        local assist = self:Get(key, plan)
        local label = professionLabel(key, plan)
        lines[#lines + 1] = label .. ": " .. self:FormatCompact(assist):gsub("^Execution:%s*", "")
    end
    return table.concat(lines, "\n")
end

do
 local build=ActionAssist.Get
 function ActionAssist:Get(key,plan,queue)
  local function evaluate() return build(self,key,plan,queue) end
  if JLP.MemoObservation and queue then return JLP:MemoObservation("action-assist",queue,evaluate) end
  return evaluate()
 end
end

JLP:RegisterModule("ActionAssist", ActionAssist)
