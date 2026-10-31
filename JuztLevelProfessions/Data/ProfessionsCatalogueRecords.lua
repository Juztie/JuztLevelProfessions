local _, JLP = ...
-- Independently qualified JLP records only. No foreign bulk ingestion.
-- M11 ADMISSION POLICY: Rows are never approved merely because evidenceState
-- says SOURCE_QUALIFIED. Profession/spell identity, exact build, item/yield,
-- reagent slots, per-field provenance, source hash, reviewed rights and actor
-- (if present) MUST all pass ProfessionsCatalogueQualification.
-- Existing 70450 teaching-item/source research is NOT live NPC/loot evidence.
-- No new 70374 production records satisfy the complete reviewed evidence
-- contract. An empty array is deliberate; never generate speculative rows.
-- Qualification grants ONLY a read-only data receipt, never native dispatch.
JLP.data.professionsCatalogueRecords = {
    contract="jlp-professions-catalogue-records-v2", schemaVersion=2,
    rows={}, nativeDispatchAllowed=false, executionEligible=false,
}
