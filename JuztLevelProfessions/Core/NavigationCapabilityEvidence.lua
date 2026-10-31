local _,JLP=...
-- P0-A: read-only, versioned capability and live character/map evidence.
-- Source build is provenance, NEVER a blanket client permission.
-- Native travel, purchases, crafting and protected calls remain outside this contract.
local Evidence={contract="jlp-navigation-capability-evidence-v1",schema=1,
    provenancePolicy="PER_DATASET_SOURCE_BUILD",navigationOnly=true,nativeDispatchAllowed=false}
local function finite(n)
 return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end
local function validMap(n) return finite(n) and n>=1 and n==math.floor(n) end
local function validCoord(n) return finite(n) and n>=0 and n<=1 end
local function native(fn,...)
 if type(fn)~="function" then return nil end
 local ok,a,b,c=pcall(fn,...)
 if ok then return a,b,c end
 return nil
end
function Evidence:Read(scope)
 scope=scope or "POSITION"
 local info=JLP:GetModule("ClientBuildInfo")
 local b=info and type(info.Read)=="function" and info:Read() or nil
 local id=JLP:GetModule("CharacterIdentity")
 local character=id and type(id.GetCurrent)=="function" and id:GetCurrent(true) or nil
 local key=character and character.stableKey
 local faction=native(UnitFactionGroup,"player")
 local _,classToken=native(UnitClass,"player")
 local mapAPI=type(C_Map)=="table" and type(C_Map.GetBestMapForUnit)=="function"
   and type(C_Map.GetPlayerMapPosition)=="function"
 local proof={contract=self.contract,schema=self.schema,scope=scope,
   -- API evidence has no historical source build. Transport/checkpoint data do.
   provenancePolicy=self.provenancePolicy,
   observedClientBuild=b and b.buildNumber or nil,
   interface=b and b.interfaceVersion or nil,characterKey=key,
   guid=character and character.guid or nil,faction=faction,
   classToken=classToken,navigationOnly=true,nativeDispatchAllowed=false,
   capabilities={CHARACTER=key and "AVAILABLE" or "UNKNOWN",
     C_MAP_POSITION=mapAPI and "AVAILABLE" or "UNAVAILABLE",
     TAXI_NODE_LIST=type(NumTaxiNodes)=="function" and
       type(TaxiNodeGetType)=="function" and type(TaxiNodeName)=="function"
       and "AVAILABLE" or "UNAVAILABLE"}}
 if type(key)~="string" or key=="" then
   proof.status="UNKNOWN";proof.reason="CHARACTER_NOT_VERIFIED";return proof end
 if scope=="CHARACTER" then proof.status="AVAILABLE";return proof end
 if not mapAPI then
   proof.status="UNAVAILABLE";proof.reason="C_MAP_API_UNAVAILABLE";return proof end
 if scope=="MAP_API" then proof.status="AVAILABLE";return proof end
 local m=native(C_Map.GetBestMapForUnit,"player")
 local pos=validMap(m) and native(C_Map.GetPlayerMapPosition,m,"player") or nil
 local x,y
 if pos~=nil then
   -- WoW Vector2D may be a userdata/mixin rather than a plain Lua table.
   local ok,rx,ry=pcall(function()
     if type(pos.GetXY)=="function" then return pos:GetXY() end
     return pos.x,pos.y
   end)
   if ok then x,y=rx,ry end
 end
 if not validMap(m) or not validCoord(x) or not validCoord(y) then
   proof.status="UNKNOWN";proof.reason="NATIVE_PLAYER_POSITION_UNAVAILABLE";return proof end
 proof.mapID=m;proof.x=x;proof.y=y
 proof.positionEvidence="C_Map.GetPlayerMapPosition"
 if scope=="POSITION" then proof.status="AVAILABLE";return proof end
 if scope=="TAXI" then
   if proof.capabilities.TAXI_NODE_LIST~="AVAILABLE" then
     proof.status="UNAVAILABLE";proof.reason="TAXI_API_UNAVAILABLE";return proof end
   if (faction~="Horde" and faction~="Alliance") or
      type(classToken)~="string" or classToken=="" or
      type(proof.guid)~="string" or proof.guid=="" then
     proof.status="UNKNOWN";proof.reason="TAXI_CHARACTER_CONTEXT_UNKNOWN";return proof end
   proof.status="AVAILABLE";return proof
 end
 proof.status="UNKNOWN";proof.reason="UNKNOWN_CAPABILITY_SCOPE"
 return proof
end
function Evidence:Check(scope)
 local proof=self:Read(scope)
 return proof.status=="AVAILABLE",proof.reason or "CAPABILITY_AVAILABLE",proof
end
JLP:RegisterModule("NavigationCapabilityEvidence",Evidence)
