local _, JLP = ...
-- Build-70450 guidance continuity. A checkpoint is untrusted *intent*, not
-- proof of a transport edge, character, source or completed journey leg.
-- Auto-resume only after fresh canonical source admission and live-origin routing.
-- Never persist executable routes or replay saved transport progress.
local Service={contract="jlp-travel-continuity-capability-v3",navigationOnly=true,
 nativeDispatchAllowed=false,initialized=false,status="UNINITIALIZED",sequence=0}
local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function capability(scope)
 local e=JLP:GetModule("NavigationCapabilityEvidence")
 if not e or type(e.Check)~="function" then return false,"CAPABILITY_CONTRACT_UNAVAILABLE" end
 return e:Check(scope or "CHARACTER")
end
local function identity()
 local id=JLP:GetModule("CharacterIdentity")
 local v=id and id.GetCurrent and id:GetCurrent(true)
 return v and v.stableKey or nil
end
local function account()
 local db=JLP.DB
 if type(db)~="table" or type(db.account)~="table" then return nil end
 db.account.travelContinuity70450=db.account.travelContinuity70450 or {schema=1,characters={}}
 local store=db.account.travelContinuity70450
 if store.schema~=1 or type(store.characters)~="table" then return nil end
 return store.characters
end
local function validPoint(p)
 return type(p)=="table" and finite(p.mapID) and p.mapID>=1 and p.mapID==math.floor(p.mapID)
  and finite(p.x) and finite(p.y) and p.x>=0 and p.x<=1 and p.y>=0 and p.y<=1
end
local function samePoint(a,b)
 return validPoint(a) and validPoint(b) and a.mapID==b.mapID and
    math.abs(a.x-b.x)<0.0000001 and math.abs(a.y-b.y)<0.0000001
end
local function validRecord(r,key)
 -- Reload checkpoints are intents only, never permanent destination authority.
 -- A missing or implausible timestamp cannot be silently revived months later.
 local now=type(time)=="function" and time() or nil
 local fresh=type(r)=="table" and finite(r.savedAt) and finite(now) and
    r.savedAt>=0 and r.savedAt<=now and now-r.savedAt<=2592000
 return fresh and ((r.schema==2 and r.sourceBuild==70450 and
    (r.clientBuild==nil or (finite(r.clientBuild) and r.clientBuild>=1 and
     r.clientBuild==math.floor(r.clientBuild)))) or
    (r.schema==1 and r.build==70450)) and
  r.characterKey==key and validPoint(r.destination) and
  type(r.category)=="string" and #r.category<=40 and
  r.category~="GATHERING" and r.navigationOnly==true and
  r.nativeDispatchAllowed==false and r.requiresFreshAdmission==true and
  (r.contextToken==nil or (type(r.contextToken)=="string" and #r.contextToken<=150)) and
  (r.paused==nil or type(r.paused)=="boolean")
end
local function snapshot(owner,allowPaused)
 local o=owner or JLP:GetModule("IntegratedDestinationOwner")
 local s=o and o.GetSnapshot and o:GetSnapshot() or nil
 if not s or not validPoint(s.point) or s.status=="STALE" or s.status=="STOPPED" or
  (s.status=="PAUSED" and not allowPaused) or s.category=="GATHERING" or
  s.sourceStatus=="PARTIAL" then return nil end
 return s
end
function Service:Initialize()
 if self.initialized and self.status~='CHARACTER_OR_DB_UNAVAILABLE' then return self.status end
 self.initialized=true
 local supported,reason=capability("CHARACTER")
 if not supported then self.status=reason;return self.status end
 local key=identity();local rows=account()
 if not key or not rows then self.status="CHARACTER_OR_DB_UNAVAILABLE";return self.status end
 local rec=rows[key]
 if rec then
   if validRecord(rec,key) then
     self.pending=rec
     self.status="PENDING_REVALIDATION"
   else
     rows[key]=nil
     self.status="INVALID_CHECKPOINT_DISCARDED"
   end
 else self.status="NO_CHECKPOINT" end
 return self.status
end
-- Paused destinations are stored as intent only. No saved route or travel leg
-- may be used to navigate until the player explicitly resumes.
local function makeRecord(owner,paused)
 local s=snapshot(owner,paused)
 if not s or (paused and s.status~="PAUSED") or
     (not paused and s.status=="PAUSED") then return nil end
 local source=type(owner)=='table' and owner.resumeSource or nil
 if s.category~="MANUAL" and
    (type(source)~="table" or type(source.nav)~="table") then return nil end
 local _,_,proof=capability("CHARACTER")
 return {schema=2,sourceBuild=70450,clientBuild=proof and proof.observedClientBuild or nil,
   interface=proof and proof.interface or nil,category=s.category,
   contextToken=s.contextToken,planRevision=s.planRevision,
   destination={mapID=s.point.mapID,x=s.point.x,y=s.point.y},
   sourceProof=source,restoreExplicit=s.priority and s.priority>1 or false,
   paused=paused==true,
   navigationOnly=true,nativeDispatchAllowed=false,requiresFreshAdmission=true,
   savedAt=type(time)=="function" and time() or nil}
end
function Service:SavePaused(owner)
 local allowed,why=capability("CHARACTER")
 if not allowed then return false,why end
 local key=identity();local rows=account()
 if not key or not rows then return false,"CHARACTER_OR_DB_UNAVAILABLE" end
 local rec=makeRecord(owner,true)
 if not rec then return false,"NO_QUALIFIED_PAUSED_DESTINATION" end
 rec.characterKey=key
 rows[key]=rec;self.pending=rec;self.status="PAUSED_CHECKPOINT_SAVED"
 return true,self.status
end
function Service:Save(owner)
 local allowed,why=capability("CHARACTER")
 if not allowed then return false,why end
 local key=identity();local rows=account()
 if not key or not rows then return false,"CHARACTER_OR_DB_UNAVAILABLE" end
 local rec=makeRecord(owner,false)
 if not rec then return false,"NO_QUALIFIED_ACTIVE_DESTINATION" end
 rec.characterKey=key
 rows[key]=rec
 self.pending=rec;self.status="CHECKPOINT_SAVED"
 return true,"ADVISORY_CHECKPOINT_SAVED"
end
function Service:Clear(reason)
 local key=identity();local rows=account()
 if key and rows then rows[key]=nil end
 self.pending=nil;self.status=reason or "CLEARED"
 return true
end
function Service:OnOwnerSelected(owner)
 local allowed,why=capability("CHARACTER")
 if not allowed then self.status=why;return false,why end
 if not self.initialized then self:Initialize() end
 local key=identity();local rows=account()
 local rec=self.pending or (key and rows and rows[key])
 if not rec then return false,"NO_PENDING_CHECKPOINT" end
 if not validRecord(rec,key) then
   self:Clear("INVALID_CHECKPOINT_DISCARDED")
   return false,"INVALID_CHECKPOINT_DISCARDED"
 end
 local s=snapshot(owner)
 if not s or not samePoint(s.point,rec.destination) or s.category~=rec.category or
  s.contextToken~=rec.contextToken or s.planRevision~=rec.planRevision then
   -- A deliberate new destination supersedes the old untrusted checkpoint;
   -- it must not be able to hijack the user later via manual resume.
   if s and (s.category=="MANUAL" or s.category~="CURRENT_STEP") then
       self:Clear("SUPERSEDED_BY_FRESH_SELECTION")
       return false,"SUPERSEDED_BY_FRESH_SELECTION"
   end
   self.status="CHECKPOINT_REQUIRES_MATCHING_SOURCE"
   return false,self.status
 end
 -- The owner has *already* admitted a fresh canonical source and recalculated
 -- the route using live client origin and current authorized edges. No saved
 -- leg/index is imported; progressing the new plan requires new observations.
 self.pending=nil
 if rows then rows[key]=nil end
 self.status="RESUMED_FRESH_ROUTE";self.sequence=self.sequence+1
 return true,"FRESH_CANONICAL_ROUTE_REBOUND"
end
-- Automatically resume the user's last explicitly selected navigation on login/reload.
-- A checkpoint is *not* an executable route: source provenance is freshly
-- compared to today's canonical producer and a new route is computed from
-- the current observed character/map. Never restore old legs or completion.
function Service:TryAutoResume()
 if not self.initialized or self.status=='CHARACTER_OR_DB_UNAVAILABLE' then
   self:Initialize()
 end
 local allowed,why=capability("POSITION")
 if not allowed then self.status=why;return false,why end
 local key=identity();local rows=account()
 if not key or not rows then self.status='CHARACTER_OR_DB_UNAVAILABLE';return false,self.status end
 local rec=self.pending or rows[key]
 if not rec then return false,'NO_CHECKPOINT' end
 if not validRecord(rec,key) then
   self:Clear('INVALID_CHECKPOINT_DISCARDED')
   return false,'INVALID_CHECKPOINT_DISCARDED'
 end
 local owner=JLP:GetModule('IntegratedDestinationOwner')
 if not owner or not owner.NavigateTo then return false,'DESTINATION_OWNER_UNAVAILABLE' end
 if owner.active or owner.stopped or owner.paused then
   return false,'ACTIVE_OWNER_OR_USER_OVERRIDE'
 end
 local router=JLP:GetModule('TravelRouter')
 local origin=router and router.GetPlayerOrigin and router:GetPlayerOrigin() or nil
 if not validPoint(origin) or origin.positionEvidence~='C_Map.GetPlayerMapPosition' then
   self.status='WAITING_FOR_PLAYER_POSITION'
   return false,self.status
 end
 local source,ctx
 if rec.category=='MANUAL' then
   source={mapID=rec.destination.mapID,x=rec.destination.x,y=rec.destination.y,
       mapDomain='UI_MAP_ID',evidence='EXPLICIT_USER_ENTERED_COORDINATES'}
   ctx={explicit=true,owner='AUTO_RESTORED_MANUAL_WAYPOINT',characterKey=key}
 else
   -- Old Candidate10 checkpoints contain coordinates only. Do not elevate
   -- them to an admitted canonical NPC/vendor without source identity.
   source=rec.sourceProof
   if type(source)~='table' or type(source.nav)~='table' then
     self.status='LEGACY_CHECKPOINT_NEEDS_ONE_NEW_SELECTION'
     return false,self.status
   end
   ctx={explicit=rec.category~='CURRENT_STEP' or rec.restoreExplicit==true,owner='AUTO_RESTORED_CANONICAL_DESTINATION',
      characterKey=rec.characterKey,planRevision=rec.planRevision,
      contextToken=rec.contextToken}
 end
 local ok,why=owner:CanNavigate(rec.category,source,ctx)
 if not ok then self.status='RESTORE_SOURCE_REJECTED_'..tostring(why);return false,self.status end
 -- Equality with stored point prevents altered metadata from moving a target.
 local point=source.nav or source
 if not samePoint(point,rec.destination) then
   self.status='RESTORE_DESTINATION_MISMATCH';return false,self.status
 end
 local accepted,reason
 if rec.paused==true then
   -- Admit the canonical destination while staying PAUSED. This does not
   -- start a route, update transport progress or display an active arrow.
   ctx.owner='AUTO_RESTORED_PAUSED_DESTINATION'
   ctx.restoreAutomatic=rec.category=='CURRENT_STEP' and rec.restoreExplicit~=true
   ctx.explicit=true -- paused restoration still requires the existing fresh-admission guard
   accepted,reason=owner:RestorePaused(rec.category,source,ctx)
 else
   accepted,reason=owner:NavigateTo(rec.category,source,ctx)
 end
 if accepted then
   self.status=rec.paused and 'PAUSED_RESTORED_AWAITING_USER_RESUME' or
      'AUTO_RESUMED_FROM_LIVE_ORIGIN'
   self.sequence=self.sequence+1
   local tom=JLP:GetModule('IntegratedJuztTom')
   if tom and tom.Refresh then tom:Refresh(true) end
   return true,self.status
 end
 self.status='AUTO_RESUME_FAILED_'..tostring(reason)
 return false,self.status
end
function Service:ResumeManual()
 self:Initialize()
 local allowed,why=capability("CHARACTER")
 if not allowed then return false,why end
 local key=identity();local rows=account();local rec=self.pending or (rows and rows[key])
 if not validRecord(rec,key) then return false,"NO_VALID_CHECKPOINT" end
 if rec.category~="MANUAL" then return false,"FRESH_CANONICAL_SOURCE_REQUIRED" end
 local owner=JLP:GetModule("IntegratedDestinationOwner")
 if not owner then return false,"DESTINATION_OWNER_UNAVAILABLE" end
 local p=rec.destination
 -- This command is an explicit user action. An old manually entered point is
 -- re-entered as manual, never promoted to source-qualified status.
 return owner:NavigateTo("MANUAL",{mapID=p.mapID,x=p.x,y=p.y,mapDomain="UI_MAP_ID",
  evidence="EXPLICIT_USER_ENTERED_COORDINATES"},
  {explicit=true,owner="USER_RESTORED_MANUAL_DESTINATION",characterKey=key})
end
function Service:GetStatus()
 local p=self.pending
 return {contract=self.contract,status=self.status,pending=p~=nil,
    destination=p and {mapID=p.destination.mapID,x=p.destination.x,y=p.destination.y} or nil,
    previousPhase=p and p.phase or nil,
    previousLeg=p and p.index or nil,
    pausedCheckpoint=p and p.paused==true or false,
    sequence=self.sequence,navigationOnly=true,nativeDispatchAllowed=false,
    checkpointAuthority="UNTRUSTED_INTENT_ONLY"}
end
function Service:GetSummary()
 local s=self:GetStatus()
 return "Capability-qualified travel continuity: "..tostring(s.status)..
  "; pending="..tostring(s.pending)..
  "; previous stage="..tostring(s.previousPhase or "none")..
  "; native transport/crafting=DISABLED"..
  (s.pending and "; auto-resume awaits current character, map position and canonical source; old checkpoints may need one Navigate To" or "")
end
JLP:RegisterModule("TravelContinuity70450",Service)
