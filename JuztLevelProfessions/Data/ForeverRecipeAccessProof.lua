local _, JLP = ...
-- Verified recipe ITEM identities only. Vendor presence, stock and character
-- learned-state are deliberately UNKNOWN and optional to observe.
JLP.data.foreverRecipeAccessProof={
    contract="forever-recipe-access-item-evidence-v1",sourceBuild=70245,
    rows={
        {professionKey="ALCHEMY",recipeID=17553,recipeName="Superior Mana Potion",
         recipeItemID=13477,requiredSkillToLearn=260,
         itemURL="https://www.wowhead.com/forever/item=13477",
         recipeURL="https://www.wowhead.com/forever/spell=17553",
         evidenceClass="WOWHEAD_FOREVER_RECIPE_ITEM",vendorStock="UNKNOWN",
         trainerAvailability="UNVERIFIED",learnedState="NOT_OBSERVED"},
    },
}
