local _, JLP = ...
-- Alpha180 non-native presentation/capability guard for the existing protected
-- AuctionScanner. Never changes the scanner's implementation or saved schema.
local Guard={contract="jlp-auction-scan-guard-v1",nativeDispatchAllowed=false,
    timeoutSeconds=45,lastScanIssue=nil}
local function clock()
    if type(time)=="function" then local ok,v=pcall(time);if ok then return tonumber(v) end end
end
local function scanner() return JLP:GetModule("AuctionScanner") end
function Guard:ExpirePendingScan()
    local service=scanner()
    if not service or not service.scanInProgress then return false end
    local started=tonumber(service.requestedAt)
    local current=clock()
    if not current or not started or started<=0 then return false end
    if current<started then
        self.lastScanIssue="SCAN_CLOCK_INVALID"
        service:CancelScan(self.lastScanIssue)
        return true
    end
    if current-started<self.timeoutSeconds then return false end
    if service.staging then
        -- Processing has a distinct absolute timeout. A completed network
        -- response must not be discarded under the shorter wait timeout.
        if current-started<=180 then return false end
        self.lastScanIssue="SCAN_PROCESSING_TIMEOUT"
    else
        self.lastScanIssue="SCAN_TIMEOUT"
    end
    service:CancelScan(self.lastScanIssue)
    return true
end
function Guard:GetDiagnostics()
    self:ExpirePendingScan()
    local service=scanner()
    local snapshot=service and service:GetSnapshot()
    local api=C_AuctionHouse
    local available=type(api)=="table" and type(api.ReplicateItems)=="function" and
      type(api.GetNumReplicateItems)=="function" and type(api.GetReplicateItemInfo)=="function"
    local issue=self.lastScanIssue or (service and service.lastScanIssue)
    local state=service and service.scanInProgress and "WAITING_FOR_REPLICATE" or
        issue or (snapshot and "SNAPSHOT_AVAILABLE" or "NO_SNAPSHOT")
    local partial=snapshot and (tonumber(snapshot.incompleteInfoCount) or 0)>0
    return {contract=self.contract,state=state,
        scanInProgress=service and service.scanInProgress==true or false,
        apiAvailable=available==true,
        auctionHouseOpen=service and service.isAuctionHouseOpen==true or false,
        snapshotAvailable=snapshot~=nil,
        -- Legacy snapshots may claim complete=true despite incomplete rows.
        snapshotComplete=snapshot~=nil and snapshot.complete==true and not partial or false,
        priceDepthLimited=snapshot~=nil and
            (tonumber(snapshot.truncatedPriceItemCount) or 0)>0 or false,
        processedRows=service and service.processedRows or 0,
        expectedRows=service and service.scanCount or 0,
        truncatedPriceItemCount=snapshot and snapshot.truncatedPriceItemCount or 0,
        incompleteInfoCount=snapshot and (snapshot.incompleteInfoCount or 0) or 0,
        snapshotCompletedAt=snapshot and snapshot.completedAt or nil,
        nativeScanVerified=false}
end
function Guard:CanStartScan()
    self:ExpirePendingScan()
    local service=scanner()
    if not service then return false,"SCANNER_UNAVAILABLE" end
    local diag=self:GetDiagnostics()
    if not diag.apiAvailable then return false,"The Forever Auction House replicate API is unavailable." end
    return service:CanStartScan()
end
function Guard:BeginManualScan()
    local can,reason=self:CanStartScan()
    if not can then return false,reason end
    local service=scanner()
    self.lastScanIssue=nil
    local ok,result=service:BeginManualScan()
    if not ok then self.lastScanIssue="REPLICATE_CALL_FAILED" end
    return ok,result
end
function Guard:GetStatusText()
    local diag=self:GetDiagnostics()
    local service=scanner()
    local text=service and service:GetStatusText() or "Auction House scanner unavailable."
    local issue=self.lastScanIssue or (service and service.lastScanIssue)
    if diag.state~="NO_SNAPSHOT" and issue then
        text=text.." | Latest attempt: "..issue
    end
    if diag.scanInProgress and diag.expectedRows>0 then
        text=text..string.format(" | Processing: %d/%d",diag.processedRows,diag.expectedRows)
    end
    if diag.snapshotAvailable and not diag.snapshotComplete then
        text=text.." (partial/unqualified prices)"
    elseif diag.priceDepthLimited then
        text=text.." (limited price depth on "..tostring(diag.truncatedPriceItemCount).." item types)"
    end
    return text
end
JLP:RegisterModule("AuctionScanGuard",Guard)
