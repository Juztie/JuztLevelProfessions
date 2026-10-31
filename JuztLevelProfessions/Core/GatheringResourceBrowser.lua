local _, JLP = ...
-- Alpha175. Shared, read-only list contract for embedded and standalone views.
-- Only stable resourceKey is ever used to mutate shared selections/routes.
local Browser={contract="jlp-gathering-resource-browser-v1",nativeDispatchAllowed=false}
local function display(record)
    local s=record.displayName or record.name or record.resourceKey or "Resource"
    if s==record.resourceKey then
        s=s:gsub("_"," "):lower():gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end)
    end
    return tostring(s)
end
function Browser:Build(layer,query,offset,visibleRows,pagingMode)
    layer=type(layer)=="table" and layer or {}
    local source=layer.resources or {}
    local selection=layer.resourceSelection or {}
    local q=tostring(query or "")
    local catalog=JLP:GetModule("GatheringResourceDisplayCatalog")
    local items={}
    local selectedTotal=0
    for _,row in ipairs(source) do
        local key=tostring(row.resourceKey or "")
        if key~="" then
            local selected=selection[key]==true
            if selected then selectedTotal=selectedTotal+1 end
            local resolved=catalog and catalog:Resolve(row)
            local name=resolved and resolved.name or display(row)
            if (resolved and catalog:Matches(resolved,q)) or
               (not resolved and (q=="" or key:lower():find(q:lower(),1,true) or name:lower():find(q:lower(),1,true))) then
                items[#items+1]={resourceKey=key,name=name,localizedItemName=resolved and resolved.clientItemName,
                    record=row,selected=selected,sourceQualified=(tonumber(row.referenceCount) or 0)>0}
            end
        end
    end
    local capacity=math.max(1,math.floor(tonumber(visibleRows) or 6))
    local requested=math.max(0,math.floor(tonumber(offset) or 0))
    local index
    if pagingMode=="PAGES" then
        -- Only standalone Resources uses full pages. Do not backfill the
        -- short final page with previously shown items; that made the pager
        -- repeat choices and misreport the current page number.
        local lastStart=math.max(0,(math.ceil(#items/capacity)-1)*capacity)
        index=math.min(math.floor(requested/capacity)*capacity,lastStart)
    else
        -- Preserve row-offset behaviour for the embedded Fishing picker,
        -- matching-item selectors and other existing browser consumers.
        index=math.min(requested,math.max(0,#items-capacity))
    end
    local rows={}
    for i=1,capacity do if items[index+i] then rows[#rows+1]=items[index+i] end end
    return {rows=rows,offset=index,matchingCount=#items,totalCount=#source,
        selectedCount=selectedTotal,first=#items>0 and index+1 or 0,last=math.min(#items,index+capacity),
        canPrevious=index>0,canNext=index+capacity<#items}
end
JLP:RegisterModule("GatheringResourceBrowser",Browser)
