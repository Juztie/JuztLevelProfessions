local _, JLP = ...
-- Explicit identity-to-original GatherLite icon filenames. Never guess new Forever resources.
local Icons={contract="gathering-resource-icons-v1",nativeDispatchAllowed=false}
local FILES={
    ["HERBALISM:ARTHAS_TEARS"]="herb\\arthas_tears.tga",
    ["HERBALISM:BLACK_LOTUS"]="herb\\black_lotus.tga",
    ["HERBALISM:BLINDWEED"]="herb\\blindweed.tga",
    ["HERBALISM:BRIARTHORN"]="herb\\briarthorn.tga",
    ["HERBALISM:BRUISEWEED"]="herb\\bruiseweed.tga",
    ["HERBALISM:DREAMFOIL"]="herb\\dreamfoil.tga",
    ["HERBALISM:EARTHROOT"]="herb\\earthroot.tga",
    ["HERBALISM:FADELEAF"]="herb\\fadeleaf.tga",
    ["HERBALISM:FIREBLOOM"]="herb\\firebloom.tga",
    ["HERBALISM:GHOST_MUSHROOM"]="herb\\ghost_mushroom.tga",
    ["HERBALISM:GOLDEN_SANSAM"]="herb\\golden_sansam.tga",
    ["HERBALISM:GOLDTHORN"]="herb\\goldthorn.tga",
    ["HERBALISM:GRAVE_MOSS"]="herb\\grave_moss.tga",
    ["HERBALISM:GROMSBLOOD"]="herb\\gromsblood.tga",
    ["HERBALISM:ICECAP"]="herb\\icecap.tga",
    ["HERBALISM:KHADGARS_WHISKER"]="herb\\khadgars_whisker.tga",
    ["HERBALISM:KINGSBLOOD"]="herb\\kingsblood.tga",
    ["HERBALISM:LIFEROOT"]="herb\\liferoot.tga",
    ["HERBALISM:MAGEROYAL"]="herb\\mageroyal.tga",
    ["HERBALISM:MOUNTAIN_SILVERSAGE"]="herb\\mountain_silversage.tga",
    ["HERBALISM:PEACEBLOOM"]="herb\\peacebloom.tga",
    ["HERBALISM:PLAGUEBLOOM"]="herb\\plaguebloom.tga",
    ["HERBALISM:PURPLE_LOTUS"]="herb\\purple_lotus.tga",
    ["HERBALISM:SILVERLEAF"]="herb\\silverleaf.tga",
    ["HERBALISM:STRANGLEKELP"]="herb\\stranglekelp.tga",
    ["HERBALISM:SUNGRASS"]="herb\\sungrass.tga",
    ["HERBALISM:WILD_STEELBLOOM"]="herb\\wild_steelbloom.tga",
    ["HERBALISM:WINTERSBITE"]="herb\\wintersbite.tga",
    ["MINING:COPPER_VEIN"]="ore\\copper.tga",
    ["MINING:DARK_IRON_DEPOSIT"]="ore\\darkiron.tga",
    ["MINING:GOLD_VEIN"]="ore\\gold.tga",
    ["MINING:IRON_DEPOSIT"]="ore\\iron.tga",
    ["MINING:MITHRIL_DEPOSIT"]="ore\\mithril.tga",
    ["MINING:RICH_THORIUM_VEIN"]="ore\\rich_thorium.tga",
    ["MINING:SILVER_VEIN"]="ore\\silver.tga",
    ["MINING:SMALL_THORIUM_VEIN"]="ore\\thorium.tga",
    ["MINING:TIN_VEIN"]="ore\\tin.tga",
    ["MINING:TRUESILVER_DEPOSIT"]="ore\\truesilver.tga",
}
function Icons:Resolve(professionKey,resourceKey)
    local fragment=FILES[tostring(professionKey)..":"..tostring(resourceKey)]
    if fragment then
        return "Interface\\AddOns\\JuztLevelProfessions\\Assets\\gathering\\"..fragment,"RESOURCE_ORIGINAL"
    end
    local fallback=JLP.UIIconResolver and JLP.UIIconResolver:GetProfession(professionKey)
    return fallback or "Interface\\Icons\\INV_Misc_QuestionMark","PROFESSION_FALLBACK"
end
JLP:RegisterModule("GatheringResourceIcons",Icons)
