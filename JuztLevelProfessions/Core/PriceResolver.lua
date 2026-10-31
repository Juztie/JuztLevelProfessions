local _, JLP = ...
local PriceResolver = {}

local function scopedIdentity(fn,...)
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...)
    return ok and type(value)=="string" and value~="" and value or nil
end
-- A receipt identifies the exact completed source scan, not only a qualified
-- realm/faction. Legacy snapshots without an ID remain advisory.
local function snapshotKey(snapshot)
    if type(snapshot)~="table" or type(snapshot.scanID)~="string" or snapshot.scanID=="" or
        type(snapshot.realm)~="string" or snapshot.realm=="" or
        type(snapshot.faction)~="string" or snapshot.faction=="" or
        type(snapshot.completedAt)~="number" or snapshot.completedAt<=0 or
        snapshot.completedAt~=snapshot.completedAt or snapshot.completedAt==math.huge then return nil end
    return snapshot.scanID.."|"..snapshot.realm.."|"..snapshot.faction.."|"..tostring(snapshot.completedAt)
end

function PriceResolver:QualifySnapshot(snapshot)
    local scanner=JLP:GetModule("AuctionScanner")
    if snapshot==nil and type(scanner)=="table" and type(scanner.GetSnapshot)=="function" then
        local ok,result=pcall(scanner.GetSnapshot,scanner)
        if ok then snapshot=result end
    end
    if type(snapshot)~="table" then
        return {status="NO_SNAPSHOT",usable=false,readOnly=true,displayableAdvisory=false,
            trustedForCostEstimate=false,scopeVerified=false,snapshotComplete=false,ageKnown=false}
    end
    local realm=scopedIdentity(GetRealmName)
    local faction=scopedIdentity(UnitFactionGroup,"player")
    local function normalized(v)
        if type(v)~="string" or v=="" then return nil end
        local clean=v:lower():gsub("[%s%-']","")
        return clean~="unknown" and clean~="unknownrealm" and clean~="unknownfaction" and clean or nil
    end
    local currentRealm,currentFaction=normalized(realm),normalized(faction)
    local snapshotRealm,snapshotFaction=normalized(snapshot.realm),normalized(snapshot.faction)
    local mismatch=(currentRealm and snapshotRealm and currentRealm~=snapshotRealm) or
        (currentFaction and snapshotFaction and currentFaction~=snapshotFaction) or false
    local scopeVerified=not mismatch and currentRealm~=nil and currentFaction~=nil and
        snapshotRealm~=nil and snapshotFaction~=nil
    local now=type(time)=="function" and tonumber(time()) or nil
    local stamp=tonumber(snapshot.completedAt)
    local age=now and stamp and stamp>0 and now>=stamp and (now-stamp) or nil
    local incomplete=snapshot.incompleteInfoCount
    local validIncomplete=type(incomplete)=="number" and incomplete>=0 and
        incomplete==math.floor(incomplete) and incomplete<math.huge
    local truncated=snapshot.truncatedPriceItemCount
    local validTruncated=type(truncated)=="number" and truncated>=0 and
        truncated==math.floor(truncated) and truncated<math.huge
    -- Truncated *price depth* is compatible with exact quotes for the cheapest
    -- captured buyout levels. Missing auction rows are not.
    local complete=snapshot.complete==true and validIncomplete and incomplete==0 and
        (truncated==nil or validTruncated)
    local buildInfo=JLP:GetModule("ClientBuildInfo")
    local observedBuild=nil
    if type(buildInfo)=="table" and type(buildInfo.GetBuildNumber)=="function" then
        local ok,value=pcall(buildInfo.GetBuildNumber,buildInfo)
        if ok and type(value)=="number" then observedBuild=value end
    end
    local matchingBuild=type(snapshot.clientBuild)=="number" and
        snapshot.clientBuild==observedBuild and observedBuild~=nil
    -- Legacy SavedVariables without an interface-qualified receipt remain
    -- displayable as advisory prices, never trusted current-client quotes.
    local sessionVerified=false
    if matchingBuild and type(buildInfo)=="table" and type(buildInfo.Read)=="function" then
        local ok,receipt=pcall(buildInfo.Read,buildInfo)
        if ok and type(receipt)=="table" and receipt.known==true and
           receipt.buildNumber==observedBuild then
            local iface=receipt.interfaceVersion
            local validIface=iface==nil or (type(iface)=="number" and iface>0 and
                iface==math.floor(iface) and iface<math.huge)
            local expected=validIface and string.format("forever:%s|interface:%s",
                tostring(observedBuild),tostring(iface or "unknown")) or nil
            sessionVerified=expected~=nil and receipt.token==expected and
                snapshot.clientBuildToken==expected
        end
    end
    local status=mismatch and "SCOPE_MISMATCH" or not scopeVerified and "SCOPE_UNVERIFIED" or
        not complete and "PARTIAL" or not matchingBuild and "BUILD_UNVERIFIED" or
        not sessionVerified and "SESSION_UNVERIFIED" or
        snapshot.listingSchema~=1 and "LEGACY_UNIT_PRICE_ONLY" or
        not age and "AGE_UNKNOWN" or age>86400 and "STALE" or "RECENT"
    local receipt=snapshotKey(snapshot)
    if status=="RECENT" and not receipt then status="SCAN_RECEIPT_MISSING" end
    local trusted=status=="RECENT"
    return {status=status,usable=trusted,readOnly=true,nativeDispatchAllowed=false,
        displayableAdvisory=not mismatch,trustedForCostEstimate=trusted,
        ageKnown=age~=nil,ageSeconds=age,ageBucket=age and (age>86400 and "STALE" or "RECENT") or "UNKNOWN",
        scopeVerified=scopeVerified,scopeMismatch=mismatch,snapshotComplete=complete,
        buildVerified=matchingBuild,sessionVerified=sessionVerified,
        clientBuild=observedBuild,snapshotBuild=type(snapshot.clientBuild)=="number" and snapshot.clientBuild or nil,
        realm=type(snapshot.realm)=="string" and snapshot.realm or nil,
        faction=type(snapshot.faction)=="string" and snapshot.faction or nil,currentRealm=realm,currentFaction=faction,
        partial=not complete,priceDepthLimited=validTruncated and truncated>0 or false,
        truncatedPriceItemCount=validTruncated and truncated or nil,
        listingSchema=snapshot.listingSchema==1 and 1 or nil,snapshotAt=stamp,snapshotKey=receipt}
end
function PriceResolver:GetItemSnapshot(itemID,allowAdvisory)
    local scanner=JLP:GetModule("AuctionScanner")
    local snapshot=nil
    if type(scanner)=="table" and type(scanner.GetSnapshot)=="function" then
        local ok,result=pcall(scanner.GetSnapshot,scanner)
        if ok then snapshot=result end
    end
    local q=self:QualifySnapshot(snapshot)
    if not q.trustedForCostEstimate and not (allowAdvisory and q.displayableAdvisory) then return nil,q end
    local id=tonumber(itemID)
    local stored=type(snapshot.items)=="table" and id and snapshot.items[id] or nil
    if type(stored)~="table" then return nil,q end
    -- A price query must never expose mutable SavedVariables rows. DB and the
    -- scanner retain the persisted snapshot; only the requested item's bucket
    -- list is copied (no whole-snapshot traversal on UI refresh).
    -- Only scalar scanner-owned fields cross the public read-only boundary.
    -- A corrupt/legacy SavedVariables row can contain arbitrary nested tables;
    -- shallow-copying them leaks mutable DB aliases to downstream UI callers.
    local row={}
    for _,field in ipairs({"totalQuantity","minUnitBuyout","minUnitPrice","auctionCount"}) do
        local value=stored[field]
        if value~=nil then
            if type(value)~="number" or value~=value or value==math.huge or
               value==-math.huge or value<0 then
                row.priceMalformed=true
            else
                row[field]=value
            end
        end
    end
    if stored.priceCoverageTruncated~=nil and type(stored.priceCoverageTruncated)~="boolean" then
        row.priceMalformed=true
    end
    row.priceCoverageTruncated=stored.priceCoverageTruncated==true
    row.priceBuckets={}
    if stored.priceBuckets~=nil and type(stored.priceBuckets)~="table" then
        row.priceMalformed=true
    elseif type(stored.priceBuckets)=="table" then
        -- The scanner publishes dense 1..B arrays (B <= MAX_PRICE_BUCKETS_PER_ITEM).
        -- Validate *all occupied keys* before indexing; ipairs silently ignores
        -- malformed tails after a nil gap, incorrectly allowing a trusted quote.
        -- The fixed upper bound prevents corrupt SavedVariables from causing
        -- arbitrarily large allocations or numeric-index loops on UI refresh.
        local buckets=stored.priceBuckets
        local declared=tonumber(JLP.Constants and JLP.Constants.MAX_PRICE_BUCKETS_PER_ITEM)
        local limit=declared and declared>=1 and declared<=64 and math.floor(declared) or 48
        local count=0
        for key,bucket in pairs(buckets) do
            count=count+1
            if count>limit or type(key)~="number" or key<1 or
               key>limit or key~=math.floor(key) or
               type(bucket)~="table" or type(bucket.unit)~="number" or
               bucket.unit~=bucket.unit or bucket.unit==math.huge or
               bucket.unit==-math.huge or bucket.unit<=0 or
               type(bucket.quantity)~="number" or bucket.quantity~=bucket.quantity or
               bucket.quantity==math.huge or bucket.quantity==-math.huge or
               bucket.quantity<=0 or bucket.quantity~=math.floor(bucket.quantity) then
                row.priceMalformed=true
                break
            end
        end
        if not row.priceMalformed then
            local priorUnit=nil
            local pricedDepth=0
            for index=1,count do
                local bucket=rawget(buckets,index)
                if type(bucket)~="table" then
                    row.priceMalformed=true
                    break
                end
                -- Replicate scanner emits ascending positive integral copper
                -- prices. Nonmonotonic or fractional rows from SavedVariables
                -- cannot be treated as lowest-first fulfillment evidence.
                if bucket.unit~=math.floor(bucket.unit) or bucket.unit>9007199254740991 or
                   (priorUnit~=nil and bucket.unit<=priorUnit) then
                    row.priceMalformed=true
                    break
                end
                priorUnit=bucket.unit
                if pricedDepth>9007199254740991-bucket.quantity then
                    row.priceMalformed=true
                    break
                end
                pricedDepth=pricedDepth+bucket.quantity
                row.priceBuckets[index]={unit=bucket.unit,quantity=bucket.quantity}
            end
            -- Scanner counts all listings, including those with no buyout.
            -- Priced buyout depth may be smaller, never larger, than inventory.
            if #row.priceBuckets>0 and row.minUnitBuyout==nil then
                row.minUnitBuyout=row.priceBuckets[1].unit
            end
            if type(row.totalQuantity)~="number" or
               row.totalQuantity~=math.floor(row.totalQuantity) or
               row.totalQuantity<pricedDepth or
               (#row.priceBuckets>0 and row.minUnitBuyout~=nil and
                   row.minUnitBuyout~=row.priceBuckets[1].unit) then
                row.priceMalformed=true
            end
        end
        if row.priceMalformed then row.priceBuckets={} end
    end
    row.listingSchema=stored.listingSchema==1 and 1 or nil
    row.listingBuckets={}
    if q.listingSchema==1 then
        local buckets=stored.listingBuckets
        local limit=tonumber(JLP.Constants and JLP.Constants.MAX_PRICE_BUCKETS_PER_ITEM) or 48
        limit=math.min(64,math.max(1,math.floor(limit)))
        local count,depth=0,0
        if stored.listingSchema~=1 or type(buckets)~="table" then row.priceMalformed=true
        else
            for key,listing in pairs(buckets) do
                count=count+1
                if count>limit or type(key)~="number" or key<1 or key>limit or key~=math.floor(key) or
                    type(listing)~="table" then row.priceMalformed=true;break end
                for _,field in ipairs({"quantity","buyout","count"}) do
                    local value=listing[field]
                    if type(value)~="number" or value~=value or value<1 or
                        value>9007199254740991 or value~=math.floor(value) then row.priceMalformed=true;break end
                end
                if row.priceMalformed then break end
            end
            if not row.priceMalformed then
                local seen={}
                for index=1,count do
                    local listing=rawget(buckets,index)
                    if type(listing)~="table" or listing.quantity>math.floor((9007199254740991-depth)/listing.count) then
                        row.priceMalformed=true;break
                    end
                    local key=string.format("%.17g:%.17g",listing.quantity,listing.buyout)
                    if seen[key] then row.priceMalformed=true;break end
                    seen[key]=true
                    depth=depth+listing.quantity*listing.count
                    row.listingBuckets[index]={quantity=listing.quantity,buyout=listing.buyout,count=listing.count}
                end
                if type(row.totalQuantity)~="number" or depth>row.totalQuantity then row.priceMalformed=true end
            end
        end
        if row.priceMalformed then row.listingBuckets={} end
    end
    return row,q
end
-- A216-002: content receipt for ONE requested item (at most B scanner buckets).
-- No saved schema or scanner commit changes. This is deliberately a bounded
-- representation, NOT an authorization token or cryptographic guarantee.
-- A plan must recheck every quoted item before showing a trusted estimate.
local function itemPriceReceipt(itemID,row,snapshotKeyValue)
    if type(row)~="table" or row.priceMalformed or
       type(snapshotKeyValue)~="string" or snapshotKeyValue=="" or
       type(row.priceBuckets)~="table" then return nil end
    local fields={snapshotKeyValue,tostring(itemID),
        type(row.totalQuantity)=="number" and string.format("%.17g",row.totalQuantity) or "",
        type(row.minUnitBuyout)=="number" and string.format("%.17g",row.minUnitBuyout) or "",
        row.priceCoverageTruncated and "LIMITED_DEPTH" or "FULL_DEPTH",tostring(row.listingSchema or "LEGACY")}
    for index,bucket in ipairs(row.priceBuckets) do
        -- The item copy's dense shape was already validated in GetItemSnapshot.
        fields[#fields+1]=string.format("%d:%.17g:%.17g",index,bucket.unit,bucket.quantity)
    end
    for index,listing in ipairs(row.listingBuckets or {}) do
        fields[#fields+1]=string.format("L%d:%.17g:%.17g:%.17g",index,listing.quantity,listing.buyout,listing.count)
    end
    return table.concat(fields,"|")
end

function PriceResolver:ItemPriceReceiptMatches(itemID,expected)
    if type(expected)~="string" or expected=="" then return false end
    local row,qualification=self:GetItemSnapshot(itemID)
    if type(qualification)~="table" or qualification.trustedForCostEstimate~=true then return false end
    return itemPriceReceipt(itemID,row,qualification.snapshotKey)==expected
end

-- Exact bounded covering knapsack for small requests. Larger requests use a
-- disclosed feasible selection; neither a heuristic nor retained depth is
-- described as a globally cheapest purchase. Every cost buys whole listings.
local function selectListings(listings,requested)
    local bundles={}
    for index,listing in ipairs(listings) do
        local remaining=math.min(listing.count,math.ceil(requested/listing.quantity))
        local size=1
        while remaining>0 do
            local take=math.min(size,remaining)
            bundles[#bundles+1]={index=index,count=take,quantity=take*listing.quantity,cost=take*listing.buyout}
            remaining=remaining-take;size=size*2
        end
    end
    local exact=requested<=4096 and #bundles*requested<=200000
    local selected={}
    if exact then
        local states={[0]={cost=0,quantity=0}}
        for _,bundle in ipairs(bundles) do
            for quantity=requested-1,0,-1 do
                local previous=states[quantity]
                if previous and bundle.cost<=9007199254740991-previous.cost and
                    bundle.quantity<=9007199254740991-previous.quantity then
                    local target=math.min(requested,quantity+bundle.quantity)
                    local cost,purchased=previous.cost+bundle.cost,previous.quantity+bundle.quantity
                    local old=states[target]
                    if not old or cost<old.cost or (cost==old.cost and purchased<old.quantity) then
                        states[target]={cost=cost,quantity=purchased,node={prior=previous.node,index=bundle.index,count=bundle.count}}
                    end
                end
            end
        end
        local best=states[requested]
        if not best then return nil,nil,nil,true end
        local node=best.node
        while node do selected[node.index]=(selected[node.index] or 0)+node.count;node=node.prior end
        return best.cost,best.quantity,selected,true
    end
    local order={}
    for index,listing in ipairs(listings) do order[#order+1]={index=index,listing=listing} end
    table.sort(order,function(a,b)
        local x,y=a.listing,b.listing
        if x.buyout/x.quantity~=y.buyout/y.quantity then return x.buyout/x.quantity<y.buyout/y.quantity end
        return x.buyout<y.buyout
    end)
    local cost,purchased=0,0
    for _,entry in ipairs(order) do
        if purchased>=requested then break end
        local listing=entry.listing
        local count=math.min(listing.count,math.ceil((requested-purchased)/listing.quantity))
        if listing.buyout>math.floor((9007199254740991-cost)/count) or
            listing.quantity>math.floor((9007199254740991-purchased)/count) then return nil,nil,nil,false end
        cost=cost+count*listing.buyout;purchased=purchased+count*listing.quantity
        selected[entry.index]=count
    end
    if purchased<requested then return nil,nil,nil,false end
    -- A cheaper large stack can beat the unit-first selection for small tails.
    for index,listing in ipairs(listings) do
        local count=math.ceil(requested/listing.quantity)
        if count<=listing.count and listing.buyout<=math.floor(9007199254740991/count) then
            local alternative=count*listing.buyout
            if alternative<cost then cost=alternative;purchased=count*listing.quantity;selected={[index]=count} end
        end
    end
    return cost,purchased,selected,false
end

function PriceResolver:GetFulfillmentCost(itemID,quantity)
    -- No invalid identity may become a zero-price quote.
    local id=tonumber(itemID)
    if not id or id~=math.floor(id) or id<1 or id==math.huge or id~=id then
        return {complete=false,status="INVALID_ITEM_ID",cost=nil,
            trustedForCostEstimate=false,readOnly=true,nativeDispatchAllowed=false}
    end
    -- Missing, NaN and infinite requests must never become a zero-cost quote.
    local requested=tonumber(quantity)
    if not requested or requested~=requested or requested==math.huge or
       requested==-math.huge or requested<0 or requested~=math.floor(requested) or
       requested>1000000000 then
        return {complete=false,status="INVALID_QUANTITY",cost=nil,
            trustedForCostEstimate=false,readOnly=true,nativeDispatchAllowed=false}
    end
    quantity=requested
    if quantity==0 then return {complete=true,requested=0,fulfilled=0,cost=0,
        readOnly=true,nativeDispatchAllowed=false} end
    local row,q=self:GetItemSnapshot(itemID)
    if type(row)~="table" or row.priceMalformed then
        return {complete=false,requested=quantity,fulfilled=0,missing=quantity,cost=nil,
            status=row and row.priceMalformed and "MALFORMED_PRICE_BUCKET" or
                (q and q.status or "NO_SNAPSHOT"),readOnly=true,
            trustedForCostEstimate=false,nativeDispatchAllowed=false}
    end
    local cost,purchased,counts,exact=selectListings(row.listingBuckets,quantity)
    local complete=cost~=nil
    local selection={}
    for index,count in pairs(counts or {}) do
        local listing=row.listingBuckets[index]
        selection[#selection+1]={quantity=listing.quantity,buyout=listing.buyout,count=count}
    end
    table.sort(selection,function(a,b) if a.buyout~=b.buyout then return a.buyout<b.buyout end;return a.quantity<b.quantity end)
    return {complete=complete,requested=quantity,fulfilled=complete and quantity or 0,
        missing=complete and 0 or quantity,cost=cost,minUnitBuyout=row.minUnitBuyout,
        purchasedQuantity=purchased or 0,excessQuantity=complete and purchased-quantity or 0,
        selection=selection,costOptimal=complete and exact and not row.priceCoverageTruncated or false,
        optimizationStatus=exact and (row.priceCoverageTruncated and "OPTIMAL_RETAINED_DEPTH" or "EXACT") or "BOUNDED_HEURISTIC",
        available=row.totalQuantity,priceCoverageTruncated=row.priceCoverageTruncated,
        readOnly=true,trustedForCostEstimate=complete,
        status=complete and q.status or "INSUFFICIENT_BUYOUT_DEPTH",snapshotKey=q.snapshotKey,
        itemPriceReceipt=itemPriceReceipt(itemID,row,q.snapshotKey),nativeDispatchAllowed=false}
end

JLP:RegisterModule("PriceResolver", PriceResolver)
