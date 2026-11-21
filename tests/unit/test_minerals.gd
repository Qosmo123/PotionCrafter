extends "res://tests/unit/unit_test_base.gd"
## Mineral catalogue integrity and the kid-friendly recipes being reachable.


func _idx(id: StringName) -> int:
	return SubstanceRegistry.index_of_id(id)


func _recipe(id: StringName) -> RecipeData:
	for r: RecipeData in RecipeBook.load_all():
		if r.recipe_id == id:
			return r
	return null


func _matches(id: StringName, m: MixtureContainer, foam: float = 0.0) -> bool:
	var traits: Dictionary = RecipeBook.measure_mixture(m, foam, false)
	traits["layers"] = 1.0
	return RecipeBook.matches(_recipe(id), traits)


func _react(m: MixtureContainer, seconds: float) -> void:
	for _i: int in int(seconds / SimConstants.TICK_SECONDS):
		m.step_reactions(SimConstants.TICK_SECONDS, 1.0)


func test_catalogue_is_complete_and_consistent() -> void:
	var all: Dictionary = Rock3D.registry()
	check(all.size() >= 36, "36+ minerals load (got %d)" % all.size())
	for id: String in all:
		var m: MineralData = all[id]
		check(m.fun_fact.length() > 20, "%s has a fun fact" % id)
		check(m.crush_products.size() == m.crush_fractions.size() and not m.crush_products.is_empty(), "%s crushes into something" % id)
		for p: Resource in m.crush_products:
			check(p is SubstanceData and SubstanceRegistry.index_of(p as SubstanceData) >= 0, "%s crush product is a registered substance" % id)
		check(m.inclusions.size() == m.inclusion_chances.size(), "%s inclusion table is consistent" % id)
		for inc: Resource in m.inclusions:
			check(inc is MineralData, "%s inclusion is a mineral" % id)


func test_harder_rocks_need_more_crushing() -> void:
	var soft: Rock3D = Rock3D.new()
	soft.mineral = Rock3D.get_mineral("halite_rock")
	soft.mass_kg = 0.1
	var hard: Rock3D = Rock3D.new()
	hard.mineral = Rock3D.get_mineral("meteorite")
	hard.mass_kg = 0.1
	var crusher: RockCrusher3D = RockCrusher3D.new()
	check(crusher.required_work_joules(hard) > crusher.required_work_joules(soft) * 3.0, "meteorite takes far more cranking than rock salt")
	crusher.free()
	soft.free()
	hard.free()


func test_polish_and_cut_raise_value() -> void:
	var gem: Rock3D = Rock3D.new()
	gem.mineral = Rock3D.get_mineral("ruby")
	gem.mass_kg = gem.mineral.typical_mass_kg
	var rough: int = gem.value()
	gem.polish = 1.0
	var polished: int = gem.value()
	gem.cut = RockMeshes.Cut.HEART
	gem.cut_quality = 0.9
	check(polished > rough and gem.value() > polished * 2, "rough %d < polished %d < cut %d" % [rough, polished, gem.value()])
	gem.free()


func test_sifter_grain_classes() -> void:
	check(SandSifter3D.grain_class(SubstanceRegistry.get_substance(_idx(&"quartz_sand_coarse"))) == 0, "coarse stays on top")
	check(SandSifter3D.grain_class(SubstanceRegistry.get_substance(_idx(&"magnetite_sand"))) == 1, "iron sand is medium")
	check(SandSifter3D.grain_class(SubstanceRegistry.get_substance(_idx(&"quartz_sand_fine"))) == 2, "fine falls through")


func test_volcano_rock_fizz_and_green_to_blue() -> void:
	var a: MixtureContainer = MixtureContainer.new()
	a.add_substance(_idx(&"water"), 4.0, 293.15)
	a.add_substance(_idx(&"acetic_acid"), 0.6, 293.15)
	a.add_substance(_idx(&"calcite_powder"), 0.3, 293.15)
	a.step_reactions(SimConstants.TICK_SECONDS, 1.0)
	check(_matches(&"volcano_rock_fizz", a), "fizzrock powder + vinegar fizzes")
	var b: MixtureContainer = MixtureContainer.new()
	b.add_substance(_idx(&"water"), 4.0, 293.15)
	b.add_substance(_idx(&"acetic_acid"), 0.6, 293.15)
	b.add_substance(_idx(&"malachite_powder"), 0.2, 293.15)
	_react(b, 2.0)
	check(_matches(&"green_to_blue", b), "malachite + vinegar turns blue and fizzes")


func test_stinky_fools_gold() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 4.0, 293.15)
	m.add_substance(_idx(&"acetic_acid"), 0.6, 293.15)
	m.add_substance(_idx(&"pyrite_dust"), 0.3, 293.15)
	_react(m, 1.0)
	check(m.get_odor() > 0.45, "pyrite + vinegar stinks (odor %.2f)" % m.get_odor())
	check(_matches(&"stinky_fools_gold", m), "Stinky Fool's Gold recognised")


func test_dragon_sneeze_heats_itself() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 8.0, 293.15)
	m.add_substance(_idx(&"firepepper_powder"), 0.15, 293.15)
	_react(m, 20.0)
	check(m.temperature_kelvin - 273.15 > 45.0, "firepepper heats the soup (%.0f °C)" % (m.temperature_kelvin - 273.15))


func test_troll_snot_and_galaxy() -> void:
	var snot: MixtureContainer = MixtureContainer.new()
	snot.add_substance(_idx(&"bog_gum"), 2.0, 293.15)
	snot.add_substance(_idx(&"borax_solution"), 3.0, 293.15)
	check(_matches(&"troll_snot", snot), "troll snot slime gels")
	var galaxy: MixtureContainer = MixtureContainer.new()
	galaxy.add_substance(_idx(&"moonwater"), 6.0, 293.15)
	galaxy.add_substance(_idx(&"stardust"), 0.2, 293.15)
	check(_matches(&"galaxy_bottle", galaxy), "stardust in moonwater makes a galaxy")
