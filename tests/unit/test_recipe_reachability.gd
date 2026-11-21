extends "res://tests/unit/unit_test_base.gd"
## Every recipe whose conditions can be produced by simple mixing must be
## reachable by mixing its key ingredients (plus borax for gels, vinegar for
## fizz, heat for hot recipes). Recipes needing the bench (foam, layers, fire,
## stirring, magnets, flares) are covered by smoke tests instead.

const BENCH_TRAITS: PackedStringArray = ["foam_m", "foam_overflow", "layers", "burning", "flash", "swirl", "magnetic", "viscosity_pas",
	"precipitate_ml", "emulsion", "boiling", "flame_r", "flame_g", "flame_b", "toxic", "transmuting", "foaming", "foam_stability"]


func _idx(id: String) -> int:
	return SubstanceRegistry.index_of_id(StringName(id))


func test_mixable_recipes_are_reachable() -> void:
	var unreachable: PackedStringArray = PackedStringArray()
	var tried: int = 0
	for r: RecipeData in RecipeBook.load_all():
		var bench_only: bool = false
		var ingredients: PackedStringArray = PackedStringArray()
		var t_min: float = -1000.0
		var t_max: float = 1000.0
		var wants_gel: bool = false
		var wants_gas: bool = false
		var wants_acid: bool = false
		var wants_base: bool = false
		var wants_cold: bool = false
		for i: int in r.condition_traits.size():
			var trait_name: String = r.condition_traits[i]
			if trait_name in BENCH_TRAITS:
				bench_only = true
			elif trait_name.begins_with("fraction:"):
				ingredients.append(trait_name.substr(9))
			elif trait_name == "temperature_c":
				t_min = r.condition_min[i]
				t_max = r.condition_max[i]
			elif trait_name == "gel":
				wants_gel = true
			elif trait_name == "gas_rate":
				wants_gas = true
			elif trait_name == "ph":
				wants_acid = r.condition_max[i] < 7.0
				wants_base = r.condition_min[i] > 7.0
		# Dry ice (cold solid CO₂) and exact titration need the bench, not a mixing test.
		if bench_only or ingredients.is_empty() or r.category == RecipeData.Category.SECRET or "carbon_dioxide" in ingredients or r.recipe_id == &"neutral_brine":
			continue
		if t_max < 15.0:
			wants_cold = true
		tried += 1
		var start_k: float = 293.15
		if t_min > 20.0:
			start_k = t_min + 285.0
		var m: MixtureContainer = MixtureContainer.new()
		# Recipe-like proportions: the key ingredients are the bulk of the potion.
		if not wants_gel:
			m.add_substance(_idx("water"), 1.0, start_k)
		for id: String in ingredients:
			if _idx(id) >= 0 and id != "water":
				m.add_substance(_idx(id), 2.0, start_k)
		if wants_gel:
			m.add_substance(_idx("borax_solution"), 3.0, start_k)
		if wants_acid or wants_gas:
			m.add_substance(_idx("acetic_acid"), 1.0, start_k)
		if wants_base:
			m.add_substance(_idx("caustic_lye"), 1.0, start_k)
		var ok: bool = false
		for _step: int in 240:
			m.step_reactions(SimConstants.TICK_SECONDS, 1.0)
			if wants_cold and m.temperature_kelvin > 270.0 and not ok:
				m.add_heat(-m.get_heat_capacity_j_k() * 0.5)
			if RecipeBook.matches(r, RecipeBook.measure_mixture(m, 0.0, false)):
				ok = true
				break
		if not ok:
			unreachable.append(String(r.recipe_id))
	check(tried >= 30, "tested a good share of mixable recipes (%d)" % tried)
	check(unreachable.is_empty(), "unreachable by mixing: %s" % ", ".join(unreachable))
