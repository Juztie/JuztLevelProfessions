local _, JLP = ...
-- The client item cache provides locale text, but NEVER a stable identity.
-- Missing or stale cache cannot remove a resource from the browser.
local Catalog={contract="jlp-gathering-resource-display-catalog-v1",nativeDispatchAllowed=false}
local function pretty(key)
 local text=tostring(key or ""):gsub("_"," "):lower()
 return (text:gsub("(%a)([%w']*)",function(a,b)return a:upper()..b end))
end
local function nameForItem(id)
 if not id then return nil end
 if type(C_Item)=="table" and type(C_Item.GetItemInfo)=="function" then
  local ok,name=pcall(C_Item.GetItemInfo,id)
  if ok and type(name)=="string" and name~="" then return name end
 end
 if type(GetItemInfo)=="function" then
  local ok,name=pcall(GetItemInfo,id)
  if ok and type(name)=="string" and name~="" then return name end
 end
 return nil
end
function Catalog:Resolve(record)
 record=type(record)=="table" and record or {}
 local key=tostring(record.resourceKey or "")
 local profession=tostring(record.professionKey or "")
 local evidence=JLP.data and JLP.data.gatheringResourceLocaleEvidence
 local ids=evidence and evidence[profession]
 local id=ids and ids[key]
 -- Use client item identity only for searching/displaying outputs; a Copper
 -- Vein is still named a vein, not silently reclassified as a Copper Ore node.
 local clientName=nameForItem(id)
 local default=record.displayName or record.name or pretty(key)
 -- Source name and produced item are not the same thing. Keep the node type
 -- explicit for ore veins; for herbs the client item name is a useful label.
 local shown=default
 if clientName and clientName~="" then
  if profession=="MINING" then shown=clientName.." ("..pretty(key)..")"
  else shown=clientName end
 end
 local names={key,pretty(key),default,record.itemName,clientName}
 return {resourceKey=key,professionKey=profession,itemID=id,
     name=tostring(shown),nodeLabel=tostring(default),clientItemName=clientName,
     localized=clientName~=nil,searchTerms=names,
     provenance=clientName and "CLIENT_CACHED_ITEM_NAME" or "STABLE_RESOURCE_KEY_FALLBACK"}
end
function Catalog:Matches(display,query)
 query=tostring(query or ""):lower():gsub("^%s+",""):gsub("%s+$","")
 if query=="" then return true end
 for _,term in pairs(display.searchTerms or {}) do
  if type(term)=="string" and term:lower():find(query,1,true) then return true end
 end
 return false
end
JLP:RegisterModule("GatheringResourceDisplayCatalog",Catalog)
