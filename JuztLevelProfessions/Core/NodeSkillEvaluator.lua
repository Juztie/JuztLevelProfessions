local _, JLP = ...
-- Read-only thresholds from historical sources: colors are Classic reference
-- bands, never promises of actual skill gain per minute or current spawn status.
local Evaluator={contract="gathering-node-skill-evaluator-v1",nativeDispatchAllowed=false}
local function skill(n)
    return type(n)=="number" and n==n and n>=0 and n<math.huge and n==math.floor(n)
end
function Evaluator:Evaluate(record,currentSkill,mode)
    if type(record)~="table" or not skill(record.requiredSkill) then
        return {status="SKILL_REQUIREMENT_UNKNOWN",actionable=false,confidence="UNKNOWN"}
    end
    if not skill(currentSkill) then
        return {status="CURRENT_SKILL_UNKNOWN",requiredSkill=record.requiredSkill,
            actionable=false,confidence="UNKNOWN"}
    end
    if record.professionKey=="MINING"or record.professionKey=="HERBALISM"then
        local guide=JLP:GetModule(record.professionKey=="MINING"and "ForeverMiningNodeProgression210"or "ForeverHerbalismProgression209")
        local node=guide and guide:GetNodeContract(record.resourceKey,record.objectID)
        local eligible=node and currentSkill>=node.minimum or false
        local tier=node and node.gray and ((currentSkill>=node.gray and "GRAY")or
            (currentSkill>=node.green and "GREEN")or (currentSkill>=node.yellow and "YELLOW")or
            (currentSkill>=node.minimum and "ORANGE")or "RED")or "UNKNOWN"
        return {status=node and (eligible and "GATHERABLE_SKILL"or "NOT_GATHERABLE_YET")or "NODE_CONTRACT_UNKNOWN",
            requiredSkill=node and node.minimum or record.requiredSkill,currentRaw=currentSkill,colorBand=tier,
            displayVisible=true,actionable=eligible,smartEligible=mode=="SMART_PROFESSION"and eligible,
            progressionEligibility=tier=="UNKNOWN"and "UNKNOWN"or eligible and tier~="GRAY"and "POSSIBLE"or "NOT_EXPECTED",
            confidence=node and node.difficultyStatus or "UNKNOWN",skillUpProbability=nil,nativeDispatchAllowed=false}
    end
    local req=record.requiredSkill
    local color=(currentSkill<req and "RED") or
        (currentSkill<req+25 and "ORANGE") or (currentSkill<req+50 and "YELLOW") or
        (currentSkill<req+100 and "GREEN") or "GRAY"
    local eligible=currentSkill>=req
    local isSmart=mode=="SMART_PROFESSION"
    return {status=eligible and "GATHERABLE_SKILL" or "NOT_GATHERABLE_YET",
        requiredSkill=req,currentRaw=currentSkill,colorBand=color,
        displayVisible=true,actionable=eligible,smartEligible=isSmart and eligible or false,
        progressionEligibility=(color~="GRAY" and eligible) and "POSSIBLE" or "NOT_EXPECTED",
        confidence="CLASSIC_BAND_REFERENCE",nativeDispatchAllowed=false}
end
function Evaluator:EvaluateKnownProfession(record,mode)
    if type(record)~="table" then return self:Evaluate(record,nil,mode) end
    local api=JLP:GetModule("ProfessionAPI")
    local p=api and api.Get and api:Get(record.professionKey)
    -- Cached skill remains advisory, not proof of currently learned profession.
    local result=self:Evaluate(record,p and p.skill,mode)
    result.skillSource=p and (p.cached and "CACHED_ADVISORY" or "LIVE_PROFESSION") or "UNKNOWN"
    return result
end
JLP:RegisterModule("NodeSkillEvaluator",Evaluator)
