local _, JLP = ...

-- Alpha103 promotes the real production Tailoring route into the existing
-- target-aware Auto Route lifecycle. This module owns only the Tailoring
-- feature gate/capability decision; it never dispatches native crafting itself.
-- The shared Auto Route orchestrator remains the runtime/session owner and every
-- irreversible ordinal still crosses ProductionTailoringNativeExecutionAuthority.
local ProductionTailoringAutoRouteAuthority = {
    contract = "production-tailoring-auto-route-authority-v1",
    promotionContract = "production-tailoring-auto-route-controlled-promotion-v1",
    authority = "feature-gated-explicit-guide-click-production-tailoring-auto-route-v1",
    professionKey = "TAILORING",
    persisted = false,
    automaticResume = false,
    automaticNonCraftActions = false,
    nativeDispatchAllowed = false,
    nativeDispatchPerOrdinal = 1,
    crossRecipeRequiresTarget = true,
    safetyCraftCap = 250,
}

local function normalizeKey(value)
    local key = tostring(value or ""):upper()
    return key ~= "" and key or nil
end

local function profile()
    local p = JLP.DB and JLP.DB.profile
    return p and p.productionTailoringAutoRouteAuthority or nil
end

function ProductionTailoringAutoRouteAuthority:IsSupported(professionKey)
    professionKey = normalizeKey(professionKey)
    if professionKey ~= self.professionKey then return false end
    local native = JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
    local consumer = JLP:GetModule("ResearchPlannerConsumerBridge")
    local readiness = JLP:GetModule("ResearchExecutionReadiness")
    return native and native.IsSupported and native:IsSupported(professionKey)
        and consumer and consumer.IsSupported and consumer:IsSupported(professionKey)
        and readiness and readiness.IsSupported and readiness:IsSupported(professionKey)
        or false
end

function ProductionTailoringAutoRouteAuthority:IsFeatureEnabled()
    local p = profile()
    return p and p.enabled == true or false
end

function ProductionTailoringAutoRouteAuthority:GetSafetyCraftCap()
    local p = profile()
    local cap = math.floor(tonumber(p and p.safetyCraftCap) or self.safetyCraftCap)
    if cap < 1 then cap = 1 end
    if cap > self.safetyCraftCap then cap = self.safetyCraftCap end
    return cap
end

function ProductionTailoringAutoRouteAuthority:IsEffectiveEnabled()
    if not self:IsFeatureEnabled() or not self:IsSupported(self.professionKey) then return false end
    local adapter = JLP:GetModule("ProductionTailoringAuthorityAdapter")
    local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
    local native = JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
    return adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled()
        and eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()
        and native and native.IsEffectiveEnabled and native:IsEffectiveEnabled()
        or false
end

function ProductionTailoringAutoRouteAuthority:SetFeatureEnabled(enabled)
    local p = profile()
    if not p then return false, "profile-unavailable" end
    if enabled == true then
        if not self:IsSupported(self.professionKey) then
            return false, "production-tailoring-auto-route-profession-unsupported"
        end
        local adapter = JLP:GetModule("ProductionTailoringAuthorityAdapter")
        if not (adapter and adapter.IsFeatureEnabled and adapter:IsFeatureEnabled()) then
            return false, "production-tailoring-authority-gate-disabled"
        end
        local eligibility = JLP:GetModule("ResearchExecutionAuthorityGate")
        if not (eligibility and eligibility.IsFeatureEnabled and eligibility:IsFeatureEnabled()) then
            return false, "execution-authority-eligibility-gate-disabled"
        end
        local native = JLP:GetModule("ProductionTailoringNativeExecutionAuthority")
        if not (native and native.IsEffectiveEnabled and native:IsEffectiveEnabled()) then
            return false, "production-tailoring-native-execution-authority-disabled"
        end
    end

    p.enabled = enabled == true
    if not p.enabled then
        local autoRoute = JLP:GetModule("ResearchAutoRouteOrchestrator")
        if autoRoute and autoRoute.Cancel then
            autoRoute:Cancel(self.professionKey, "production-tailoring-auto-route-feature-gate-disabled")
        end
    end
    if JLP.EventBus and JLP.EventBus.Emit then
        JLP.EventBus:Emit("PRODUCTION_TAILORING_AUTO_ROUTE_AUTHORITY_UPDATED", { enabled=p.enabled })
        JLP.EventBus:Emit("SETTINGS_CHANGED", "productionTailoringAutoRouteAuthority", p.enabled)
    end
    return true, p.enabled and "enabled" or "disabled"
end

function ProductionTailoringAutoRouteAuthority:GetSummary()
    local autoRoute = JLP:GetModule("ResearchAutoRouteOrchestrator")
    local active = autoRoute and autoRoute.GetSession and autoRoute:GetSession(self.professionKey) or nil
    local last = autoRoute and autoRoute.GetLast and autoRoute:GetLast(self.professionKey) or nil
    local lines = {
        "PRODUCTION TAILORING / AUTO ROUTE CONTROLLED PROMOTION",
        self.professionKey,
        "Contract: " .. self.contract,
        "Promotion contract: " .. self.promotionContract,
        "Feature gate: " .. (self:IsFeatureEnabled() and "enabled" or "disabled"),
        "Effective authority: " .. (self:IsEffectiveEnabled() and "enabled" or "disabled"),
        "Native primitive: Production Tailoring Craft One only",
        "Native dispatch per ordinal: 1",
        "Cross-recipe handoff: previous target + verified post-settlement route handoff",
        "Fresh restart source hardening: production-tailoring-auto-route-fresh-restart-hardening-v1",
        "Prior source/session reuse: forbidden",
        "Non-craft actions: stop and hand off to Guide",
        "Safety craft cap: " .. tostring(self:GetSafetyCraftCap()),
        "Automatic resume: disabled",
        "Automatic trainer/material actions: disabled",
        "Persistence: none",
        "Current session: " .. tostring(active and active.state or "none"),
        "Last state: " .. tostring(last and last.state or "none"),
    }
    return table.concat(lines, "\n")
end

function ProductionTailoringAutoRouteAuthority:Validate()
    local errors, warnings = {}, {}
    if self.persisted ~= false then errors[#errors+1] = "production Tailoring Auto Route authority must not persist" end
    if self.automaticResume ~= false then errors[#errors+1] = "production Tailoring Auto Route must not auto-resume" end
    if self.automaticNonCraftActions ~= false then errors[#errors+1] = "production Tailoring Auto Route must not automate non-craft actions" end
    if self.nativeDispatchAllowed ~= false then errors[#errors+1] = "production Tailoring Auto Route gate must not dispatch native crafting itself" end
    if self.nativeDispatchPerOrdinal ~= 1 then errors[#errors+1] = "production Tailoring Auto Route must remain one native craft per ordinal" end
    if self.crossRecipeRequiresTarget ~= true then errors[#errors+1] = "production Tailoring Auto Route cross-recipe changes must require target completion" end
    for _, name in ipairs({
        "ProductionTailoringAuthorityAdapter",
        "ProductionTailoringExecutionReadiness",
        "ProductionTailoringNativeExecutionAuthority",
        "ResearchExecutionAuthorityGate",
        "ResearchPlannerConsumerBridge",
        "ResearchExecutionReadiness",
        "ResearchAutoRouteOrchestrator",
        "ProductionTailoringAutoRouteRestart",
    }) do
        if not JLP:GetModule(name) then errors[#errors+1] = "production Tailoring Auto Route dependency missing: " .. name end
    end
    return #errors == 0, errors, warnings
end

JLP:RegisterModule("ProductionTailoringAutoRouteAuthority", ProductionTailoringAutoRouteAuthority)
