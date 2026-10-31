local _, JLP = ...
-- Entirely optional, transient read-only inspection of an open merchant/trainer.
-- Source availability is advisory; missing/inconsistent NPC data never becomes
-- a validation or promotion requirement and never rewrites Wowhead evidence.
local Service={contract="optional-npc-profession-snapshot-v1",persisted=false,nativeDispatchAllowed=false,optional=true}
local function safe(fn,...)
    if type(fn)~="function" then return nil end
    local ok,result=pcall(fn,...)
    if ok then return result end
    return nil
end
local function npcIDFromGUID(guid)
    if type(guid)~="string" then return nil end
    local value=guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    return tonumber(value)
end
function Service:Capture()
    local guid=safe(UnitGUID,"npc")
    local snapshot={contract=self.contract,optional=true,source="client-advisory",npcGUID=guid,
        npcID=npcIDFromGUID(guid),items={},trainerRows={},nativeDispatchAllowed=false,persisted=false}
    local merchantCount=tonumber(safe(GetMerchantNumItems)) or 0
    local trainerCount=tonumber(safe(GetNumTrainerServices)) or 0
    if merchantCount>0 then
        snapshot.state="MERCHANT_SNAPSHOT"
        for i=1,math.min(merchantCount,300) do
            local itemID=tonumber(safe(GetMerchantItemID,i))
            local name,price,numAvailable,usable=nil,nil,nil,nil
            if type(GetMerchantItemInfo)=="function" then
                local ok,n,_,cost,_,available,canUse=pcall(GetMerchantItemInfo,i)
                if ok then name=n; price=cost; numAvailable=available; usable=canUse end
            end
            if itemID or name then snapshot.items[#snapshot.items+1]={itemID=itemID,name=name,slot=i,
                price=price,available=numAvailable,usable=usable} end
        end
    elseif trainerCount>0 then
        snapshot.state="TRAINER_SNAPSHOT"
        for i=1,math.min(trainerCount,300) do
            local name=safe(GetTrainerServiceInfo,i)
            if name then snapshot.trainerRows[#snapshot.trainerRows+1]={name=name,slot=i,
                requiredSkill=tonumber(safe(GetTrainerServiceSkillReq,i)),
                requiredLevel=tonumber(safe(GetTrainerServiceLevelReq,i)),
                trainingCost=tonumber(safe(GetTrainerServiceCost,i))} end
        end
    else snapshot.state="NO_OPEN_NPC_WINDOW" end
    snapshot.observedCount=#snapshot.items+#snapshot.trainerRows
    return snapshot
end
function Service:CompareWithPublishedSources(snapshot)
    snapshot=type(snapshot)=="table" and snapshot or self:Capture()
    local references=JLP.data and JLP.data.recipeAccessSources and JLP.data.recipeAccessSources.requirements or {}
    local observed,byItem={},{}
    for _,item in ipairs(snapshot.items or {}) do if item.itemID then byItem[item.itemID]=true end end
    for _,ref in pairs(references) do
        for _,source in ipairs(ref.sources or {}) do
            if snapshot.npcID and tonumber(source.npcID)==snapshot.npcID and source.sourceType=="vendor" then
                observed[#observed+1]={itemID=ref.itemID,referenceEligible=source.referenceEligible==true,
                    observed=byItem[tonumber(ref.itemID)]==true}
            end
        end
    end
    return {contract="optional-npc-public-reference-comparison-v1",optional=true,
        state=snapshot.state,rows=observed,canBlockValidation=false,nativeDispatchAllowed=false,persisted=false}
end
function Service:GetSummary()
    local snapshot=self:Capture()
    local report=self:CompareWithPublishedSources(snapshot)
    return "Optional NPC snapshot · "..snapshot.state.." · observed "..snapshot.observedCount..
        " · reference comparisons "..#report.rows.." · informational only; not a validation requirement"
end
JLP:RegisterModule("OptionalNPCSnapshot",Service)
