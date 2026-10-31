local _, JLP = ...
-- Forever recipe learning requirements, independently verified by precise
-- SpellID/ItemID. Advisory only, NOT permission to craft/learn/teleport.
-- Build numbers are source dates, NEVER client-runtime gates.
JLP.data.foreverRecipeMinimums192 = {
  contract="JLP-FOREVER-RECIPE-MINIMUMS-192",readOnly=true,
  rows={
    TAILORING={
      [2963]={requiredSkill=1,source="https://www.wowhead.com/forever/spell=2963/bolt-of-linen-cloth"},
      [18401]={requiredSkill=250,source="https://www.wowhead.com/forever/spell=18401/bolt-of-runecloth"},
      [2964]={requiredSkill=75,source="https://www.wowhead.com/forever/spell=2964/bolt-of-woolen-cloth"},
      [18560]={requiredSkill=230,teachingItemID=14526,source="https://foreverdiff.com/recipes/mooncloth-10487/"},
      [22902]={requiredSkill=275,teachingItemID=18487,source="https://www.wowhead.com/forever/item=18487/pattern-mooncloth-robe"},
    },
    ENGINEERING={
      [3924]={requiredSkill=50,source="https://www.wowhead.com/forever/spell=3924/copper-tube"},
      [3973]={requiredSkill=90,source="https://www.wowhead.com/forever/spell=3973/silver-contact"},
    },
    BLACKSMITHING={
      [2665]={requiredSkill=65,source="https://www.wowhead.com/forever/spell=2665/coarse-sharpening-stone"},
    },
    ALCHEMY={
      [11479]={requiredSkill=225,source="https://www.wowhead.com/forever/spell=11479/transmute-iron-to-gold"},
    },
  },
}
