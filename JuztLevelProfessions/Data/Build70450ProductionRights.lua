local _, JLP = ...
-- Owner-controlled release-review registry. An empty registry is deliberate:
-- client DB2 tables and public NPC references provide NO permission to promote.
-- Future approvals must be individually reviewed, legally usable and bound to
-- the exact 70450 recipe, source hash, field and explicit access restrictions.
JLP.data.build70450ProductionRights = {
    contract="JLP-70450-PRODUCTION-RIGHTS-1", sourceBuild=70450,
    nativeDispatchAllowed=false, executionEligible=false,
    sourceReferences={}, -- sourceId -> {url,sourceBuild,locale,inputSHA256,verified=true,
                        -- redistributionApproved=true,licenseId,rightsScope="CATALOGUE_FIELDS"}
    reviews={}, -- reviewId -> {status="APPROVED",sourceId,sourceBuild,locale,
                -- inputSHA256,reviewer,reviewedAtUTC,redistributionApproved=true,
                -- approvedRecords={["TAILORING:2963"]={identity=true,...}}}
    records={}, -- professionKey:spellID -> explicit reviewed recipe record, never auto-populated
}
