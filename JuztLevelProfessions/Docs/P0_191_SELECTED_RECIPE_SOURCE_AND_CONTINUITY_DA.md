# P0 v0.34.191: Valgte recipes, kilder og fortsættelse

- `RecipeSourcePlanningBridge:ForRecipe(key,recipeID,name,faction)` bruger eksakte DB70450 links og eksisterende Forever NPC/quest/vendorkilder. Den valgte `UniversalCurrentStep` har én source-lead med samme RecipeID.
- `guideSkillRequired` og `merchantFavorCost` bevares nu på navngivne vendorkandidater, så Current Step viser prisen og adgangsniveauet når dokumenteret. Ikke alle kandidater har disse felter.
- Et præcist Horde-questeksempel: Wild Leather Boots, Spell 10566, Pattern 8406, Quest 2858, Jangdor Swiftstrider. Fra Wowhead Forever quest 2858: 2 Nightscape Pants, 2 Nightscape Boots og 2 Wildvine. Navn/mængde er dokumenteret; item-ID og bagbeholdning kan IKKE udledes heraf. Dette er kun vejledning og må ikke tilføjes som reagent i native recipe-schema.
- `CurrentStepTravelBridge` bruger kun eksisterende owner-kvalificerede trainer- og servicewaypoints. Quest- og vendorreferencer uden uafhængigt kanonisk waypoint er referencer og aktiverer IKKE JuztTom.
- Regler: Ingen camp-workstations; ingen klient-evidence som krav for planlægning; ingen buildlock; ingen afsendelse af native crafting eller automatisk questreward.
- Simuleret `/reload` skal genkvalificere current owner-kilden og ruten fra observeret positionskort. SavedVariables er hensigt, ikke bevist nuværende waypoint/route eller craftresultat.
- Udestående: mange af de 2.664 poster mangler specifik navngiven NPC-kilde; ingen ingame-QA før release den 4. november. Deadline for funktionel releaseleverance er 3. november.
