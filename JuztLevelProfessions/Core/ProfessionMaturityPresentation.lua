local _, JLP = ...
-- UI-only explanation: permissions come exclusively from existing authority
-- policies and NativeDispatchService. Never infer native eligibility here.
local Presentation={contract="jlp-profession-maturity-presentation-v1",nativeDispatchAllowed=false}
function Presentation:Build(key)
    local registry=JLP:GetModule("ProfessionRegistry")
    local def=registry and registry:Get(key)
    if not def then
        return {contract=self.contract,kind="UNAVAILABLE",label="UNKNOWN",detail="No verified profession capability.",tone="warn",nativeDispatchAllowed=false}
    end
    local maturity=def.maturity or {}
    local kind,label,detail,tone
    if maturity.production==true then
        kind="GUARDED_PRODUCTION";label="GUARDED PRODUCTION";tone="good"
        detail="Crafting requires explicit user action, current-build evidence and the existing native authority gates. Not automatically approved."
    elseif maturity.candidate==true then
        kind="CANDIDATE_READONLY";label="CANDIDATE · READ-ONLY";tone="gold"
        detail="General profession workflow is available. Research candidates remain read-only until live proof and native authorization are satisfied."
    elseif def.capabilities and (def.capabilities.mapRoutes or def.capabilities.mapAreas) then
        kind="ADVISORY_GATHERING";label="GATHERING · ADVISORY";tone="gold"
        detail="General gathering workflow is available. Node/area references do not prove current spawns, automatic gathering or yields."
    else
        kind="RESEARCH_READONLY";label="RESEARCH · READ-ONLY";tone="gold"
        detail="General workflow is available. Historical references do not authorize native crafting."
    end
    return {contract=self.contract,professionKey=def.key,kind=kind,label=label,detail=detail,tone=tone,
        nativeDispatchAllowed=false,productionCapabilityDeclared=maturity.production==true}
end
function Presentation:Summary(key)
    local item=self:Build(key)
    return item.label.." · "..item.detail
end
JLP:RegisterModule("ProfessionMaturityPresentation",Presentation)
