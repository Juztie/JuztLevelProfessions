local _, JLP = ...
local AuctionScanner = {
    isAuctionHouseOpen = false,
    scanInProgress = false,
    requestedAt = nil,
    staging = nil,
    scanCursor = 0,
    scanCount = 0,
    processedRows = 0,
    progressAt = nil,
    scanFrame = nil,
    lastScanIssue = nil,
}

local function now()
    if type(time) == "function" then
        local ok, v = pcall(time)
        if ok then
            local stamp=tonumber(v)
            if stamp and stamp==stamp and stamp~=math.huge and stamp~=-math.huge and stamp>=0 then
                return math.floor(stamp)
            end
        end
    end
    return 0
end

local function realmName()
    if type(GetRealmName) == "function" then
        local ok, value = pcall(GetRealmName)
        if ok and value then return value end
    end
    return "Unknown Realm"
end

local function factionName()
    if type(UnitFactionGroup) == "function" then
        local ok, value = pcall(UnitFactionGroup, "player")
        if ok and value then return value end
    end
    return "Unknown"
end

-- Retain bounded groups of identical BUYABLE listings. Rounded unit buckets
-- remain a display compatibility field; they cannot establish purchase cost.
local MAX_SAFE_INTEGER = 9007199254740991
local function positiveInteger(value)
    if type(value)~="number" or value~=value or value==math.huge or value==-math.huge or
        value<=0 or value>MAX_SAFE_INTEGER or value~=math.floor(value) then return nil end
    return value
end
local function priceBucketLimit()
    local n=JLP.Constants and JLP.Constants.MAX_PRICE_BUCKETS_PER_ITEM
    return type(n)=="number" and n>=1 and n<=64 and n==math.floor(n) and n or 48
end
local function displayUnitPrice(buyout,quantity)
    local value=buyout/quantity
    local unit=math.floor(value)
    if value-unit>=0.5 and unit<MAX_SAFE_INTEGER then unit=unit+1 end
    return math.max(1,unit)
end
local function recordPrice(row,buyout,quantity)
    local levels=row._priceMap
    local key=string.format("%.17g:%.17g",quantity,buyout)
    if levels[key] then
        levels[key].count=levels[key].count+1
        return
    end
    local listing={quantity=quantity,buyout=buyout,count=1}
    if row._levelCount<priceBucketLimit() then
        levels[key]=listing
        row._levelCount=row._levelCount+1
        return
    end
    local worst=nil
    for old,value in pairs(levels) do
        local prior=worst and levels[worst]
        if not prior or value.buyout/value.quantity>prior.buyout/prior.quantity or
            (value.buyout/value.quantity==prior.buyout/prior.quantity and value.buyout>prior.buyout) then worst=old end
    end
    local prior=worst and levels[worst]
    if prior and (buyout/quantity<prior.buyout/prior.quantity or
        (buyout/quantity==prior.buyout/prior.quantity and buyout<prior.buyout)) then
        levels[worst]=nil
        levels[key]=listing
    end
    row.priceCoverageTruncated=true
end
local function buildPriceBuckets(item)
    local list={}
    for _,listing in pairs(item._priceMap) do
        list[#list+1]=listing
    end
    table.sort(list,function(a,b)
        if a.buyout/a.quantity~=b.buyout/b.quantity then return a.buyout/a.quantity<b.buyout/b.quantity end
        if a.buyout~=b.buyout then return a.buyout<b.buyout end
        return a.quantity<b.quantity
    end)
    item._priceMap=nil
    item._levelCount=nil
    item.listingBuckets=list
    item.listingSchema=1
    local display={}
    for _,listing in ipairs(list) do
        local unit=displayUnitPrice(listing.buyout,listing.quantity)
        display[unit]=(display[unit] or 0)+listing.quantity*listing.count
    end
    item.priceBuckets={}
    for unit,quantity in pairs(display) do item.priceBuckets[#item.priceBuckets+1]={unit=unit,quantity=quantity} end
    table.sort(item.priceBuckets,function(a,b) return a.unit<b.unit end)
end

function AuctionScanner:GetSnapshot()
    local db = JLP:GetModule("DB")
    return db and db:GetAuctionSnapshot() or nil
end

-- Saved auction metadata may be historic or malformed. It must not throw in
-- read-only UI/eligibility checks or be silently displayed as a confirmed scan.
local function nonnegativeInteger(value)
    local number=tonumber(value)
    if not number or number~=number or number==math.huge or number==-math.huge or
        number<0 or number~=math.floor(number) then return nil end
    return number
end

local function qualifiedScanTime(snapshot,current)
    if type(snapshot)~="table" then return nil end
    local stamp=nonnegativeInteger(snapshot.completedAt)
    if not stamp or stamp<=0 or stamp>current then return nil end
    return stamp
end

-- An AH replicate snapshot only gates the same observed realm/faction/build.
-- A previous character's saved scan in a different qualified scope is not
-- evidence of a cooldown in the currently opened Auction House. Unknown
-- identities are deliberately conservative: do not waive that old gate on
-- the basis of missing/ambiguous client context.
local function scopeIdentity(value)
    if type(value)~="string" or value=="" then return nil end
    local key=value:lower():gsub("[%s%-']","")
    if key=="" or key=="unknown" or key=="unknownrealm" or
       key=="unknownfaction" then return nil end
    return key
end
local function observedIdentity(fn,...)
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...)
    return ok and scopeIdentity(value) or nil
end
function AuctionScanner:GetCooldownRemaining()
    local snapshot=self:GetSnapshot()
    local current=now()
    if type(snapshot)=="table" then
        local currentRealm=observedIdentity(GetRealmName)
        local storedRealm=scopeIdentity(snapshot.realm)
        local currentFaction=observedIdentity(UnitFactionGroup,"player")
        local storedFaction=scopeIdentity(snapshot.faction)
        if (currentRealm and storedRealm and currentRealm~=storedRealm) or
           (currentFaction and storedFaction and currentFaction~=storedFaction) then
            return 0
        end
        local build=JLP:GetModule("ClientBuildInfo")
        if build and type(build.GetBuildNumber)=="function" then
            local ok,observed=pcall(build.GetBuildNumber,build)
            if ok and type(observed)=="number" and
               type(snapshot.clientBuild)=="number" and
               snapshot.clientBuild~=observed then return 0 end
        end
    end
    local stamp=qualifiedScanTime(snapshot,current)
    -- Preserve the legacy nil-timestamp fallback: a corrupt historic receipt
    -- cannot authorize an automatic scan; only the explicit guarded action can.
    if not stamp then return 0 end
    local limit=nonnegativeInteger(JLP.Constants and JLP.Constants.FULL_SCAN_COOLDOWN) or 0
    return math.max(0,limit-(current-stamp))
end

function AuctionScanner:CanStartScan()
    if self.scanInProgress then return false, "A scan is already in progress." end
    if not self.isAuctionHouseOpen then return false, "Open the Auction House before scanning." end
    if not C_AuctionHouse or type(C_AuctionHouse.ReplicateItems) ~= "function" then
        return false, "The Forever Auction House replicate API is unavailable."
    end
    local cooldown = self:GetCooldownRemaining()
    if cooldown > 0 then return false, string.format("Full scan cooldown: %d:%02d remaining.", math.floor(cooldown / 60), cooldown % 60) end
    return true
end

local function emit(event,payload)
    if JLP.EventBus and type(JLP.EventBus.Emit)=="function" then
        JLP.EventBus:Emit(event,payload)
    end
end

function AuctionScanner:CancelScan(reason)
    if not self.scanInProgress then return false end
    self.scanInProgress=false
    self.requestedAt=nil
    self.progressAt=nil
    self.scanCursor=0
    self.scanCount=0
    self.processedRows=0
    self.waitElapsed=0
    self.staging=nil
    self.finalizeKey=nil
    self.finalizedItems=nil
    self.lastScanIssue=reason or "SCAN_CANCELLED"
    if self.scanFrame and self.scanFrame.SetScript then
        self.scanFrame:SetScript("OnUpdate",nil)
    end
    emit("AH_SCAN_EXPIRED",self.lastScanIssue)
    return true
end

function AuctionScanner:BeginManualScan()
    local can,reason=self:CanStartScan()
    if not can then return false,reason end
    self.scanInProgress=true
    self.requestedAt=now()
    if self.requestedAt<=0 then
        self:CancelScan("CLOCK_UNAVAILABLE")
        return false,"Reliable scan clock unavailable; previous snapshot retained."
    end
    self.progressAt=self.requestedAt
    self.scanCursor=0
    self.scanCount=0
    self.processedRows=0
    self.waitElapsed=0
    self.staging=nil
    self.lastScanIssue=nil
    if not self.scanFrame then
        local ready,frame=pcall(CreateFrame,"Frame")
        if ready and frame and type(frame.SetScript)=="function" then
            self.scanFrame=frame
        end
    end
    if not self.scanFrame then
        self:CancelScan("FRAME_SCHEDULER_UNAVAILABLE")
        return false,"Scan watchdog unavailable; previous snapshot retained."
    end
    local installed=pcall(self.scanFrame.SetScript,self.scanFrame,"OnUpdate",function(_,elapsed)
        self.waitElapsed=(self.waitElapsed or 0)+(tonumber(elapsed) or 0)
        if self.waitElapsed>=1 then
            self.waitElapsed=0
            local guard=JLP:GetModule("AuctionScanGuard")
            if guard and guard.ExpirePendingScan then guard:ExpirePendingScan() end
        end
    end)
    if not installed then
        self:CancelScan("FRAME_SCHEDULER_UNAVAILABLE")
        return false,"Scan watchdog failed; previous snapshot retained."
    end
    self.waitElapsed=0
    if type(self.scanFrame.Show)=="function" then pcall(self.scanFrame.Show,self.scanFrame) end
    local ok,err=pcall(C_AuctionHouse.ReplicateItems)
    if not ok or err==false then
        self:CancelScan("REPLICATE_CALL_FAILED")
        return false,tostring(err or "ReplicateItems failed")
    end
    emit("AH_SCAN_STARTED")
    return true,"Auction House scan requested. Waiting for replicate data."
end

local function finiteNonnegativeInteger(value)
    return type(value)=="number" and value==value and value~=math.huge and
        value~=-math.huge and value>=0 and value<=MAX_SAFE_INTEGER and
        value==math.floor(value) and value or nil
end

function AuctionScanner:ProcessReplicateList()
    if not self.scanInProgress then return false,"No manual scan is pending." end
    if self.staging then
        return true,{pending=true,auctionCount=self.scanCount,processed=self.scanCursor}
    end
    if not self.isAuctionHouseOpen then
        self:CancelScan("AUCTION_HOUSE_CLOSED")
        return false,"Auction House closed; previous snapshot retained."
    end
    if type(C_AuctionHouse)~="table" or
       type(C_AuctionHouse.GetNumReplicateItems)~="function" or
       type(C_AuctionHouse.GetReplicateItemInfo)~="function" then
        self:CancelScan("REPLICATE_API_UNAVAILABLE")
        return false,"Replicate result API unavailable."
    end
    local okCount,count=pcall(C_AuctionHouse.GetNumReplicateItems)
    if not okCount or not positiveInteger(count) or count>500000 then
        self:CancelScan("INVALID_REPLICATE_COUNT")
        return false,"Invalid or excessive replicate count; previous snapshot retained."
    end
    local staging={
        schema=JLP.Constants.SNAPSHOT_SCHEMA,listingSchema=1,
        startedAt=self.requestedAt or now(),
        realm=realmName(),faction=factionName(),auctionCount=count,
        itemCount=0,incompleteInfoCount=0,truncatedPriceItemCount=0,
        items={},complete=false,
    }
    local buildInfo=JLP:GetModule("ClientBuildInfo")
    if type(buildInfo)=="table" and type(buildInfo.GetBuildNumber)=="function" then
        local ok,build=pcall(buildInfo.GetBuildNumber,buildInfo)
        if ok and positiveInteger(build) then staging.clientBuild=build end
    end
    if type(buildInfo)=="table" and type(buildInfo.Read)=="function" then
        local ok,receipt=pcall(buildInfo.Read,buildInfo)
        if ok and type(receipt)=="table" and receipt.known==true and
           receipt.buildNumber==staging.clientBuild and
           (receipt.interfaceVersion==nil or positiveInteger(receipt.interfaceVersion)) then
            local expected=string.format("forever:%s|interface:%s",
                tostring(receipt.buildNumber),tostring(receipt.interfaceVersion or "unknown"))
            if receipt.token==expected then staging.clientBuildToken=expected end
        end
    end
    self.staging=staging
    self.scanCount=count
    self.scanCursor=0
    self.progressAt=now()
    -- This frame processes a bounded slice. A missing frame is a fail-closed
    -- capability failure, never a synchronous fallback for large datasets.
    if not self.scanFrame then
        local ok,frame=pcall(CreateFrame,"Frame")
        if ok and frame and type(frame.SetScript)=="function" then
            self.scanFrame=frame
        end
    end
    if not self.scanFrame then
        self:CancelScan("FRAME_SCHEDULER_UNAVAILABLE")
        return false,"Incremental scan frame unavailable; previous snapshot retained."
    end
    local installed=pcall(self.scanFrame.SetScript,self.scanFrame,"OnUpdate",function()
        local ok,err=pcall(self.PumpScan,self)
        if not ok then
            self:CancelScan("REPLICATE_PROCESSING_ERROR")
            if JLP.RecordRuntimeError then JLP:RecordRuntimeError("AH_SCAN_PUMP",err) end
        end
    end)
    if not installed then
        self:CancelScan("FRAME_SCHEDULER_UNAVAILABLE")
        return false,"Incremental scan scheduling failed; previous snapshot retained."
    end
    return true,{pending=true,auctionCount=count,processed=0}
end

local function processAuctionRow(staging,index)
    local ok,name,texture,stackCount,qualityID,usable,level,levelType,
        minBid,minIncrement,buyoutPrice,bidAmount,highBidder,bidderFullName,
        owner,ownerFullName,saleStatus,itemID,hasAllInfo =
        pcall(C_AuctionHouse.GetReplicateItemInfo,index)
    if not ok or not positiveInteger(itemID) or not positiveInteger(stackCount) then
        staging.incompleteInfoCount=staging.incompleteInfoCount+1
        return true
    end
    local row=staging.items[itemID]
    if not row then
        if staging.itemCount>=60000 then return false,"TOO_MANY_ITEM_TYPES" end
        row={itemID=itemID,name=(type(name)=="string" and name~="" and name or nil),
            texture=nil,
            qualityID=finiteNonnegativeInteger(qualityID),level=finiteNonnegativeInteger(level),
            totalQuantity=0,auctionCount=0,minUnitBuyout=nil,_priceMap={},_levelCount=0}
        -- Do not hold texture/name objects of invalid types in SavedVariables.
        if type(texture)=="string" or type(texture)=="number" then row.texture=texture end
        staging.items[itemID]=row
        staging.itemCount=staging.itemCount+1
    end
    if row.totalQuantity>MAX_SAFE_INTEGER-stackCount then return false,"QUANTITY_OVERFLOW" end
    row.totalQuantity=row.totalQuantity+stackCount
    row.auctionCount=row.auctionCount+1
    if not row.name and type(name)=="string" and name~="" then row.name=name end
    if row.qualityID==nil then row.qualityID=finiteNonnegativeInteger(qualityID) end
    if row.level==nil then row.level=finiteNonnegativeInteger(level) end
    if hasAllInfo~=true then
        staging.incompleteInfoCount=staging.incompleteInfoCount+1
        return true
    end
    local buyout=finiteNonnegativeInteger(buyoutPrice)
    if buyoutPrice~=nil and not buyout then
        staging.incompleteInfoCount=staging.incompleteInfoCount+1
        return true
    end
    if buyout and buyout>0 then
        local unit=displayUnitPrice(buyout,stackCount)
        if unit>0 then
            row.minUnitBuyout=row.minUnitBuyout and math.min(row.minUnitBuyout,unit) or unit
            recordPrice(row,buyout,stackCount)
        end
    end
    return true
end

function AuctionScanner:PumpScan()
    if not self.scanInProgress or not self.staging then return false,"No pending scan data." end
    local current=now()
    if not self.isAuctionHouseOpen then
        self:CancelScan("AUCTION_HOUSE_CLOSED")
        return false,"Auction House closed; previous snapshot retained."
    end
    if self.requestedAt and (current<self.requestedAt or current-self.requestedAt>180) then
        self:CancelScan("SCAN_PROCESSING_TIMEOUT")
        return false,"Scan processing exceeded time limit; previous snapshot retained."
    end
    local started=type(debugprofilestop)=="function" and debugprofilestop() or nil
    local deadline=started and (started+2) or nil
    local limit=math.min(self.scanCursor+200,self.scanCount)
    local staging=self.staging
    while self.scanCursor<limit do
        local ok,reason=processAuctionRow(staging,self.scanCursor)
        if not ok then
            self:CancelScan(reason)
            return false,reason
        end
        self.scanCursor=self.scanCursor+1
        if deadline and self.scanCursor%16==0 and debugprofilestop()>=deadline then break end
    end
    self.processedRows=self.scanCursor
    self.progressAt=current
    if self.scanCursor<self.scanCount then return true,{pending=true,processed=self.scanCursor,auctionCount=self.scanCount} end
    if staging.itemCount<=0 then
        self:CancelScan("NO_VALID_AUCTIONS")
        return false,"No valid auction rows; previous snapshot retained."
    end
    -- Iterate the existing map using next(); never allocate a second array of
    -- up to 60,000 item identities in one frame.
    staging.complete=(staging.incompleteInfoCount==0)
    self.finalizeKey=nil
    self.finalizedItems=0
    if self.scanFrame then self.scanFrame:SetScript("OnUpdate",function()
        local ok,err=pcall(self.FinalizeScan,self)
        if not ok then
            self:CancelScan("SCAN_FINALIZE_ERROR")
            if JLP.RecordRuntimeError then JLP:RecordRuntimeError("AH_SCAN_FINALIZE",err) end
        end
    end) end
    return true,{pending=true,finalizing=true,auctionCount=self.scanCount}
end

function AuctionScanner:FinalizeScan()
    local staging=self.staging
    if not staging or self.finalizedItems==nil then return false,"Nothing to finalize." end
    if not self.isAuctionHouseOpen then self:CancelScan("AUCTION_HOUSE_CLOSED"); return false end
    if self.requestedAt and (now()<self.requestedAt or now()-self.requestedAt>180) then
        self:CancelScan("SCAN_PROCESSING_TIMEOUT")
        return false,"Finalization exceeded time limit; previous snapshot retained."
    end
    -- A scan spanning a client/interface identity change must never become a
    -- current-price receipt, even if the original build returns later.
    if staging.clientBuildToken then
        local info=JLP:GetModule("ClientBuildInfo")
        local ok,receipt=false,nil
        if type(info)=="table" and type(info.Read)=="function" then
            ok,receipt=pcall(info.Read,info)
        end
        if not ok or type(receipt)~="table" or receipt.known~=true or
           receipt.buildNumber~=staging.clientBuild or
           receipt.token~=staging.clientBuildToken then
            self:CancelScan("CLIENT_SESSION_CHANGED")
            return false,"Client identity changed during scan; previous snapshot retained."
        end
    end
    local n=0
    local started=type(debugprofilestop)=="function" and debugprofilestop() or nil
    local deadline=started and started+2 or nil
    while n<200 do
        local nextKey,row=next(staging.items,self.finalizeKey)
        if nextKey==nil then break end
        self.finalizeKey=nextKey
        buildPriceBuckets(row)
        if row.priceCoverageTruncated then
            staging.truncatedPriceItemCount=staging.truncatedPriceItemCount+1
        end
        self.finalizedItems=self.finalizedItems+1
        n=n+1
        if deadline and n%16==0 and debugprofilestop()>=deadline then break end
    end
    if self.finalizedItems<staging.itemCount then return true,{pending=true,finalizing=true} end
    -- Only bounded groups are retained. Each selection still buys actual
    -- listings; discarded groups mean a globally cheapest choice is unknown.
    if not staging.complete then
        self:CancelScan("PARTIAL_REPLICATE_DATA")
        return false,"Incomplete auction data; previous snapshot retained."
    end
    staging.completedAt=now()
    staging.scanID=string.format("%s-%d-%d-%d",staging.realm,staging.startedAt,
        staging.completedAt,staging.auctionCount)
    local db=JLP:GetModule("DB")
    if not db or not db.SetAuctionSnapshot then
        self:CancelScan("SNAPSHOT_DB_UNAVAILABLE")
        return false,"Snapshot storage unavailable; previous snapshot retained."
    end
    local previousSnapshot=self:GetSnapshot()
    local ok,saved=pcall(db.SetAuctionSnapshot,db,staging)
    if not ok or saved~=true then
        self:CancelScan("SNAPSHOT_PERSIST_FAILED")
        return false,"Unable to persist snapshot; previous snapshot retained."
    end
    -- The scan becomes visible only after the atomic SavedVariables commit.
    local completed=staging
    self.scanInProgress=false
    self.staging=nil
    self.finalizeKey=nil
    self.finalizedItems=nil
    self.requestedAt=nil
    self.progressAt=nil
    self.lastScanIssue=nil
    if self.scanFrame then self.scanFrame:SetScript("OnUpdate",nil) end
    -- KnowledgeCache must never block snapshot completion or mutate the
    -- authoritative AH quote; lazily resolved names remain informational.
    if JLP.MarkObservationsDirty then
        local items={}
        for id in pairs(previousSnapshot and previousSnapshot.items or {}) do items[tonumber(id) or id]=true end
        for id in pairs(completed.items or {}) do items[tonumber(id) or id]=true end
        JLP:MarkObservationsDirty("AH_SNAPSHOT_UPDATED",nil,items)
    end
    emit("AH_SNAPSHOT_UPDATED",completed)
    return true,completed
end

function AuctionScanner:GetStatusText()
    if self.scanInProgress then return "Scan in progress..." end
    local snapshot=self:GetSnapshot()
    if type(snapshot)~="table" then return "No successful Auction House scan saved yet." end
    local current=now()
    local stamp=qualifiedScanTime(snapshot,current)
    local auctions=nonnegativeInteger(snapshot.auctionCount)
    local items=nonnegativeInteger(snapshot.itemCount)
    if not stamp or not auctions or not items then
        return "Saved Auction House snapshot metadata unavailable; check manually."
    end
    local age=current-stamp
    local ageText
    if age<60 then ageText="less than a minute"
    elseif age<3600 then ageText=string.format("%d min",math.floor(age/60))
    elseif age<86400 then ageText=string.format("%d h",math.floor(age/3600))
    else ageText=string.format("%d d",math.floor(age/86400)) end
    return string.format("Last successful scan: %s ago - %d auctions - %d item types",ageText,auctions,items)
end

JLP:RegisterModule("AuctionScanner", AuctionScanner)
