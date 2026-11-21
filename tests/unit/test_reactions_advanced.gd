extends "res://tests/unit/unit_test_base.gd"
## Decomposition, precipitation, layers, combustion, thermochromism, transmutation.

func _idx(id: StringName) -> int:
	return SubstanceRegistry.index_of_id(id)


func _run(m: MixtureContainer, seconds: float, air: bool = true, spark: bool = false) -> float:
	var total: float = 0.0
	for _i: int in int(seconds / SimConstants.TICK_SECONDS):
		total += m.step_reactions(SimConstants.TICK_SECONDS, 0.5, air, spark)
	return total


func test_catalyst_accelerates_peroxide_decomposition() -> void:
	var slow: MixtureContainer = MixtureContainer.new()
	slow.add_substance(_idx(&"hydrogen_peroxide"), 1.0, 293.15)
	slow.add_substance(_idx(&"water"), 4.0, 293.15)
	var fast: MixtureContainer = MixtureContainer.new()
	fast.add_substance(_idx(&"hydrogen_peroxide"), 1.0, 293.15)
	fast.add_substance(_idx(&"water"), 4.0, 293.15)
	fast.add_substance(_idx(&"potassium_iodide"), 0.15, 293.15)
	var mass_before: float = fast.get_total_mass_kg()
	var h_before: float = fast.enthalpy_joules
	_run(slow, 2.0)
	var delta: float = _run(fast, 2.0)
	var left_slow: float = slow.moles[_idx(&"hydrogen_peroxide")]
	var left_fast: float = fast.moles[_idx(&"hydrogen_peroxide")]
	check(left_fast < left_slow * 0.7, "KI speeds decomposition (%.3f vs %.3f mol left)" % [left_fast, left_slow])
	check(fast.moles[_idx(&"oxygen")] > 0.05, "oxygen is released")
	check(fast.reaction_heat_joules > 0.0, "decomposition is exothermic")
	check_near(fast.get_total_mass_kg(), mass_before, 1e-12, "decomposition conserves mass")
	check_near(fast.enthalpy_joules - fast.clamp_correction_joules, h_before + delta, absf(h_before) * 1e-9, "enthalpy fully booked")


func test_silver_and_brine_precipitate() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 4.0, 293.15)
	m.add_substance(_idx(&"silver_nitrate"), 0.5, 293.15)
	m.add_substance(_idx(&"salt_brine"), 0.5, 293.15)
	m.step_reactions(SimConstants.TICK_SECONDS, 0.5)
	check(m.precipitation_rate_mol_s > 0.0, "precipitate forms immediately")
	_run(m, 1.0)
	check(m.get_solid_volume_m3() > 1e-6, "solid silver salt settles out (%.2f mL)" % (m.get_solid_volume_m3() * 1e6))
	var c: Color = m.get_layer_color(-1, true)
	check(c.r > 0.9 and c.g > 0.9, "the precipitate is white")


func test_copper_and_lye_give_blue_precipitate() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 4.0, 293.15)
	m.add_substance(_idx(&"copper_sulfate"), 0.5, 293.15)
	m.add_substance(_idx(&"caustic_lye"), 0.5, 293.15)
	_run(m, 1.0)
	check(m.moles[_idx(&"copper_precipitate")] > 0.05, "Cu(OH)₂ precipitates")
	var c: Color = m.get_layer_color(-1, true)
	check(c.b > c.r, "the precipitate is blue")


func test_oil_water_and_quicksilver_form_three_layers() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 3.0, 293.15)
	m.add_substance(_idx(&"salamander_oil"), 0.15, 293.15)
	m.add_substance(_idx(&"quicksilver"), 0.3, 293.15)
	for g: int in 3:
		check(m.get_group_volume_m3(g) > 1e-6, "group %d present" % g)
	check(m.get_group_density_kg_m3(2) > m.get_group_density_kg_m3(0) and m.get_group_density_kg_m3(0) > m.get_group_density_kg_m3(1), "metal sinks, oil floats")


func test_pure_spirit_lights_from_a_spark_but_watered_spirit_does_not() -> void:
	var pure: MixtureContainer = MixtureContainer.new()
	pure.add_substance(_idx(&"ethanol"), 2.0, 300.0)
	_run(pure, 0.5, true, true)
	check(pure.burning and pure.moles[_idx(&"carbon_dioxide")] + pure.moles[_idx(&"water")] > 0.0, "spirit of wine burns")
	var watered: MixtureContainer = MixtureContainer.new()
	watered.add_substance(_idx(&"ethanol"), 1.0, 300.0)
	watered.add_substance(_idx(&"water"), 8.0, 300.0)
	_run(watered, 0.5, true, true)
	check(not watered.burning, "diluted spirit will not light")
	var sealed: MixtureContainer = MixtureContainer.new()
	sealed.add_substance(_idx(&"ethanol"), 2.0, 300.0)
	_run(sealed, 0.5, false, true)
	check(not sealed.burning, "no air, no fire")


func test_chameleon_ink_follows_temperature() -> void:
	var cold: MixtureContainer = MixtureContainer.new()
	cold.add_substance(_idx(&"chameleon_ink"), 1.0, 278.0)
	var hot: MixtureContainer = MixtureContainer.new()
	hot.add_substance(_idx(&"chameleon_ink"), 1.0, 350.0)
	var cc: Color = cold.get_contents_color()
	var hc: Color = hot.get_contents_color()
	check(cc.b > cc.r, "cold ink is blue")
	check(hc.r > hc.b, "hot ink is crimson")


func test_quicksilver_transmutes_in_hot_thaumic_mixture() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"quicksilver"), 1.0, 360.0)
	m.add_substance(_idx(&"moonwater"), 8.0, 360.0)
	_run(m, 3.0)
	check(m.moles[_idx(&"aurum_potabile")] > 0.01, "aurum potabile forms (%.3f mol)" % m.moles[_idx(&"aurum_potabile")])
	var cool: MixtureContainer = MixtureContainer.new()
	cool.add_substance(_idx(&"quicksilver"), 1.0, 293.15)
	cool.add_substance(_idx(&"moonwater"), 8.0, 293.15)
	_run(cool, 3.0)
	check_near(cool.moles[_idx(&"aurum_potabile")], 0.0, 0.0, "no transmutation when cool")
