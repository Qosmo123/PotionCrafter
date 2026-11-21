extends "res://tests/unit/unit_test_base.gd"
## Recipes are recognised from emergent results, never used to drive reactions.

func _recipe(id: StringName) -> RecipeData:
	for r: RecipeData in RecipeBook.load_all():
		if r.recipe_id == id:
			return r
	return null


func _idx(id: StringName) -> int:
	return SubstanceRegistry.index_of_id(id)


func test_all_recipes_load_with_valid_signatures() -> void:
	var all: Array[RecipeData] = RecipeBook.load_all()
	check(all.size() >= 16, "16+ recipes load (got %d)" % all.size())
	var secrets: int = 0
	for r: RecipeData in all:
		check(r.condition_traits.size() > 0 and r.condition_traits.size() == r.condition_min.size() and r.condition_min.size() == r.condition_max.size(), "%s has a consistent signature" % r.recipe_id)
		if r.category == RecipeData.Category.SECRET:
			secrets += 1
			check(r.riddle != "", "%s secret has a riddle" % r.recipe_id)
	check(secrets >= 5, "at least five secret recipes")


func test_fizz_is_recognised_while_reacting() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 5.0, 293.15)
	m.add_substance(_idx(&"acetic_acid"), 0.6, 293.15)
	m.add_substance(_idx(&"baking_soda"), 0.6, 293.15)
	m.step_reactions(SimConstants.TICK_SECONDS, 1.0)
	check(RecipeBook.matches(_recipe(&"volcano_fizz"), RecipeBook.measure_mixture(m, 0.0, false)), "fizzing mixture matches Volcanic Effervescence")


func test_slime_is_recognised() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"pva_glue"), 2.0, 293.15)
	m.add_substance(_idx(&"borax_solution"), 3.0, 293.15)
	check(RecipeBook.matches(_recipe(&"borax_slime"), RecipeBook.measure_mixture(m, 0.0, false)), "glue + borax matches Borax Slime")


func test_plain_water_matches_nothing() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 5.0, 293.15)
	var traits: Dictionary = RecipeBook.measure_mixture(m, 0.0, false)
	for r: RecipeData in RecipeBook.load_all():
		check(not RecipeBook.matches(r, traits), "plain water should not match %s" % r.recipe_id)


func test_secret_levitating_bubbles() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"moonwater"), 6.0, 293.15)
	m.add_substance(_idx(&"soap_solution"), 4.0, 293.15)
	m.add_substance(_idx(&"glycerin"), 0.4, 293.15)
	check(RecipeBook.matches(_recipe(&"philosophers_bubble"), RecipeBook.measure_mixture(m, 0.0, false)), "soap + glycerin + moonwater unlocks Philosopher's Bubble")
