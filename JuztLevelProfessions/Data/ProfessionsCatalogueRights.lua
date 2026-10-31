local _, JLP = ...
-- Only completed, documented redistribution decisions belong here.
-- Sources cited for research are NOT automatically authorized to be shipped.
JLP.data.professionsCatalogueRights = {
    contract="jlp-catalogue-rights-v1",
    -- No approval is supplied by this release. A future review MUST bind the
    -- exact source hash/build/locale, reviewer, explicit allowed fields, and
    -- the exact PROFESSION:SpellID; research references cannot grant rights.
    reviews={}, -- reviewId -> {status="APPROVED",redistribution=true,sourceId,
                -- sourceBuild,locale,inputSHA256,reviewer,reviewedAtUTC,
                -- approvedRecords={["TAILORING:2963"]={identity=true,...}}}
    sourceReferences={}, -- sourceId -> {url,sourceBuild,locale,inputSHA256,verified=true}
}
