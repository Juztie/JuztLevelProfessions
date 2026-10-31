local _, JLP = ...
local SourceResolver = {}

local function faction()
    if type(UnitFactionGroup) ~= "function" then return nil end
    local ok, value = pcall(UnitFactionGroup, "player")
    if not ok then ok, value = pcall(UnitFactionGroup) end
    return ok and value or nil
end

local function firstOption(options, preferredFaction)
    if type(options) ~= "table" then return nil end
    local bucket = preferredFaction and options[preferredFaction]
    if type(bucket) == "table" and bucket[1] then return bucket[1] end
    if type(options.Neutral) == "table" and options.Neutral[1] then return options.Neutral[1] end
    if type(options.Alliance) == "table" and options.Alliance[1] then return options.Alliance[1] end
    if type(options.Horde) == "table" and options.Horde[1] then return options.Horde[1] end
    return nil
end

local function copyRecord(record)
    if type(record) ~= "table" then return nil end
    local out = {}
    for k,v in pairs(record) do
        if k=="nav" and type(v)=="table" then
            local nav={};for field,value in pairs(v) do nav[field]=value end
            out[k]=nav -- Never hand a mutable canonical coordinate table to a UI.
        else out[k]=v end
    end
    return out
end

local function professionLabel(key)
    local registry=JLP:GetModule("ProfessionRegistry")
    return registry and registry:GetDisplayName(key) or tostring(key or "")
end

local function normalizedRank(professionKey, rank)
    rank = tostring(rank or "")
    if rank == "" then return nil end
    local professionName = professionLabel(professionKey)
    if professionName ~= "" and not rank:lower():find(professionName:lower(), 1, true) then
        return rank .. " " .. professionName
    end
    return rank
end

function SourceResolver:GetRankRequirement(professionKey, rank)
    local sources = JLP.data and JLP.data.professionSources
    local rows = sources and sources.rankRequirements and sources.rankRequirements[professionKey]
    if type(rows) ~= "table" then return nil end
    local wanted = normalizedRank(professionKey, rank)
    local tier = tostring(rank or ""):match("^(%S+)")
    for _, row in ipairs(rows) do
        if tostring(row.rank or "") == tostring(wanted or "") or tostring(row.tier or "") == tostring(tier or "") then
            return copyRecord(row)
        end
    end
    return nil
end

function SourceResolver:GetTrainerOptions(professionKey, rank, preferredFaction)
    local sources = JLP.data and JLP.data.professionSources
    local profession = sources and sources.trainers and sources.trainers[professionKey]
    local resolvedRank = normalizedRank(professionKey, rank)
    local rankData = profession and profession[resolvedRank]
    if not rankData then return {} end
    preferredFaction = preferredFaction or faction()
    if rankData[preferredFaction] then return rankData[preferredFaction] end
    return rankData.Neutral or {}
end

local function decorateTrainer(self, professionKey, resolvedRank, record)
    if not record then return nil end
    local out = copyRecord(record)
    out.kind = "trainer"
    out.rank = resolvedRank
    out.profession = professionKey
    out.rankRequirement = self:GetRankRequirement(professionKey, resolvedRank)
    -- v1 lists Zephras Isle with conflicting 2521 / 2991 map IDs.
    -- Preserve NPC/zone advice, but never expose a precise navigation target
    -- on the strength of an unresolved contradictory user source.
    if out.zone=="Zephras Isle" then
        local root=JLP.data and JLP.data.professionSources
        local conflict={status="UNRESOLVED",mapIDs={2521,2991},
        source="Horde Profession Infomation v1.docx"}
        if conflict and conflict.status=="UNRESOLVED" then
            out.proposedNav=out.nav
            out.nav=nil
            out.navigationStatus="MAP_ID_CONFLICT_MANUAL_ONLY"
            out.sourceConflict="ZEPHRAS_ISLE_MAP_ID"
        end
    end
    return out
end

function SourceResolver:GetTrainerForRank(professionKey, rank, preferredFaction)
    local resolvedRank = normalizedRank(professionKey, rank)
    local options = self:GetTrainerOptions(professionKey, resolvedRank, preferredFaction)
    return decorateTrainer(self, professionKey, resolvedRank, options and options[1])
end

function SourceResolver:GetBestTrainerForRank(professionKey, rank, preferredFaction, origin)
    local resolvedRank = normalizedRank(professionKey, rank)
    local options = self:GetTrainerOptions(professionKey, resolvedRank, preferredFaction)
    if type(options) ~= "table" or not options[1] then return nil end
    local router = JLP:GetModule("TravelRouter")
    origin = origin or (router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil)
    local best, bestCost, bestIndex
    for index, record in ipairs(options) do
        local location = router and router:GetSourceLocation(record) or nil
        local cost = router and router:Cost(origin, location) or nil
        cost = tonumber(cost) or math.huge
        if not best or cost < bestCost or (cost == bestCost and index < bestIndex) then
            best, bestCost, bestIndex = record, cost, index
        end
    end
    local out = decorateTrainer(self, professionKey, resolvedRank, best)
    if out then
        out.selection = "travel-aware-best-candidate"
        out.travelCost = bestCost ~= math.huge and bestCost or nil
        out.optionIndex = bestIndex
    end
    return out
end

function SourceResolver:GetTrainerForGate(professionKey, gate, preferredFaction)
    if not gate then return nil end
    return self:GetTrainerForRank(professionKey, gate.rank, preferredFaction)
end

function SourceResolver:GetBestTrainerForGate(professionKey, gate, preferredFaction, origin)
    if not gate then return nil end
    return self:GetBestTrainerForRank(professionKey, gate.rank, preferredFaction, origin)
end

function SourceResolver:GetHordeTrainerResearch(key,rank)
    local options=self:GetTrainerOptions(key,rank,"Horde")
    local root=JLP.data and JLP.data.professionSources
    local conflict={status="UNRESOLVED",mapIDs={2521,2991},
        source="Horde Profession Infomation v1.docx"}
    local rows={}
    for _,trainer in ipairs(options or {}) do
        local t=copyRecord(trainer)
        t.faction="Horde"
        t.sourceAuthority="USER_RESEARCH_NOT_LIVE_VERIFIED"
        -- Positive identity binding is independent of legacy research labels.
        local owner=JLP:GetModule("OwnerAuthorizedNavigation")
        local qualified=owner and owner.GetTrainerByName and
            owner:GetTrainerByName(key,rank,t.name) or nil
        if qualified and qualified.nav and qualified.sourceQualified==true then
            t.sourceAuthority="OWNER_PRODUCTION_AUTHORIZED"
            t.ownerServiceID=qualified.serviceID
            t.qualifiedNav=copyRecord(qualified.nav)
            t.navigationMapIDQualified=true
            t.navigationStatus="OWNER_CANONICAL_TRAINER"
        end
        if t.zone=="Zephras Isle" and
            not (t.navigationStatus=="OWNER_CANONICAL_TRAINER" and
                 t.navigationMapIDQualified==true) and
            conflict and conflict.status=="UNRESOLVED" then
            t.navigationStatus="MAP_ID_CONFLICT_MANUAL_ONLY"
            t.navigationMapIDQualified=false
            t.alternativeMapIDs={2521,2991}
            t.rawSourceNav=t.nav -- historical original retained for manual display
            t.qualifiedNav=nil -- must NOT be passed to navigation widgets
        elseif t.navigationStatus~="OWNER_CANONICAL_TRAINER" then
            t.navigationStatus="SOURCE_COORDINATE_NOT_CLIENT_VERIFIED"
            t.navigationMapIDQualified=t.nav and t.nav.mapID~=nil or false
            t.qualifiedNav=t.navigationMapIDQualified and t.nav or nil
        end
        rows[#rows+1]=t
    end
    return {profession=key,rank=rank,trainers=rows,faction="Horde",
        nativeDispatchAllowed=false,persisted=false}
end

-- The only supported map navigation adapter for imported Horde trainers.
-- Raw `nav` exists for source comparison and user-visible manual reference,
-- but is NOT sufficient authorization for automatic map pin placement.
-- Guide train navigation must be bound to the SAME trainer displayed by the
-- current plan, not to a research-only ActionAssist source or the first trainer
-- for a rank. Owner authorization is navigation-only; it grants no trainer,
-- crafting, faction-access, or travel-completion authority.
function SourceResolver:GetQualifiedGuideTrainerWaypoint(professionKey, rank, displayedSource)
    if type(professionKey)~="string" or type(rank)~="string" or
       type(displayedSource)~="table" or type(displayedSource.name)~="string" or
       displayedSource.name=="" or
       (displayedSource.kind~=nil and displayedSource.kind~="trainer") then
        return nil,"GUIDE_TRAINER_IDENTITY_MISSING"
    end
    -- Never navigate to a different trainer merely because it is first in
    -- a rank list. Lookup requires an exact profession + rank + NPC name.
    local owner=JLP:GetModule("OwnerAuthorizedNavigation")
    if not owner or type(owner.GetTrainerByName)~="function" then
        return nil,"OWNER_TRAINER_CATALOGUE_UNAVAILABLE"
    end
    local canonical,reason=owner:GetTrainerByName(professionKey,rank,displayedSource.name)
    if not canonical or canonical.sourceQualified~=true or
       canonical.state~="SOURCE_QUALIFIED" or
       type(canonical.nav)~="table" then
        return nil,reason or "TRAINER_NAVIGATION_UNQUALIFIED"
    end
    -- If the displayed research entry carries precise coordinates, a
    -- disagreement with the owner-qualified waypoint must fail closed.
    local raw=displayedSource.nav
    if type(raw)=="table" and (raw.mapID~=nil or raw.x~=nil or raw.y~=nil) then
        if (raw.mapDomain~=nil and raw.mapDomain~="UI_MAP_ID") or
           type(raw.mapID)~="number" or raw.mapID~=canonical.nav.mapID or
           type(raw.x)~="number" or type(raw.y)~="number" or
           math.abs(raw.x-canonical.nav.x)>0.000001 or
           math.abs(raw.y-canonical.nav.y)>0.000001 then
            return nil,"GUIDE_TRAINER_COORDINATE_CONFLICT"
        end
    end
    return canonical,"OWNER_CANONICAL_GUIDE_TRAINER"
end

function SourceResolver:GetQualifiedHordeTrainerNav(key,rank,name)
    local view=self:GetHordeTrainerResearch(key,rank)
    for _,record in ipairs(view and view.trainers or {}) do
        if record.name==name then
            if record.navigationStatus~="OWNER_CANONICAL_TRAINER" or
               record.navigationMapIDQualified~=true or not record.qualifiedNav then
                return nil,record.navigationStatus or "NAVIGATION_UNQUALIFIED"
            end
            return copyRecord(record.qualifiedNav)
        end
    end
    return nil,"TRAINER_NOT_FOUND"
end
-- Exact item membership and canonical geography are separate from current
-- stock/access. No name-only join or caller-provided coordinates are admitted.
function SourceResolver:GetMaterialVendorSources(professionKey,itemID,recipeItem)
    if type(itemID)~="number" or itemID<1 or itemID~=math.floor(itemID) then return {} end
    local root=JLP.data and JLP.data.materialAcquisitionSources
    local owner=JLP:GetModule("OwnerAuthorizedNavigation")
    local who=faction();local result={}
    if not owner or (who~="Horde" and who~="Alliance") then return result end
    local router=JLP:GetModule("TravelRouter")
    local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin()
    for _,v in ipairs(root and root.vendors or {})do
        local found=false
        for _,id in ipairs(recipeItem and v.recipeItems or v.items or {})do if id==itemID then found=true end end
        if found and (v.faction==who or v.faction=="Neutral") then
            local source=owner:GetWaypoint("VENDOR",v.id)
            if source and source.npcID==v.npcID then
                source.profession=professionKey;source.materialItemID=not recipeItem and itemID or nil
                source.teachingItemID=recipeItem and itemID or nil
                source.accessNote=v.accessNote;source.accessStatus=v.accessStatus
                source.currentClientAvailabilityVerified=false;source.readOnly=true
                source.transportQualified=false
                local location=router and router.GetSourceLocation and router:GetSourceLocation(source)
                source.sameMap=origin and location and origin.mapID==location.mapID or false
                source.advisoryCost=router and origin and location and router:Cost(origin,location) or math.huge
                result[#result+1]=source
            end
        end
    end
    table.sort(result,function(a,b)
        if a.sameMap~=b.sameMap then return a.sameMap end
        if a.advisoryCost~=b.advisoryCost then return a.advisoryCost<b.advisoryCost end
        return a.serviceID<b.serviceID
    end)
    return result
end
function SourceResolver:GetRecipeVendorWaypoint(key,itemID,npcID)
    for _,source in ipairs(self:GetMaterialVendorSources(key,itemID,true))do
        if source.npcID==npcID then return source end
    end
end
function SourceResolver:GetRecipeSource(professionKey, recipe, preferredFaction)
    if professionKey=="COOKING"and type(recipe)=="number"then
        local secondary=JLP:GetModule("SecondaryLevelingPlanner");local api=JLP:GetModule("ProfessionAPI")
        local a=secondary and secondary:GetOperationalAccess(professionKey,api and api:Get(professionKey),recipe)
        return a and secondary:GetOperationalWaypoint(a)
    end
    if professionKey=="FIRST_AID"and type(recipe)=="number"then
        local aid=JLP:GetModule("ForeverFirstAidArtisan232");local api=JLP:GetModule("ProfessionAPI")
        local a=aid and aid:GetOperationalAccess(api and api:Get(professionKey),recipe)
        return a and aid:GetOperationalWaypoint(a)
    end
    if professionKey=="LEATHERWORKING" and type(recipe)=="number" then
        local data=JLP.data and JLP.data.leatherworking
        local root=data and data.progression
        local f=root and root.recipes and root.recipes[recipe]
        local g=f and f.dropResearch and data.recipeSourceGeography and data.recipeSourceGeography[recipe]
        local owner=JLP:GetModule("OwnerAuthorizedNavigation")
        local source=g and owner and owner:GetWaypoint("RECIPE_SOURCE",g.id)
        if source then
            source.recipeID=recipe;source.teachingItemID=f.recipeItemID
            source.accessNote=g.accessNote;source.positionQualification=g.positionQualification
            source.currentClientAvailabilityVerified=false;source.dropChance="UNKNOWN"
            source.transportQualified=false;source.readOnly=true
            return source
        end
    end
    if professionKey=="LEATHERWORKING" and recipe==19082 then
        local owner=JLP:GetModule("OwnerAuthorizedNavigation")
        local source=owner and owner:GetWaypoint("VENDOR","LW_JASE")
        if source then source.recipeID=19082;return source end
    end
    if type(recipe)=="number" then
        local bridge=JLP:GetModule("RecipeSourcePlanningBridge")
        local pattern=bridge and bridge.GetPatternAcquisition and bridge:GetPatternAcquisition(professionKey,recipe)
        local lead=pattern and pattern.primary
        if lead and lead.kind=="vendor" and lead.availabilityRank>=0 and
            not (lead.stockObservation and lead.stockObservation.recentUnavailable) then
            local source=self:GetRecipeVendorWaypoint(professionKey,pattern.itemID,lead.npcID)
            -- Qualified access instructions may have a position even while
            -- the access-unlock chain is unresolved. This is advisory travel,
            -- never a promotion of acquisition readiness or source rank.
            local access=pattern.vendorAccess
            local accessAllows=not access or access.status=="UNKNOWN"or access.status=="EQUIPPED"or access.status=="EQUIP_MANUALLY"or access.status=="CURRENT_USABLE_OFFER"
            if source and accessAllows and (lead.availabilityRank>=3 or source.accessStatus)then
                source.recipeID=recipe
                if access then source.accessNPCID=11278;source.accessItemID=13544;source.accessStage=access.status end
                return source
            end
        end
        if professionKey=="ENCHANTING" or professionKey=="ALCHEMY" or professionKey=="BLACKSMITHING" or professionKey=="ENGINEERING" or professionKey=="LEATHERWORKING" then
            local facts=JLP:GetModule("ProfessionPlanningFacts")
            local f=facts and ((professionKey=="ALCHEMY" or professionKey=="BLACKSMITHING" or professionKey=="ENGINEERING" or professionKey=="LEATHERWORKING") and facts.GetAlchemyContract and facts:GetAlchemyContract(recipe,professionKey) or professionKey=="ENCHANTING" and facts.GetEnchantingContract and facts:GetEnchantingContract(recipe))
            if f and f.learning=="automatic" then
                return {kind="automatic",recipeID=recipe,profession=professionKey,
                    name=f.name,sourceURL=f.minimumURL,learned="UNKNOWN",
                    readOnly=true,navigationQualified=false,nativeDispatchAllowed=false,
                    currentClientAvailabilityVerified=false,actionable=false}
            end
        end
        local catalogue=JLP:GetModule("ProfessionsDataCatalogue")
        local clientBuild=catalogue and catalogue.GetObservedClientBuild and
            catalogue:GetObservedClientBuild() or nil
        local proof=catalogue and catalogue.GetAcquisitionEvidence and
            catalogue:GetAcquisitionEvidence(professionKey,recipe,clientBuild) or nil
        if not proof then return nil end
        -- Do not offer faction-restricted actors to an incompatible player.
        -- UNKNOWN faction remains advisory: no access entitlement is inferred.
        local requestedFaction=preferredFaction or faction()
        if requestedFaction and requestedFaction~="Horde" and requestedFaction~="Alliance" then return nil end
        if requestedFaction=="Alliance" and proof.faction=="Horde" then return nil end
        local out=copyRecord(proof)
        out.recipeID=recipe
        out.evidenceState="SOURCE_QUALIFIED"
        -- SOURCE_QUALIFIED is historical field integrity, not live NPC
        -- location or client eligibility. Preserve the catalogue's explicit
        -- advisory flags across builds; do not promote navigation authority.
        out.currentClientAvailabilityVerified=false
        out.navigationQualified=false
        out.actionable=false
        out.readOnly=true
        out.productionAuthority="NOT_AUTHORIZED"
        out.nativeDispatchAllowed=false
        return out
    end
    local sources = JLP.data and JLP.data.professionSources
    local profession = sources and sources.recipes and sources.recipes[professionKey]
    local data = profession and profession[recipe]
    if not data then return nil end
    preferredFaction = preferredFaction or faction()
    local out = copyRecord(data)
    local option = firstOption(data.options, preferredFaction)
    if option then
        for k,v in pairs(option) do
            if out[k] == nil then
                if k=="nav" and type(v)=="table" then
                    local nav={};for field,value in pairs(v) do nav[field]=value end
                    out[k]=nav
                else out[k]=v end
            end
        end
    end
    out.profession = professionKey
    out.recipe = recipe
    return out
end

-- A compact DB70532 producer join in the existing Blacksmithing dataset.
-- Source alternatives never manufacture inventory or native permissions.
function SourceResolver:GetOrdinaryRodAcquisition(itemID,required)
    local data=JLP.data and JLP.data.blacksmithing
    local root=data and data.ordinaryRods
    local f=root and root.contract=="ordinary-rods-70532-v1" and root.rows[itemID]
    if not f or f.itemID~=itemID or f.sourceBuild~=70532 or f.professionKey~="BLACKSMITHING" or
        f.skillLineID~=164 or type(f.recipeID)~="number" or type(f.reagents)~="string" then return nil end
    required=tonumber(required)
    if not required or required<1 or required~=math.floor(required) or required==math.huge then return nil end
    local result={itemID=itemID,recipeID=f.recipeID,name=f.name,required=required,
        professionKey="BLACKSMITHING",sourceBuild=70532,producer=f,
        status="UNKNOWN_INVENTORY",options={},readOnly=true,nativeDispatchAllowed=false,
        observedOutputCredit=0,executionEligible=false}
    local function option(kind,label,meta)
        local o={kind=kind,source=kind,label=label,readOnly=true,nativeDispatchAllowed=false,
            currentAccessible=false,availabilityState="UNKNOWN",eligible=false}
        for k,v in pairs(meta or {})do o[k]=v end
        result.options[#result.options+1]=o;return o
    end
    local inventory=JLP:GetModule("Inventory")
    local owned=inventory and inventory.GetOwned and inventory:GetOwned(itemID)
    local function count(v)return type(v)=="number" and v>=0 and v<math.huge and v==math.floor(v)end
    local bags=owned and owned.bagKnown==true and count(owned.bags) and owned.bags or nil
    local bank=owned and owned.bankKnown==true and count(owned.bank) and owned.bank or nil
    result.bags=bags;result.bank=bank
    if bags then
        if bags>0 then option("bags","Observed ordinary rod in bags",{count=bags,eligible=true,currentAccessible=true,availabilityState="AVAILABLE"})end
        if bags>=required then result.status="BAGS_OBSERVED";result.missing=0
        elseif bank then
            result.missing=math.max(0,required-bags-bank)
            if bank>0 then
                option("bank","Withdraw ordinary rod from bank",{count=bank,eligible=true,requiresRetrieve=true,availabilityState="RETRIEVE"})
                result.status="BANK_OBSERVED"
            else result.status="ACQUIRE_ORDINARY_ROD"end
        end
    end
    local facts=JLP:GetModule("ProfessionPlanningFacts")
    local observation=facts and facts:Observe("BLACKSMITHING",f.recipeID)
    local signature={};for id,n in f.reagents:gmatch("(%d+):(%d+)")do signature[tonumber(id)]=tonumber(n)end
    local parity=observation and observation.requiredReagents~=nil
    for id,n in pairs(observation and observation.requiredReagents or {})do
        if signature[id]~=n then parity=false end;signature[id]=nil
    end
    if next(signature)then parity=false end
    local selfQualified=observation and observation.observed and observation.learned==true and parity and
        observation.output and observation.output.fixed and observation.output.itemID==itemID
    local craft=option("craft",selfQualified and "Observed Blacksmithing recipe; verify current skill, materials and hammer/anvil before crafting" or
        "Verify your Blacksmithing recipe and fixed schematic before crafting",{
        professionKey="BLACKSMITHING",recipeID=f.recipeID,professionLearned=observation and observation.observed or false,
        recipeLearned=observation and observation.learned,eligible=selfQualified==true,
        availabilityState=selfQualified and "RECIPE_AND_SCHEMATIC_OBSERVED_VERIFY_SKILL_AND_STATION" or "UNKNOWN",
        learningMinimumStatus="UNKNOWN_NOT_INFERRED_FROM_DB_MINRANK_OR_DIFFICULTY",
        craftabilityVerified=false,
        outputPerCraft=selfQualified and observation.output.minimum or nil,materials=f.reagents,
        requiresManualVerification=true,observedOutputCredit=0})
    result.selfCraft=craft
    -- Extend the existing cross-profession producer, never infer possession of
    -- Blacksmithing from Enchanting. Old reference-only fixtures stay UNKNOWN.
    local qualified=facts and facts.GetBlacksmithingContract and facts:GetBlacksmithingContract(f.recipeID)
    if qualified then
        craft.learningMinimum=qualified.learningMinimum
        craft.sourceLearningMinimumStatus=qualified.learningMinimum and qualified.minimumStatus or "UNKNOWN_EXACT_LEARNING_MINIMUM"
        craft.minimumPlanningFloor=qualified.minimum
        craft.toolItemID=qualified.toolItemID;craft.toolConsumed=false
        craft.stationID=qualified.focusID;craft.stationName=qualified.focusName
        craft.skillRequirementMet=observation and observation.observed and type(observation.skill)=="number" and observation.skill>=qualified.minimum or false
        craft.toolStatus="PLAYER_MANAGED_ORDINARY_TOOL"
        local access=JLP:GetModule("TailoringRecipeQualification")
        craft.stationStatus=qualified.focusID==0 and "MET" or access and access.RecipeAccess and
            access:RecipeAccess({recipeID=f.recipeID,sourceSpellFocusReference=qualified.focusID},"BLACKSMITHING") or "UNKNOWN"
        selfQualified=selfQualified and craft.skillRequirementMet
        -- eligible/selectedSource describe an acquisition candidate. Readiness
        -- is a separate field; an observed recipe can still require an anvil.
        craft.eligible=selfQualified==true
        craft.craftabilityVerified=selfQualified==true and craft.stationStatus=="MET"
        craft.learningMinimumStatus=craft.craftabilityVerified and craft.sourceLearningMinimumStatus or "UNKNOWN_CURRENT_READINESS_SOURCE_MINIMUM_AVAILABLE_SEPARATELY"
        craft.availabilityState=craft.craftabilityVerified and "CURRENT_LEARNED_FIXED_OUTPUT_SKILL_TOOL_STATION_OBSERVED" or "VERIFY_SKILL_TOOL_STATION"
        craft.requiresManualVerification=true -- advisory readiness is not native authority
    end
    if selfQualified and result.missing and result.missing>0 then
        local casts=math.ceil(result.missing/observation.output.minimum)
        local materials={}
        for id,n in f.reagents:gmatch("(%d+):(%d+)")do
            id,n=tonumber(id),tonumber(n)
            local storage=inventory and inventory.GetOwned and inventory:GetOwned(id)
            local bagKnown=storage and storage.bagKnown==true and count(storage.bags)
            materials[#materials+1]={itemID=id,perCraft=n,required=casts*n,storage=storage,
                owned=bagKnown and storage.bags or nil,
                missing=bagKnown and math.max(0,casts*n-storage.bags) or nil,
                inventoryKnown=bagKnown==true,observedOutputCredit=0,readOnly=true}
        end
        result.craftedRecipe={contract="ordinary-rods-70532-v1",itemID=itemID,name=f.name,
            recipe=f.name,recipeID=f.recipeID,professionKey="BLACKSMITHING",
            outputPerCraft=observation.output.minimum,outputNeeded=result.missing,
            craftsNeeded=casts,producedOutput=casts*observation.output.minimum,
            yieldStatus="CURRENT_FIXED_SCHEMATIC_READ_ONLY_NOT_STOCK",materials=materials,
            resolved=true,observedOutputCredit=0,readOnly=true,nativeDispatchAllowed=false}
    end
    local prices=JLP:GetModule("PriceResolver")
    local quote=prices and prices.GetFulfillmentCost and prices:GetFulfillmentCost(itemID,result.missing or required)
    local offered=quote and quote.complete==true and quote.trustedForCostEstimate==true and
        type(quote.cost)=="number" and quote.cost>0 and quote.cost<math.huge and
        type(quote.snapshotKey)=="string" and quote.snapshotKey~="" and quote.itemPriceReceipt~=nil
    option("auction",offered and "Observed AH offer; recheck before manual purchase" or "Verify Auction House offers and price",{
        eligible=offered==true,availabilityState=offered and "OBSERVED_QUOTE_NOT_RESERVED" or "UNKNOWN",
        price=offered and quote.cost or nil,snapshotKey=offered and quote.snapshotKey or nil})
    option("player-craft","Ask a Blacksmith to supply the ordinary rod manually",{
        professionKey="BLACKSMITHING",recipeID=f.recipeID,materials=f.reagents,
        availabilityState="MANUAL_COMMISSION_NOT_ARRANGED",requiresManualVerification=true})
    if f.vendorReference==true and itemID==6217 then
        option("vendor","Copper Rod vendor reference; inspect current stock",{sourceURL=f.vendorURL})
    end
    if result.status=="UNKNOWN_INVENTORY" then
        result.nextAction="Inspect bags and bank for "..f.name.." before acquiring another; inventory is UNKNOWN."
    elseif result.status=="BAGS_OBSERVED" then result.nextAction="Use the observed ordinary rod as a reagent for its Runed version; it is not the reusable tool."
    elseif result.status=="BANK_OBSERVED" then result.nextAction="Withdraw the observed "..f.name.." from your bank manually; observe bags before making its Runed version."
    else
        result.selectedSource=selfQualified and "craft" or offered and "auction" or "player-craft"
        result.nextAction=selfQualified and ("Inspect current skill, material and hammer/anvil requirements for your observed Blacksmithing recipe "..f.name.."; craft manually only when available, then observe the item before Enchanting. "..(qualified and ("Source learning minimum: "..tostring(qualified.learningMinimum or "UNKNOWN").."; current learned-state is separate.") or "The static learning minimum is UNKNOWN.")) or
            offered and ("Inspect the observed AH offer and manually buy "..f.name.."; purchase is not reserved or observed inventory.") or
            ("Arrange a manual Blacksmith commission for "..f.name.." (spell "..f.recipeID.."); alternatively inspect actual AH offers. No NPC vendor or price is assumed.")
    end
    return result
end

-- A private research row is not a recipe-source actor or travel destination.
-- Keep this out of GetRecipeSource(), which has a separate typed qualification gate.
function SourceResolver:GetPrivateResearchAcquisitionPreview(key,spellOrName,clientBuild)
    local catalogue=JLP:GetModule("ProfessionsDataCatalogue")
    if not catalogue or type(catalogue.GetPrivateResearchAdvisory)~="function" then
        return nil,"PILOT_UNAVAILABLE"
    end
    local receipt,reason=catalogue:GetPrivateResearchAdvisory(key,spellOrName,clientBuild)
    if not receipt then return nil,reason end
    return {contract="JLP-PRIVATE-ACQUISITION-ADVISORY-1",
        professionKey=key,spellID=receipt.spellID,
        state=receipt.state=="CONFLICT" and "CONFLICT" or "UNKNOWN",
        sourceActor=nil,trainer=nil,vendor=nil,npc=nil,drop=nil,scroll=nil,
        hordeAccess=nil,available=nil,travelTarget=nil,price=nil,
        materialTotals=nil,bankActions={},auctionActions={},actions={},
        sourceQualified=false,actionable=false,planMutationAllowed=false,
        nativeDispatchAllowed=false,readOnly=true,
        buildState=receipt.buildState,
        evidenceReason=receipt.evidenceReason},"RESEARCH_ACTOR_NOT_QUALIFIED"
end
function SourceResolver:GetVendorSource(professionKey, materialName, preferredFaction)
    local itemID=type(materialName)=="number" and materialName or nil
    local root=JLP.data and JLP.data.materialAcquisitionSources
    if not itemID and type(materialName)=="string" then
        local ref=root and root.materials and root.materials[materialName:lower()]
        itemID=ref and ref.itemID
    end
    if itemID then local candidates=self:GetMaterialVendorSources(professionKey,itemID)
        if candidates[1] then return candidates[1] end end
    local sources = JLP.data and JLP.data.professionSources
    local profession = sources and sources.vendors and sources.vendors[professionKey]
    local data = profession and profession[materialName]
    if not data then return nil end
    local out = copyRecord(data)
    local option = firstOption(data.options, preferredFaction or faction())
    if option then
        for k,v in pairs(option) do
            if out[k] == nil then
                if k=="nav" and type(v)=="table" then
                    local nav={};for field,value in pairs(v) do nav[field]=value end
                    out[k]=nav
                else out[k]=v end
            end
        end
    end
    out.profession = professionKey
    out.material = materialName
    out.kind = out.kind or "vendor"
    return out
end

-- QA004: resolve each UI category via a real canonical producer, never via
-- caller supplied coordinates, kind, name or optimistic qualification flags.
-- No Bank/AH/station coordinate data are independently qualified today.
-- A future verified producer can implement GetQualifiedServiceWaypoint without
-- altering the consumer or turning raw research records into authority.
local function nonempty(v) return type(v)=="string" and v~="" end
local function positiveID(v) return type(v)=="number" and v>=1 and v==math.floor(v) end
function SourceResolver:GetQualifiedServiceWaypoint(category,serviceID,profession)
    local provider=JLP:GetModule("OwnerAuthorizedNavigation")
    if not provider or not provider.GetWaypoint then return nil end
    if category~="BANK" and category~="AUCTION_HOUSE" and category~="CRAFT_STATION" and
        category~="TRAINER" and category~="VENDOR" then return nil end
    local r=provider:GetWaypoint(category,serviceID)
    if r and profession~=nil and r.profession~=profession then return nil end
    return r
end
function SourceResolver:GetOwnerServiceLocations(category)
    local provider=JLP:GetModule("OwnerAuthorizedNavigation")
    return provider and provider.GetServiceList and provider:GetServiceList(category) or {}
end
function SourceResolver:GetOwnerTrainerForRank(profession,rank)
    local provider=JLP:GetModule("OwnerAuthorizedNavigation")
    local targetRank=tostring(rank):upper():match("^(%S+)")
    if (profession=="TAILORING" or profession=="ENCHANTING" or profession=="ALCHEMY" or profession=="BLACKSMITHING" or profession=="ENGINEERING" or profession=="LEATHERWORKING" or profession=="SKINNING"or profession=="MINING"or profession=="HERBALISM") and (targetRank=="JOURNEYMAN" or targetRank=="EXPERT" or targetRank=="ARTISAN") and
        provider and provider.GetServiceList then
        local who=faction()
        if who~="Horde" and who~="Alliance" then return nil end
        local router=JLP:GetModule("TravelRouter")
        local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin()
        local best,bestLocal,bestCost
        for _,row in ipairs(provider:GetServiceList("TRAINER"))do
            if row.profession==profession and row.rank==targetRank and row.sourceQualified==true and
                (row.faction==who or row.faction=="Neutral") and row.nav and row.nav.mapDomain=="UI_MAP_ID" and
                not (type(row.zone)=="string" and row.zone:find("Zephras Isle",1,true)) then
                local location=router and router:GetSourceLocation(row)
                local isLocal=origin and location and origin.mapID and origin.mapID==location.mapID or false
                local cost=router and router:Cost(origin,location) or math.huge
                if not best or (isLocal and not bestLocal) or (isLocal==bestLocal and cost<bestCost) then
                    best,bestLocal,bestCost=row,isLocal,cost
                end
            end
        end
        return best
    end
    return provider and provider.GetTrainerForRank and provider:GetTrainerForRank(profession,rank)
end
local function producerFor(self, category, source)
    if category=="CURRENT_STEP"and source.fishingApproach==true then
        local secondary=JLP:GetModule("SecondaryLevelingPlanner")
        return secondary and secondary:GetCanonicalFishingApproach(source)
    end
    if category=="CURRENT_STEP"and source.secondaryAccess==true then
        local secondary=JLP:GetModule("SecondaryLevelingPlanner");local api=JLP:GetModule("ProfessionAPI")
        local a=secondary and secondary:GetOperationalAccess(source.profession,api and api:Get(source.profession),source.recipeID)
        if not a or a.status~=source.accessStage or a.itemID~=source.teachingItemID or a.rank~=source.accessRank or a.questID~=source.accessQuestID then return nil end
        if a.status=="RETRIEVE_BOOK_BANK"then
            local bank=self:GetQualifiedServiceWaypoint("BANK",source.serviceID)
            if bank then bank.profession=source.profession;bank.recipeID=a.recipeID;bank.secondaryAccess=true;bank.accessStage=a.status;bank.teachingItemID=a.itemID;bank.accessRank=a.rank end
            return bank
        end
        return secondary:GetCanonicalWaypoint(source)
    end
    if source.profession=="CLOTH"and source.kind=="drop"then
        local bridge=JLP:GetModule("GatheringMaterialBridge")
        return bridge and bridge:GetClothWaypoint(tonumber(source.material),source.serviceID)
    end
    if category=="CURRENT_STEP"and source.firstAidAccess==true and source.profession=="FIRST_AID"then
        local aid=JLP:GetModule("ForeverFirstAidArtisan232");local api=JLP:GetModule("ProfessionAPI")
        local a=aid and aid:GetOperationalAccess(api and api:Get("FIRST_AID"),source.recipeID)
        if not a or a.status~=source.accessStage or a.itemID~=source.teachingItemID or a.rank~=source.accessRank or a.questID~=source.accessQuestID then return nil end
        if a.status=="RETRIEVE_BOOK_BANK"then
            local bank=self:GetQualifiedServiceWaypoint("BANK",source.serviceID)
            if bank then bank.profession="FIRST_AID";bank.recipeID=a.recipeID;bank.firstAidAccess=true;bank.accessStage=a.status;bank.teachingItemID=a.itemID;bank.accessRank=a.rank end
            return bank
        end
        return aid:GetCanonicalWaypoint(source)
    end
    if category=="CURRENT_STEP"and source.accessNPCID==11278 and source.profession=="BLACKSMITHING"then
        local api=JLP:GetModule("ProfessionAPI")
        local observation=api and api.GetReadOnlyRecipeObservation and api:GetReadOnlyRecipeObservation(source.recipeID,"BLACKSMITHING")
        if not observation or observation.readOnlyObserved~=true or observation.learned~=false then return nil end
        local bridge=JLP:GetModule("RecipeSourcePlanningBridge")
        local pattern=bridge and bridge:GetPatternAcquisition("BLACKSMITHING",source.recipeID)
        if not pattern or pattern.patternPossession=="UNKNOWN"or pattern.status=="LEARN_ITEM_MANUALLY"or pattern.status=="RETRIEVE_PATTERN_FROM_BANK"or pattern.status=="SOURCE_UNAVAILABLE"then return nil end
        local access=pattern.vendorAccess
        if not access then return nil end
        if source.kind=="vendor"then return self:GetRecipeSource("BLACKSMITHING",source.recipeID)end
        local owner=JLP:GetModule("OwnerAuthorizedNavigation")
        if source.kind=="quest_giver"then return owner and owner:GetMagnusQuestWaypoint(source.recipeID,access)end
        if source.kind=="bank"and access.status=="BANK"then
            local bank=self:GetQualifiedServiceWaypoint("BANK",source.serviceID)
            if bank then bank.profession="BLACKSMITHING";bank.recipeID=source.recipeID;bank.accessNPCID=11278;bank.accessItemID=13544;bank.accessStage="BANK"end
            return bank
        end
        return nil
    end
    if category=="CURRENT_STEP" and ((source.kind=="dungeon_entrance" and source.serviceID=="ULDAMAN_REAR") or
        (source.kind=="dungeon_npc" and source.serviceID=="ULDAMAN_ANNORA")) and source.profession=="ENCHANTING" then
        local bridge=JLP:GetModule("CurrentStepTravelBridge")
        local api=JLP:GetModule("ProfessionAPI")
        local step
        if source.learningKind=="RANK" then step={kind="train",rank="Artisan"}
        elseif source.learningKind=="RECIPE" and positiveID(source.learningRecipeID) then
            local observation=api and api.GetReadOnlyRecipeObservation and api:GetReadOnlyRecipeObservation(source.learningRecipeID,"ENCHANTING")
            local learned
            if observation and observation.readOnlyObserved==true then learned=observation.learned end
            step={kind="craft",recipeID=source.learningRecipeID,learned=learned}
        end
        local nav=step and bridge and bridge.ForAnnoraStep and bridge:ForAnnoraStep(step)
        return nav and nav.source
    end
    if (category=="CURRENT_STEP" or category=="VENDOR" or category=="MATERIAL_SOURCE") and
        source.kind=="vendor" and positiveID(source.materialItemID) and nonempty(source.profession) then
        for _,candidate in ipairs(self:GetMaterialVendorSources(source.profession,source.materialItemID))do
            if candidate.serviceID==source.serviceID then return candidate end
        end
        return nil
    end
    if (category=="CURRENT_STEP" or category=="RECIPE_SOURCE") and (source.kind=="vendor"or source.kind=="drop") and
        positiveID(source.recipeID) and nonempty(source.profession) then
        return self:GetRecipeSource(source.profession,source.recipeID,source.faction)
    end
    if category=="CURRENT_STEP"and source.kind=="gather"and source.profession=="HERBALISM"then
        local bridge=JLP:GetModule("GatheringMaterialBridge")
        return bridge and bridge:GetHerbalismWaypoint(tonumber(source.material),source.serviceID)
    end
    if category=="CURRENT_STEP"and source.kind=="gather"and source.profession=="MINING"then
        local bridge=JLP:GetModule("GatheringMaterialBridge")
        return bridge and bridge:GetMiningWaypoint(tonumber(source.material),source.serviceID)
    end
    if category=="CURRENT_STEP" and source.kind=="gather" and source.profession=="SKINNING" then
        local bridge=JLP:GetModule("GatheringMaterialBridge")
        return bridge and bridge:GetSkinningWaypoint(tonumber(source.material),source.serviceID)
    end
    local key=source.profession or source.professionKey
    local recipeID=source.recipeID
    if recipeID==nil and positiveID(source.recipe) then recipeID=source.recipe end
    local rank=source.rank
    local material=source.material
    local factionHint=source.faction
    local canRecipe=nonempty(key) and positiveID(recipeID)
    local canTrainer=nonempty(key) and nonempty(rank)
    local canVendor=nonempty(key) and nonempty(material)
    -- Scoped owner-admitted categories MUST include the canonical record ID.
    -- Never accept request flags, ad-hoc coordinates or a claimed owner SHA.
    if source.ownerDataAuthorized==true then
        if nonempty(source.serviceID) and
           (category=="TRAINER" or category=="BANK" or category=="AUCTION_HOUSE" or
            category=="CRAFT_STATION" or category=="CURRENT_STEP") then
            local scoped=category
            if category=="CURRENT_STEP" then
                if source.kind=="trainer" then scoped="TRAINER"
                elseif source.kind=="bank" then scoped="BANK"
                elseif source.kind=="auction_house" then scoped="AUCTION_HOUSE"
                elseif source.kind=="craft_station"and (source.profession=="MINING" or source.profession=="BLACKSMITHING")then scoped="CRAFT_STATION"
                elseif source.kind=="vendor" and source.recipeID==19082 and key=="LEATHERWORKING" then
                    return self:GetRecipeSource(key,source.recipeID,factionHint)
                else return nil end
            end
            return self:GetQualifiedServiceWaypoint(scoped,source.serviceID,key)
        end
        return nil
    end
    if category=="RECIPE_SOURCE" then
        if canRecipe then return self:GetRecipeSource(key,recipeID,factionHint) end
    elseif category=="TRAINER" then
        if canTrainer then return self:GetTrainerForRank(key,rank,factionHint) end
    elseif category=="VENDOR" then
        if canVendor then return self:GetVendorSource(key,material,factionHint) end
    elseif category=="CURRENT_STEP" then
        -- A current step can point at an existing recipe, trainer or vendor.
        -- Mixed typed identities are ambiguous and must not silently select
        -- whichever producer happens to pass first.
        local count=(canRecipe and 1 or 0)+(canTrainer and 1 or 0)+(canVendor and 1 or 0)
        if count~=1 then return nil end
        if canRecipe then return self:GetRecipeSource(key,recipeID,factionHint) end
        if canTrainer then return self:GetTrainerForRank(key,rank,factionHint) end
        return self:GetVendorSource(key,material,factionHint)
    elseif category=="MATERIAL_SOURCE" then
        -- Material lookup is an actual vendor/material identity, not an
        -- arbitrary recipe/source with a claimed material label.
        if canVendor and not canRecipe and not canTrainer then
            return self:GetVendorSource(key,material,factionHint)
        end
    elseif category=="BANK" or category=="AUCTION_HOUSE" or category=="CRAFT_STATION" then
        -- Currently no verified location producer in the shipped data.
        -- Use a separately implemented, canonical service/station lookup if
        -- one is ever admitted. Do not fallback to GetRecipeSource or nav.
        if nonempty(source.serviceID) and type(self.GetQualifiedServiceWaypoint)=="function" then
            return self:GetQualifiedServiceWaypoint(category,source.serviceID,key)
        end
    end
    return nil
end

local function sameIdentity(expected,provided,field)
    return expected[field]==provided[field]
end

-- Revalidate the selected consumer separately from the bank's geography.
-- Delivery, cancellation and another character must retire this bank intent.
local function currentCookingKitBank(source)
    if source.kind~="bank" or source.materialConsumer~="COOKING" or source.materialRequired~=1 or
       type(UnitGUID)~="function" or type(source.observerGUID)~="string" or
       not source.observerGUID:match("^Player%-") or UnitGUID("player")~=source.observerGUID then return false end
    local api=JLP:GetModule("ProfessionAPI")
    local datasets=JLP:GetModule("ProfessionDatasetProvider")
    local current=JLP:GetModule("UniversalCurrentStep")
    local p=api and api:Get("COOKING")
    local d=datasets and datasets:GetPlannerDataset("COOKING",{allowCandidate=true})
    local c=p and d and current and current:Recommend("COOKING",p,d)
    local prep=c and c.stationPreparation
    return c and c.recipeID==source.consumerRecipeID and prep and prep.mode=="KIT" and
        prep.status=="RETRIEVE_KIT_BANK" and prep.itemID==source.materialItemID and
        UnitGUID("player")==source.observerGUID
end

function SourceResolver:VerifyNavigationWaypoint(category,source)
    if type(source)~="table" or type(source.nav)~="table" or
        source.sourceQualified~=true or source.state~="SOURCE_QUALIFIED" or
        (source.status~=nil and source.status~=source.state) or
        source.nav.mapDomain~="UI_MAP_ID" or
        source.productionAuthorized==true or source.nativeDispatchAllowed==true then
        return false,"SOURCE_NOT_QUALIFIED"
    end
    if category=="CURRENT_STEP" and source.cookingKitBank==true then
        if not currentCookingKitBank(source) then return false,"STALE_COOKING_KIT_BANK_CONSUMER" end
        local bank={};for k,v in pairs(source)do bank[k]=v end
        bank.cookingKitBank=nil;bank.materialConsumer=nil;bank.consumerRecipeID=nil
        bank.materialItemID=nil;bank.materialRequired=nil;bank.observerGUID=nil
        return self:VerifyNavigationWaypoint(category,bank)
    end
    if category=="CURRENT_STEP" and source.kind=="vendor" and positiveID(source.materialItemID) then
        local inventory=JLP:GetModule("Inventory")
        local owned=inventory and inventory.GetOwned and inventory:GetOwned(source.materialItemID)
        if not positiveID(source.materialRequired) or not owned or owned.bagKnown~=true or
            type(owned.bags)~="number" or owned.bags<0 or owned.bags>=source.materialRequired then
            return false,"CURRENT_MATERIAL_SHORTAGE_NOT_OBSERVED"
        end
        local evidence=JLP:GetModule("RecipeAccessEvidence")
        local offer=evidence and evidence.GetMerchantPlanningHint and evidence:GetMerchantPlanningHint(source.materialItemID,source.npcID)
        if offer and (offer.recentUnavailable or offer.status=="OUT_OF_STOCK" or offer.status=="NOT_OFFERED" or offer.status=="INELIGIBLE")then
            return false,"CURRENT_SUPPLIER_UNAVAILABLE"
        end
    end
    if category=="CURRENT_STEP" and (source.kind=="vendor"or source.kind=="drop") and positiveID(source.recipeID) then
        local bridge=JLP:GetModule("RecipeSourcePlanningBridge")
        local pattern=bridge and bridge:GetPatternAcquisition(source.profession,source.recipeID)
        if pattern and (pattern.patternPossession=="BAGS_OBSERVED" or pattern.patternPossession=="BANK_OBSERVED")then
            return false,"OBSERVED_RECIPE_ITEM_REQUIRES_LEARNING_OR_BANK_NOT_VENDOR_TRAVEL"
        end
        local api=JLP:GetModule("ProfessionAPI")
        local observed=api and api.GetReadOnlyRecipeObservation and api:GetReadOnlyRecipeObservation(source.recipeID,source.profession)
        if observed and observed.readOnlyObserved==true and observed.learned==true then
            return false,"RECIPE_ALREADY_OBSERVED_LEARNED"
        end
    end
    local expected=producerFor(self,category,source)
    if not expected then return false,"NO_CANONICAL_SOURCE_PRODUCER" end
    local a,b=expected.nav,source.nav
    if type(a)~="table" or expected.sourceQualified~=true or
       expected.state~="SOURCE_QUALIFIED" or
       (expected.status~=nil and expected.status~=expected.state) or
       a.mapDomain~="UI_MAP_ID" or a.mapID~=b.mapID or
       a.x~=b.x or a.y~=b.y or
       a.evidence~=b.evidence or not nonempty(a.evidence) or
       expected.sourceQualified~=source.sourceQualified or
       expected.state~=source.state or
       expected.profession~=(source.profession or source.professionKey) or
       not sameIdentity(expected,source,"recipeID") or
       not sameIdentity(expected,source,"rank") or
       not sameIdentity(expected,source,"material") or
       not sameIdentity(expected,source,"materialItemID") or
       not sameIdentity(expected,source,"teachingItemID") or
       not sameIdentity(expected,source,"serviceID") or
       not sameIdentity(expected,source,"npcID") or
       not sameIdentity(expected,source,"goalNPCID") or
       not sameIdentity(expected,source,"approachOnly") or
       not sameIdentity(expected,source,"pointRole") or
       not sameIdentity(expected,source,"directBearing") or
       not sameIdentity(expected,source,"referenceID") or
       not sameIdentity(expected,source,"bindingEvidence") or
       not sameIdentity(expected,source,"bindingArtID") or
       not sameIdentity(expected,source,"bindingGroupID") or
       not sameIdentity(expected,source,"bindingFloor") or
       not sameIdentity(expected,source,"accessNPCID") or
       not sameIdentity(expected,source,"accessItemID") or
       not sameIdentity(expected,source,"accessQuestID") or
       not sameIdentity(expected,source,"accessStage") or
       not sameIdentity(expected,source,"metricGeometry") or
       not sameIdentity(expected,source,"learningKind") or
       not sameIdentity(expected,source,"learningRecipeID") or
       not sameIdentity(expected,source,"trainingSpellID") or
       ((expected.profession=="MINING"or expected.profession=="HERBALISM")and (not sameIdentity(expected,source,"objectID")or not sameIdentity(expected,source,"resourceKey")))or
       (source.fishingApproach==true and (not sameIdentity(expected,source,"pointType")or not sameIdentity(expected,source,"geometryType")or not sameIdentity(expected,source,"materialRequired")or not sameIdentity(expected,source,"materialConsumer")))or
       (source.fishingApproach==true and (not sameIdentity(expected,source,"zoneApproach")or not sameIdentity(expected,source,"questID")or
        not sameIdentity(expected,source,"questObjectiveKey")or not sameIdentity(expected,source,"questObjectiveText")or
        not sameIdentity(expected,source,"questNumFulfilled")or not sameIdentity(expected,source,"questNumRequired")or not sameIdentity(expected,source,"observerGUID")))or
       not sameIdentity(expected,source,"stationID") or
       (expected.profession=="MINING"and not sameIdentity(expected,source,"stationFocus"))or
       not sameIdentity(expected,source,"faction") or
       expected.hordeAccess~=source.hordeAccess or
       expected.ownerDataAuthorized~=source.ownerDataAuthorized or
       expected.ownerAuthority~=source.ownerAuthority or
       expected.sourceSHA~=source.sourceSHA or
       expected.sourceRow~=source.sourceRow or
       (source.professionKey~=nil and source.professionKey~=expected.profession) or
       (source.recipe~=nil and source.recipe~=expected.recipe and
        source.recipe~=expected.recipeID) then
       return false,"CANONICAL_WAYPOINT_MISMATCH"
    end
    -- Kind/type are not authorities. When the canonical record defines them,
    -- callers cannot relabel a vendor as a recipe or a bank as a station.
    if (source.kind~=nil and source.kind~=expected.kind) or
       (source.type~=nil and source.type~=expected.type) then
       return false,"CANONICAL_SOURCE_KIND_MISMATCH"
    end
    return true,"CANONICAL_WAYPOINT_BOUND"
end

function SourceResolver:Format(source, includeEvidence)
    if not source then return nil end
    local parts = {}
    if source.name then parts[#parts+1] = tostring(source.name) end
    local place = source.area or source.zone
    if source.area and source.zone and source.area ~= source.zone then
        place = tostring(source.area) .. ", " .. tostring(source.zone)
    end
    if place then parts[#parts+1] = tostring(place) end
    if type(source.nav) == "table" and tonumber(source.nav.x) and tonumber(source.nav.y) then
        parts[#parts+1] = string.format("%.1f, %.1f", tonumber(source.nav.x) * 100, tonumber(source.nav.y) * 100)
    end
    local text = table.concat(parts, " - ")
    if text == "" then
        if source.kind == "drop-pattern" then text = source.note or "World/drop pattern" else text = source.kind or "Source available" end
    end
    if source.note and source.kind ~= "drop-pattern" then text = text .. " (" .. tostring(source.note) .. ")" end
    if includeEvidence and source.evidence then text = text .. " [" .. tostring(source.evidence) .. "]" end
    return text
end

function SourceResolver:DescribeRecipe(professionKey, recipe, fallbackKind)
    local source = self:GetRecipeSource(professionKey, recipe)
    if source then
        local label = source.kind or fallbackKind or "recipe-source"
        local formatted = self:Format(source, false)
        return string.format("%s: %s", tostring(label), tostring(formatted or "source available")), source
    end
    if fallbackKind == "trainer" or not fallbackKind then return "Trainer-taught", nil end
    return tostring(fallbackKind), nil
end

JLP:RegisterModule("SourceResolver", SourceResolver)
