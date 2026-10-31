local _, JLP = ...
-- All inputs are gross counts. Cached alt stock is advisory until physically retrieved.
local Quantities={contract="canonical-acquisition-quantities-v1"}
local function n(value)
    local x=tonumber(value)
    if type(x)~="number" or x~=x or x<0 or x==math.huge then return nil end
    return math.floor(x)
end
local function observed(storage,field,flag)
    if storage[flag]==false then return nil,false end
    local count=n(storage[field])
    if count==nil then return nil,false end
    return count,true
end
function Quantities:Compute(required,storage,altBankAdvisory)
    storage=type(storage)=="table" and storage or {}
    local gross=n(required)
    if gross==nil then return nil,"INVALID_REQUIRED_QUANTITY" end
    local bags,bagKnown=observed(storage,"bags","bagKnown")
    local bank,bankKnown=observed(storage,"bank","bankKnown")
    local current=bagKnown and bankKnown and math.min(gross,bags+bank) or nil
    local immediate=bagKnown and math.max(0,gross-bags) or nil
    local prepared=bagKnown and bankKnown and math.max(0,gross-bags-bank) or nil
    local advisory=prepared and math.min(prepared,n(altBankAdvisory) or 0) or nil
    local lower=math.max(0,gross-(bags or 0)-(bank or 0))
    -- Unknown stock can cover all demand: zero lower bound; do not present
    -- an exact shortage, a cost quote, or a spurious shopping action.
    if not bagKnown or not bankKnown then lower=0 end
    return {
        contract=self.contract,grossRequired=gross,bagsAvailable=bags,
        bagKnown=bagKnown,bankKnown=bankKnown,inventoryKnown=bagKnown and bankKnown,
        state=bagKnown and bankKnown and "KNOWN" or "UNKNOWN",
        externalLowerBound=lower,externalUpperBound=gross,
        currentBankAvailable=bank,currentOwned=current,
        immediateMissing=immediate,preparedMissing=prepared,
        altBankAdvisory=advisory,externalRequired=prepared,
        externalRequiredIfTransferred=prepared and math.max(0,prepared-advisory) or nil,
        altBankCountsForReadiness=false,
    }
end
function Quantities:Validate()
    local r=self:Compute(72,{bags=10,bank=15},9)
    local zero=self:Compute(7,{bags=7,bank=0},99)
    local storage=self:Compute(7,{bags=0,bank=7},0)
    if r.grossRequired~=72 or r.immediateMissing~=62 or r.preparedMissing~=47 or r.externalRequired~=47 or r.externalRequiredIfTransferred~=38 then return {"baseline-72-25-9"} end
    if zero.externalRequired~=0 or zero.altBankAdvisory~=0 or storage.immediateMissing~=7 or storage.preparedMissing~=0 then return {"storage-partition"} end
    return {}
end
JLP:RegisterModule("AcquisitionQuantities",Quantities)
