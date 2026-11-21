extends "res://tests/unit/unit_test_base.gd"
## Real-chemistry behaviours from the redox, complexation, dissolution,
## crystallisation, shear and flame channels.


func _idx(id: StringName) -> int:
	return SubstanceRegistry.index_of_id(id)


func _run(m: MixtureContainer, seconds: float, ignite: bool = false, mixing: float = 1.0) -> float:
	var total: float = 0.0
	for _i: int in int(seconds / SimConstants.TICK_SECONDS):
		total += m.step_reactions(SimConstants.TICK_SECONDS, mixing, true, ignite)
	return total


func test_iron_plates_out_copper() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 5.0, 293.15)
	m.add_substance(_idx(&"copper_sulfate"), 0.3, 293.15)
	m.add_substance(_idx(&"iron_filings"), 0.3, 293.15)
	var mass_before: float = m.get_total_mass_kg()
	_run(m, 3.0)
	check(m.moles[_idx(&"copper_metal")] > 0.02, "copper metal deposits")
	check(m.moles[_idx(&"iron_sulfate_aq")] > 0.0, "green iron sulfate forms")
	check_near(m.get_total_mass_kg(), mass_before, 1e-12, "redox conserves mass")


func test_ammonia_turns_copper_royal_blue() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 5.0, 293.15)
	m.add_substance(_idx(&"copper_sulfate"), 0.2, 293.15)
	m.add_substance(_idx(&"ammonia_solution"), 1.0, 293.15)
	_run(m, 2.0)
	check(m.moles[_idx(&"copper_ammine_complex")] > 0.02, "tetraamminecopper forms")
	var c: Color = m.get_contents_color()
	check(c.b > c.r * 2.0, "the solution is deep blue")


func test_starch_iodine_goes_blue_black() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 5.0, 293.15)
	m.add_substance(_idx(&"starch"), 0.1, 293.15)
	m.add_substance(_idx(&"iodine_tincture"), 0.05, 293.15)
	_run(m, 1.0)
	check(m.moles[_idx(&"starch_iodine_complex")] > 0.01, "starch-iodine complex forms")


func test_luminol_glows_then_fades() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 5.0, 293.15)
	m.add_substance(_idx(&"luminol"), 0.05, 293.15)
	m.add_substance(_idx(&"hydrogen_peroxide"), 0.3, 293.15)
	m.add_substance(_idx(&"potassium_ferricyanide"), 0.02, 293.15)
	_run(m, 0.5)
	var glow_early: float = m.get_emission_hdr().b
	check(glow_early > 0.02, "luminol glows blue (%.3f)" % glow_early)
	_run(m, 25.0)
	check(m.get_emission_hdr().b < glow_early, "the glow fades as the luminol is used up")


func test_hot_and_cold_packs() -> void:
	var hot: MixtureContainer = MixtureContainer.new()
	hot.add_substance(_idx(&"water"), 5.0, 293.15)
	hot.add_substance(_idx(&"calcium_chloride"), 0.4, 293.15)
	_run(hot, 3.0)
	check(hot.temperature_kelvin > 300.0, "calcium chloride warms the water (%.1f °C)" % (hot.temperature_kelvin - 273.15))
	var cold: MixtureContainer = MixtureContainer.new()
	cold.add_substance(_idx(&"water"), 5.0, 293.15)
	cold.add_substance(_idx(&"ammonium_nitrate"), 0.6, 293.15)
	_run(cold, 3.0)
	check(cold.temperature_kelvin < 285.0, "ammonium nitrate chills the water (%.1f °C)" % (cold.temperature_kelvin - 273.15))


func test_hot_ice_needs_a_seed() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"sodium_acetate_supersat"), 2.0, 293.15)
	_run(m, 2.0)
	check(m.moles[_idx(&"sodium_acetate_crystals")] < 1e-9, "no seed, no crystals")
	m.add_substance(_idx(&"sodium_acetate_crystals"), 0.01, 293.15)
	_run(m, 2.0)
	check(m.moles[_idx(&"sodium_acetate_crystals")] > 1.0, "a seed crystal freezes it into hot ice")
	check(m.temperature_kelvin > 300.0, "and it warms up (%.1f °C)" % (m.temperature_kelvin - 273.15))


func test_oobleck_thickens_when_stirred() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 3.0, 293.15)
	m.add_substance(_idx(&"cornstarch"), 0.8, 293.15)
	m.shear_rate = 0.0
	var calm: float = m.get_liquid_viscosity_pas()
	m.shear_rate = 1.5
	check(m.get_liquid_viscosity_pas() > calm * 10.0, "stirring makes oobleck far thicker")


func test_permanganate_glycerin_ignites() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"glycerin"), 0.3, 293.15)
	m.add_substance(_idx(&"potassium_permanganate"), 0.3, 293.15)
	_run(m, 8.0)
	check(m.reaction_heat_joules > 1000.0, "the redox releases heat")
	check(m.burning or m.temperature_kelvin > 500.0, "it gets hot enough to burn (%.0f K)" % m.temperature_kelvin)


func test_thermite_makes_molten_iron() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"iron_oxide"), 0.2, 293.15)
	m.add_substance(_idx(&"aluminium_powder"), 0.4, 293.15)
	m.add_substance(_idx(&"magnesium_ribbon"), 0.5, 293.15)
	_run(m, 0.2)
	check(m.moles[_idx(&"molten_iron")] < 1e-9, "thermite does nothing until lit")
	_run(m, 3.0, true)
	check(m.moles[_idx(&"molten_iron")] > 0.05, "lit by burning magnesium, thermite pours out iron")
	check(m.temperature_kelvin > 1500.0, "white hot (%.0f K)" % m.temperature_kelvin)


func test_never_mix_bleach() -> void:
	var a: MixtureContainer = MixtureContainer.new()
	a.add_substance(_idx(&"bleach"), 0.5, 293.15)
	a.add_substance(_idx(&"hydrochloric_acid"), 0.5, 293.15)
	a.step_reactions(SimConstants.TICK_SECONDS, 1.0)
	check(a.moles[_idx(&"chlorine_gas")] > 0.0, "bleach + acid releases chlorine")
	var b: MixtureContainer = MixtureContainer.new()
	b.add_substance(_idx(&"bleach"), 0.5, 293.15)
	b.add_substance(_idx(&"ammonia_solution"), 0.5, 293.15)
	b.step_reactions(SimConstants.TICK_SECONDS, 1.0)
	check(b.moles[_idx(&"chloramine_gas")] > 0.0, "bleach + ammonia releases chloramine")
	check(b.hazard_level(&"toxic") > 0.3, "and the mixture is flagged toxic")


func test_strontium_flame_is_red() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"methanol"), 3.0, 293.15)
	m.add_substance(_idx(&"strontium_chloride"), 0.3, 293.15)
	var c: Color = m.get_flame_color()
	check(c.r > 0.8 and c.g < 0.4, "strontium colours the flame red")
