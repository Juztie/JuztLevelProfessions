local _, JLP = ...
-- JLP-authored schema and data admission policy; no redistributable external tables.
-- This describes source quality, never the authority to execute protected actions.
JLP.data.professionsCatalogueSchema = {
    contract="jlp-professions-catalogue-schema-v2", version=2,
    evidenceStates={CANDIDATE=true,SOURCE_QUALIFIED=true,CONFLICT=true,UNKNOWN=true},
    productionAuthorityStates={NOT_AUTHORIZED=true,PRODUCTION_AUTHORIZED=true},
    identityTypes={RECIPE=true,SPELL=true,ITEM=true,THRESHOLD=true,NPC=true,RESOURCE=true},
    gatherShapes={POINT=true,AREA=true},
    professions={TAILORING=true,ENCHANTING=true,ALCHEMY=true,BLACKSMITHING=true,
        ENGINEERING=true,LEATHERWORKING=true,HERBALISM=true,MINING=true,
        SKINNING=true,FISHING=true,COOKING=true,FIRST_AID=true},
    -- Only reviewer-approved, individually attested, current-build rows may be added.
    -- Older JLP datasets are retained as an unmodified migration/reference layer.
    minimumFieldProvenance={"sourceId","url","sourceBuild","locale","observedAtUTC",
        "inputSHA256","rightsReviewId","reviewer","transformation"},
    requiredRecipeFields={"identity","reagents","output","requiredSkill"},
    nativeDispatchAllowed=false,executionEligible=false,
}
