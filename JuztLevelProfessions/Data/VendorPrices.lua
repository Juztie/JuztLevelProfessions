local _, JLP = ...

-- Gold-vendor base prices in copper. These are static Classic-continuity prices
-- for unlimited tailoring reagents and are kept separate from AH economics.
JLP.data.vendorPrices = {
    schema = 1,
    evidence = "classic-continuity-vendor-price",
    items = {
        [2320]  = { name="Coarse Thread",        price=10 },
        [2321]  = { name="Fine Thread",          price=100 },
        [4291]  = { name="Silken Thread",        price=500 },
        [8343]  = { name="Heavy Silken Thread",  price=2000 },
        [14341] = { name="Rune Thread",          price=5000 },
        [2604]  = { name="Red Dye",              price=50 },
        [6260]  = { name="Blue Dye",             price=50 },
    },
}
