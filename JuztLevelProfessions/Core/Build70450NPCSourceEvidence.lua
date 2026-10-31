local _, JLP = ...
-- M21: provenance-preserving and fully read-only source crosscheck and client UI observation.
-- Does NOT alter recipe rights, record an NPC spawn, buy anything, or certify server loot tables.
local BUILD=70450
local Service={contract="JLP-BUILD70450-NPC-SOURCE-EVIDENCE-1",sourceBuild=BUILD,
 readOnly=true,executionEligible=false,nativeDispatchAllowed=false,productionAuthority=false}
local function pos(n) return type(n)=="number" and n>0 and n<2147483647 and n==math.floor(n) end
local function liveBuild()
 local m=JLP:GetModule("ClientBuildInfo")
 if not m or type(m.GetBuildNumber)~="function" then return nil end
 local ok,n=pcall(m.GetBuildNumber,m)
 -- NPC/item IDs and client builds are different numeric domains.
 return ok and type(n)=="number" and n==n and n>0 and
     n==math.floor(n) and n<=9007199254740991 and n or nil
end
local function itemIDFromLink(link)
 if type(link)~="string" or #link>1024 then return nil end
 local _,links=link:gsub("|H","|H")
 if links~=1 then return nil end
 local value=link:match("|Hitem:(%d+)[|:]")
 local id=tonumber(value)
 return pos(id) and id or nil
end
local function npcIDFromGUID(guid)
 if type(guid)~="string" then return nil end
 -- Creature-0-<realm>-<instance>-<zone>-<creatureEntry>-<spawnUid>
 local id=guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$") or
          guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
 id=tonumber(id)
 return pos(id) and id or nil
end
local function npcIdentity()
 if type(UnitGUID)~="function" then return nil,"NPC_GUID_API_UNAVAILABLE" end
 -- Never substitute the player's target (possibly a different unit).
 local ok,guid=pcall(UnitGUID,"npc")
 local id=ok and npcIDFromGUID(guid) or nil
 if not id then return nil,"INTERACTING_NPC_GUID_UNAVAILABLE" end
 local name
 if type(UnitName)=="function" then
  local valid,v=pcall(UnitName,"npc")
  if valid and type(v)=="string" and #v<200 then name=v end
 end
 return {npcID=id,npcName=name,rawGUID=guid},nil
end
local function currentPosition()
 -- This is the player's position while interacting, never an NPC spawn coordinate.
 if type(C_Map)~="table" or type(C_Map.GetBestMapForUnit)~="function" or
    type(C_Map.GetPlayerMapPosition)~="function" then return nil end
 local ok,id=pcall(C_Map.GetBestMapForUnit,"player")
 if not ok or not pos(id) then return nil end
 local valid,xy=pcall(C_Map.GetPlayerMapPosition,id,"player")
 if not valid or type(xy)~="table" or
    type(xy.x)~="number" or type(xy.y)~="number" or
    xy.x<0 or xy.x>1 or xy.y<0 or xy.y>1 then return nil end
 return {uiMapID=id,x=xy.x*100,y=xy.y*100,authority="PLAYER_POSITION_NEAR_INTERACTION_NOT_NPC_SPAWN"}
end
local function citationRows()
 local d=JLP.data and JLP.data.build70450NPCSourceCrosschecks
 if type(d)~="table" or d.contract~="JLP-70450-NPC-PUBLIC-CROSSCHECKS-1" or
    d.sourceBuild~=BUILD or d.productionAuthority~=false or type(d.rows)~="table" or
    type(d.citations)~="table" then return nil,"PUBLIC_REFERENCE_DATA_INVALID" end
 return d
end
function Service:GetPublicCrosschecks(itemID,kind,npcID,sourceBuild)
 if sourceBuild~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
 if not pos(itemID) then return nil,"INVALID_ITEM_ID" end
 local d,why=citationRows();if not d then return nil,why end
 local rows={}
 for _,r in ipairs(d.rows[itemID] or {}) do
  if (not kind or kind==r.kind) and (not npcID or npcID==r.npcID) then
   local url=d.citations[r.source]
   if type(url)~="string" or url:sub(1,8)~="https://" or not pos(r.npcID) or
      type(r.name)~="string" or r.name=="" then return nil,"PUBLIC_REFERENCE_INVALID" end
   -- Explicit, independently sourced vendor-side evidence. A faction guide
   -- never licenses NPC/item records for the opposite faction.
   local qualifiedSource=r.source=="acaForeverGuide" or r.source=="acaForeverGuide02R4" or
       r.source=="foreverCookingGuide" or r.source=="foreverHordeLWItem"
   if qualifiedSource then
    local expectedFaction=((r.source=="acaForeverGuide" or r.source=="acaForeverGuide02R4")) and "Alliance" or "Horde"
    if r.faction~=expectedFaction or not pos(r.skillRequired) or
       (r.merchantFavor~=nil and not pos(r.merchantFavor)) or
       ((r.source=="acaForeverGuide" or r.source=="acaForeverGuide02R4") and not pos(r.merchantFavor)) or
       not pos(r.spellID) or type(r.professionKey)~="string" or
       r.itemPageURL~="https://www.wowhead.com/forever/item="..tostring(itemID) then
     return nil,"PUBLIC_GUIDE_FIELD_CONFLICT"
    end
    if (r.source=="foreverCookingGuide" and r.professionKey~="COOKING") or
       (r.source=="foreverHordeLWItem" and
        (r.professionKey~="LEATHERWORKING" or itemID~=13287)) then
     return nil,"PUBLIC_GUIDE_FIELD_CONFLICT"
    end
   end
   local position=nil
   if r.mapID or r.x or r.y then
    if not pos(r.mapID) or type(r.x)~="number" or type(r.y)~="number" or
        r.x<0 or r.x>100 or r.y<0 or r.y>100 or
        type(d.citations[r.coordinateSource or r.source])~="string" then
     return nil,"PUBLIC_COORDINATE_INVALID"
    end
    position={uiMapID=r.mapID,x=r.x,y=r.y,sourceURL=d.citations[r.coordinateSource or r.source],
       authority="NON_FOREVER_HISTORICAL_COORDINATE_NOT_LIVE_70450",routeEligible=false}
   end
   rows[#rows+1]={itemID=itemID,sourceType=r.kind,npcName=r.name,npcID=r.npcID,
      idAuthority="PUBLIC_REFERENCE_PLUS_LEGACY_NO_LIVE_70450",evidenceState=r.state,
      referenceURL=url,referenceCheckedDate=r.verifiedDate or d.checkedDate,position=position,
      factionRequirement="UNKNOWN",factionVerified=false,live70450Verified=false,
      documentedVendorFaction=r.faction,guideSkillRequired=r.skillRequired,
      guideMerchantFavorCost=r.merchantFavor,documentedSpellID=r.spellID,
      documentedProfessionKey=r.professionKey,itemReferenceURL=r.itemPageURL,
      productionAuthority=false,routeEligible=false,readOnly=true}
  end
 end
 return rows,nil
end
-- Exactly one public QuestID->reward item->client teaching SpellID chain.
-- QuestV2 confirms ID only. Quest fulfillment, class/faction eligibility,
-- live reward inventory and actual NPC position remain UNKNOWN.
function Service:GetPublicQuestRewards(itemID,sourceBuild)
 if sourceBuild~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
 if not pos(itemID) then return nil,"INVALID_ITEM_ID" end
 local d,why=citationRows();if not d then return nil,why end
 if d.questRewardSourceSHA256~="6e552ddbec22f043dd6103408ff7596b8ac94ba1f404d6eb164fe13e85099edd" or
    type(d.questRewardRows)~="table" then return nil,"QUEST_REWARD_SOURCE_CONFLICT" end
 local rows={}
 for _,r in ipairs(d.questRewardRows[itemID] or {}) do
  local exact="https://www.wowhead.com/forever/quest="..tostring(r.questID).."/"
  local expectedNPC=r.faction=="Alliance" and 7852 or r.faction=="Horde" and 7854 or nil
  local expectedName=r.faction=="Alliance" and "Pratt McGrubben" or "Jangdor Swiftstrider"
  if not pos(r.questID) or not pos(r.spellID) or not pos(r.npcID) or
     r.npcID~=expectedNPC or r.npcName~=expectedName or
     type(r.url)~="string" or r.url:sub(1,#exact)~=exact or #r.url<=#exact then
    return nil,"PUBLIC_QUEST_FIELD_CONFLICT"
  end
  rows[#rows+1]={teachingItemID=itemID,documentedSpellID=r.spellID,
   sourceType="quest",questID=r.questID,questURL=r.url,
   npcName=r.npcName,npcID=r.npcID,factionReference=r.faction,
   evidenceTier="WOWHEAD_FOREVER_QUEST_REWARD_REFERENCE_NOT_LIVE",
   sourceVerifiedLive70450=false,questCompletionVerified=false,
   actualQuestEligibility="UNKNOWN",nativeDispatchAllowed=false,
   routeEligible=false,productionAuthority=false,readOnly=true}
 end
 return rows,nil
end
local function requireRecipe(key,spell,build)
 if build~=BUILD then return nil,"EXPLICIT_BUILD_70450_REQUIRED" end
 if not pos(spell) then return nil,"INVALID_SPELL_ID" end
 local acquisition=JLP:GetModule("Build70450RecipeAcquisition")
 if not acquisition then return nil,"ACQUISITION_SERVICE_UNAVAILABLE" end
 local r,err=acquisition:GetRecipeSources(key,spell,BUILD)
 if not r then return nil,err end
 if not liveBuild() then return nil,"LIVE_CLIENT_BUILD_UNKNOWN" end
 return r
end
local function immutableObservation(base,kind,npc,match,position)
 local observed=liveBuild()
 return {contract=Service.contract,sourceBuild=BUILD,observedClientBuild=observed,
   professionKey=base.professionKey,
  spellID=base.spellID,observationType=kind,sourceState="CURRENT_CLIENT_UI_SESSION_ONLY",
  observedNPC=npc.npcName,npcID=npc.npcID,teachingItemID=match,
  position=position,sourceBuildRelation=observed==BUILD and "MATCH" or "HISTORICAL_REFERENCE",
   factionRequirement="UNKNOWN",
  factionRequirementVerified=false,trainerAccessVerified=false,
  vendorAvailableForAllCharacters=false,dropTableVerified=false,
  availableOnServer="UNKNOWN_OUTSIDE_THIS_SESSION",readOnly=true,
  persistedToReference=false,routeEligible=false,productionAuthority=false,
  nativeDispatchAllowed=false}
end
function Service:ObserveMerchant(key,spell,build)
 local row,why=requireRecipe(key,spell,build);if not row then return nil,why end
 if not MerchantFrame or type(MerchantFrame.IsShown)~="function" or not MerchantFrame:IsShown() then
  return nil,"MERCHANT_WINDOW_NOT_OPEN" end
 local npc,err=npcIdentity();if not npc then return nil,err end
 if type(GetMerchantNumItems)~="function" or type(GetMerchantItemLink)~="function" then
  return nil,"MERCHANT_ITEM_API_UNAVAILABLE" end
 local ok,n=pcall(GetMerchantNumItems)
 if not ok or type(n)~="number" or n<0 or n>500 then return nil,"INVALID_MERCHANT_ITEM_COUNT" end
 local expected={}
 for _,t in ipairs(row.teachingItems) do expected[t.itemID]=true end
 local matches={}
 for i=1,n do
  local success,link=pcall(GetMerchantItemLink,i)
  if success and link then
   local id=itemIDFromLink(link)
   if id and expected[id] then matches[#matches+1]={itemID=id,merchantSlot=i} end
  end
 end
 if #matches==0 then return nil,"NO_TEACHING_ITEM_IN_CURRENT_MERCHANT_STOCK" end
 local obs=immutableObservation(row,"VENDOR_STOCK",npc,nil,currentPosition())
 obs.matches=matches;obs.observedStockAtOpenWindow=true;obs.trainerVerified=false
 return obs
end
function Service:ObserveTrainer(key,spell,build)
 local row,why=requireRecipe(key,spell,build);if not row then return nil,why end
 if not ClassTrainerFrame or type(ClassTrainerFrame.IsShown)~="function" or
     not ClassTrainerFrame:IsShown() then return nil,"TRAINER_WINDOW_NOT_OPEN" end
 local npc,err=npcIdentity();if not npc then return nil,err end
 -- Never infer spell ID from localized trainer text or profession name.
 if type(GetTrainerServiceSpellID)~="function" or
    type(GetNumTrainerServices)~="function" then return nil,"TRAINER_EXACT_SPELL_ID_API_UNAVAILABLE" end
 local ok,n=pcall(GetNumTrainerServices)
 if not ok or type(n)~="number" or n<0 or n>500 then return nil,"INVALID_TRAINER_ENTRY_COUNT" end
 local matched={}
 for i=1,n do
  local success,id=pcall(GetTrainerServiceSpellID,i)
  if success and id==spell then matched[#matched+1]=i end
 end
 if #matched==0 then return nil,"EXACT_SPELL_NOT_OFFERED_IN_TRAINER_UI" end
 local obs=immutableObservation(row,"TRAINER_SPELL",npc,nil,currentPosition())
 obs.trainerServiceSlots=matched;obs.exactSpellIDObserved=true
 return obs
end
function Service:ObserveLoot(key,spell,build)
 local row,why=requireRecipe(key,spell,build);if not row then return nil,why end
 if not LootFrame or type(LootFrame.IsShown)~="function" or not LootFrame:IsShown() then
  return nil,"LOOT_WINDOW_NOT_OPEN" end
 if type(GetNumLootItems)~="function" or type(GetLootSlotLink)~="function" or
    type(GetLootSourceInfo)~="function" then return nil,"LOOT_SOURCE_API_UNAVAILABLE" end
 local ok,n=pcall(GetNumLootItems)
 if not ok or type(n)~="number" or n<0 or n>100 then return nil,"INVALID_LOOT_SLOT_COUNT" end
 local expected={}
 for _,t in ipairs(row.teachingItems) do expected[t.itemID]=true end
 local matches={}
 for i=1,n do
  local valid,link=pcall(GetLootSlotLink,i)
  local id=valid and itemIDFromLink(link) or nil
  if id and expected[id] then
   local info={pcall(GetLootSourceInfo,i)}
   if not info[1] then return nil,"LOOT_SOURCE_API_ERROR" end
   -- First pair must specify exactly one creature; multi-source loot is ambiguous.
   if info[4]~=nil or not pos(info[3]) then return nil,"AMBIGUOUS_LOOT_SOURCE" end
   local npcID=npcIDFromGUID(info[2]);if not npcID then return nil,"LOOT_CREATURE_ID_UNAVAILABLE" end
   matches[#matches+1]={itemID=id,lootSlot=i,npcID=npcID,sourceGUID=info[2]}
  end
 end
 if #matches==0 then return nil,"NO_TEACHING_ITEM_IN_CURRENT_LOOT" end
 local obs=immutableObservation(row,"DIRECT_LOOT",{npcID=matches[1].npcID},nil,currentPosition())
 obs.matches=matches;obs.dropChance="UNKNOWN";obs.lootTableVerified=false
 return obs
end
JLP:RegisterModule("Build70450NPCSourceEvidence",Service)
