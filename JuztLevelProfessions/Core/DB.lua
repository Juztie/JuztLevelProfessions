local _, JLP = ...
local DB = { CURRENT_SCHEMA = JLP.Constants.DB_SCHEMA }

local defaults = {
    meta = {
        schemaVersion = JLP.Constants.DB_SCHEMA,
        installVersion = JLP.version,
        lastVersion = JLP.version,
    },
    profile = {
        enabled = true,
        showWindow = true,
        scale = 1.0,
        opacity = 1.0,
        clickThrough = false,
        strategy = JLP.Constants.STRATEGIES.ECONOMICAL,
        shoppingScope = JLP.Constants.SHOPPING_SCOPES.CURRENT,
        guideMode = "dual",
        stepTrackerEnabledByProfession = {},
        objectiveTrackerPlacement = "AUTO",
        researchRouteAuthority = {
            enabled = false, -- historical explicit toggle retained for compatibility
            autoPlannerPromotion = true, -- read-only Planner route only, never native dispatch
            mode = "normal",
        },
        productionTailoringAuthority = {
            enabled = false,
        },
        productionEnchantingAuthority = {
            enabled = false,
        },
        productionTailoringNativeExecutionAuthority = {
            enabled = false,
        },
        productionEnchantingNativeExecutionAuthority = {
            enabled = false,
        },
        productionEnchantingCraftAllAuthority = {
            enabled = false,
        },
        productionTailoringCraftAllAuthority = {
            enabled = false,
        },
        productionTailoringAutoRouteAuthority = {
            enabled = false,
            safetyCraftCap = 250,
        },
        researchExecutionAuthority = {
            enabled = false,
        },
        researchNativeExecutionAuthority = {
            enabled = false,
        },
        researchCraftAllAuthority = {
            enabled = false,
        },
        researchSequentialExecutionAuthority = {
            enabled = false,
            maxCrafts = 3,
        },
        researchAutoRouteAuthority = {
            enabled = false,
            safetyCraftCap = 250,
        },
        minimap = {
            hidden = false,
        },
    },
    character = {
        selectedProfession = "TAILORING",
    },
    account = {
        enchantingRodCompetence = {schema=1,characters={}},
        gathering = {
            schema = 1,
            characters = {},
        },
        auction = {
            snapshot = nil,
        },
        inventory = {
            characters = {},
        },
        characterIdentity = {
            schema = 1,
            aliases = {},
            records = {},
        },
        knowledge = {
            items = {},
            itemNames = {},
            characters = {},
        },
        routeProgress = {
            characters = {},
        },
        progressTracking = {
            characters = {},
        },
        executionProgress = {
            characters = {},
        },
        routeCheckpoint = {
            characters = {},
        },
        transactionRecovery = {
            characters = {},
        },
        transactionLedger = {
            characters = {},
        },
        recipeTelemetry = {
            characters = {},
        },
        recipeOutputEvidence = {
            schema = 1,
            characters = {},
        },
        recipeAccessEvidence = {
            schema = 1,
            builds = {},
        },
        materialAcquisitionEvidence = {
            schema = 1,
            builds = {},
        },
    },
}

local function deepCopy(src, seen)
    if type(src) ~= "table" then return src end
    seen = seen or {}
    if seen[src] then return seen[src] end
    local dst = {}
    seen[src] = dst
    for k, v in pairs(src) do dst[k] = deepCopy(v, seen) end
    return dst
end

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = deepCopy(v)
        elseif type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = deepCopy(v) else applyDefaults(dst[k], v) end
        end
    end
end

-- One existing SavedVariable slot serves ordinary checkpoints and quarantines.
-- A quarantine is immutable until the player explicitly recovers/exports it.
-- Older releases used backupReason but no backupKind; recognize those as well.
local function isQuarantined(backup)
    if type(backup) ~= "table" then return false end
    local meta = type(backup.meta) == "table" and backup.meta or nil
    local marker = type(backup.__jlpBackup) == "table" and backup.__jlpBackup or nil
    local reason = meta and meta.backupReason
    return (marker and marker.kind == "quarantine") or
        (meta and meta.backupKind == "quarantine") or
        reason == "future-schema-isolated" or
        (type(reason) == "string" and reason:sub(1,17) == "migration-failed-") or false
end

local function annotateBackup(backup, reason, sourceSchema, quarantine)
    if type(backup) ~= "table" then return end
    -- Sidecar within the *existing* backup SavedVariable preserves malformed
    -- source.meta verbatim; source tables are never stamped in place.
    local marker = {contract="jlp-db-backup-retention-v1",
        kind=quarantine and "quarantine" or "checkpoint",
        sourceSchema=sourceSchema, reason=reason or "snapshot",addonVersion=JLP.version}
    if type(time) == "function" then
        local ok, stamp = pcall(time)
        if ok then marker.at=stamp end
    end
    backup.__jlpBackup=marker
    if type(backup.meta) == "table" then
        backup.meta.backupReason=marker.reason
        backup.meta.backupVersion=JLP.version
        backup.meta.backupKind=marker.kind
        if marker.at then backup.meta.backupAt=marker.at end
    end
end

function DB:GetBackupStatus()
    local backup=JuztLevelProfessionsDBBackup
    if type(backup)~="table" then return {kind="none",protected=false} end
    local meta=type(backup.meta)=="table" and backup.meta or nil
    local marker=type(backup.__jlpBackup)=="table" and backup.__jlpBackup or nil
    local quarantine=isQuarantined(backup)
    local active=type(JuztLevelProfessionsDB)=="table" and JuztLevelProfessionsDB or nil
    local isolation=active and type(active.meta)=="table" and active.meta.lastDBIsolation or nil
    local second=quarantine and type(isolation)=="table" and
        isolation.additionalSourceNotPreserved==true
    local latestPreserved=nil
    if type(isolation)=="table" then latestPreserved=isolation.sourcePreservedInBackup==true end
    return {kind=quarantine and "quarantine" or "checkpoint",protected=quarantine,
        reason=(marker and marker.reason) or (meta and meta.backupReason) or "legacy-checkpoint",
        sourceSchema=(marker and marker.sourceSchema) or (meta and meta.schemaVersion),
        previousOriginalPreserved=quarantine,
        latestIncompatibleSourcePreserved=latestPreserved,
        additionalSourceNotPreserved=second and true or false,
        recoveryCode=second and "SECOND_SOURCE_NOT_BACKED_UP" or
            (quarantine and "QUARANTINE_REQUIRES_MANUAL_RECOVERY" or "NONE"),
        recoveryAdvice=second and
            "Existing quarantine retained. A later incompatible active source was NOT copied; recover it only from an external backup made before client write-out." or
            (quarantine and "Existing original remains in the single backup slot; export and review manually before any restore." or nil)}
end

function DB:CreateBackup(source, reason)
    if type(source) ~= "table" then return false, "source is not a table" end
    if isQuarantined(JuztLevelProfessionsDBBackup) then
        return false,"QUARANTINE_PROTECTED"
    end
    local snapshot=deepCopy(source)
    local meta=type(source.meta)=="table" and source.meta or nil
    local sourceSchema=meta and meta.schemaVersion or 1
    local quarantine=reason=="future-schema-isolated" or
        (type(reason)=="string" and reason:sub(1,17)=="migration-failed-")
    annotateBackup(snapshot,reason,sourceSchema,quarantine)
    JuztLevelProfessionsDBBackup=snapshot
    return true
end

-- Promote the *unmodified* pre-migration checkpoint, never a working table
-- whose migration may have mutated some fields before failing.
function DB:ProtectBackup(reason,sourceSchema)
    local backup=JuztLevelProfessionsDBBackup
    if isQuarantined(backup) then return false,"QUARANTINE_PROTECTED" end
    if type(backup)~="table" then return false,"BACKUP_NOT_AVAILABLE" end
    annotateBackup(backup,reason,sourceSchema,true)
    return true
end

local migrations = {}

local function ensureMeta(db)
    db.meta = type(db.meta) == "table" and db.meta or {}
    db.meta.migrationHistory = type(db.meta.migrationHistory) == "table" and db.meta.migrationHistory or {}
    return db.meta
end

local function stampMigration(db, fromSchema, toSchema, name)
    local meta = ensureMeta(db)
    local row = { fromSchema=fromSchema, toSchema=toSchema, name=name, addonVersion=JLP.version }
    if type(time) == "function" then
        local ok, stamp = pcall(time)
        if ok then row.at = stamp end
    end
    meta.migrationHistory[#meta.migrationHistory + 1] = row
    while #meta.migrationHistory > 16 do table.remove(meta.migrationHistory, 1) end
end

migrations[1] = function(db)
    -- Historical schemas 1->2 were additive. Keep an explicit, idempotent step so
    -- old SavedVariables now traverse a monotone migration chain.
    db.account = type(db.account) == "table" and db.account or {}
    return true, "legacy-additive-1-to-2"
end

migrations[2] = function(db)
    -- Historical schemas 2->3 were also additive/default-driven. This explicit
    -- step records provenance without guessing at fields that may not have existed.
    db.account = type(db.account) == "table" and db.account or {}
    return true, "legacy-additive-2-to-3"
end

migrations[3] = function(db)
    db.account = type(db.account) == "table" and db.account or {}
    db.account.characterIdentity = type(db.account.characterIdentity) == "table" and db.account.characterIdentity or {}
    local identity = db.account.characterIdentity
    identity.schema = 1
    identity.aliases = type(identity.aliases) == "table" and identity.aliases or {}
    identity.records = type(identity.records) == "table" and identity.records or {}
    return true, "stable-character-identity-foundation"
end

function DB:RunMigrations(db, sourceSchema)
    if type(db) ~= "table" then return false, "db-not-table" end
    local schema = math.floor(tonumber(sourceSchema) or 1)
    if schema > self.CURRENT_SCHEMA then return false, "future-schema" end
    while schema < self.CURRENT_SCHEMA do
        local migrate = migrations[schema]
        if type(migrate) ~= "function" then return false, "missing-migration-" .. tostring(schema) end
        local ok, name = migrate(db)
        if not ok then return false, name or ("migration-failed-" .. tostring(schema)) end
        stampMigration(db, schema, schema + 1, name or ("migrate-" .. tostring(schema) .. "-to-" .. tostring(schema + 1)))
        schema = schema + 1
        ensureMeta(db).schemaVersion = schema
    end
    return true, schema
end

function DB:Initialize()
    local db = type(JuztLevelProfessionsDB) == "table" and JuztLevelProfessionsDB or {}
    local oldVersion = type(db.meta)=="table" and db.meta.lastVersion or nil
    local sourceSchema = type(db.meta)=="table" and tonumber(db.meta.schemaVersion) or 1
    local preMigrationSaved=false
    if next(db) ~= nil then
        preMigrationSaved=select(1,self:CreateBackup(db,"pre-migration-schema-"..tostring(sourceSchema)))
    end

    -- A thrown migration is treated as a failed migration, not an excuse to
    -- write a partially mutated working copy over the original checkpoint.
    local callOK, ok, migrationState = pcall(self.RunMigrations,self,db,sourceSchema)
    if not callOK then migrationState="migration-exception";ok=false end
    if not ok then
        local isolationReason=migrationState=="future-schema" and
            "future-schema-isolated" or ("migration-failed-"..tostring(migrationState))
        local protected,protectReason=false,nil
        if preMigrationSaved then
            protected,protectReason=self:ProtectBackup(isolationReason,sourceSchema)
        elseif not isQuarantined(JuztLevelProfessionsDBBackup) and next(db)~=nil then
            -- Defensive fallback for callers with a missing checkpoint.  Never
            -- replace an older quarantine, even if a second isolation occurs.
            protected,protectReason=self:CreateBackup(db,isolationReason)
        else
            protectReason="QUARANTINE_PROTECTED"
        end
        db = {}
        -- The active fallback is safe defaults. Never automatically restore
        -- or migrate the quarantined original; manual export/review is required.
        applyDefaults(db, defaults)
        local originalSaved=protected==true
        local olderQuarantine=isQuarantined(JuztLevelProfessionsDBBackup) and not originalSaved
        db.meta.lastDBIsolation={reason=isolationReason,sourceSchema=sourceSchema,
            backupProtected=originalSaved or olderQuarantine,
            sourcePreservedInBackup=originalSaved,
            previousQuarantinePreserved=olderQuarantine,
            additionalSourceNotPreserved=olderQuarantine,
            recoveryCode=olderQuarantine and "SECOND_SOURCE_NOT_BACKED_UP" or
                (originalSaved and "SOURCE_QUARANTINED" or "SOURCE_NOT_BACKED_UP"),
            backupStatus=protectReason or (protected and "QUARANTINED" or "NO_BACKUP")}
        sourceSchema=self.CURRENT_SCHEMA
    else
        applyDefaults(db,defaults)
    end

    db.meta.schemaVersion=self.CURRENT_SCHEMA
    db.meta.installVersion=db.meta.installVersion or oldVersion or JLP.version
    db.meta.lastVersion=JLP.version
    JuztLevelProfessionsDB=db
    JLP.DB=db

    local identity = JLP:GetModule("CharacterIdentity")
    if identity and identity.ReconcileAccount then
        local receipt = identity:ReconcileAccount(db)
        db.meta.lastCharacterIdentityReconciliation = receipt
    end
    return db
end

function DB:Get()
    return JLP.DB or JuztLevelProfessionsDB
end

function DB:GetAuctionSnapshot()
    local db = self:Get()
    return db and db.account and db.account.auction and db.account.auction.snapshot
end

function DB:SetAuctionSnapshot(snapshot)
    local db = self:Get()
    if not db then return false end
    db.account = db.account or {}
    db.account.auction = db.account.auction or {}
    db.account.auction.snapshot = snapshot
    return true
end

JLP:RegisterModule("DB", DB)
