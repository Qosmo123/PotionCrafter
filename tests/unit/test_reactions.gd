extends "res://tests/unit/unit_test_base.gd"
## Emergent reaction channels: every outcome comes from property vectors.

func _idx(id: StringName) -> int:
	return SubstanceRegistry.index_of_id(id)


func _run(m: MixtureContainer, seconds: float, mixing: float) -> float:
	var heat: float = 0.0
	for _i: int in int(seconds / SimConstants.TICK_SECONDS):
		heat += m.step_reactions(SimConstants.TICK_SECONDS, mixing)
	return heat


func test_vinegar_and_soda_fizz_conserves_mass_and_releases_co2() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 5.0, 293.15)
	m.add_substance(_idx(&"acetic_acid"), 0.5, 293.15)
	m.add_substance(_idx(&"baking_soda"), 0.5, 293.15)
	var mass_before: float = m.get_total_mass_kg()
	var h_before: float = m.enthalpy_joules
	var heat: float = _run(m, 3.0, 1.0)
	check_near(m.get_total_mass_kg(), mass_before, 1e-12, "reaction conserves mass")
	check_near(m.enthalpy_joules - m.clamp_correction_joules, h_before + heat, absf(h_before) * 1e-10, "reaction enthalpy fully booked")
	check(m.moles[_idx(&"carbon_dioxide")] > 0.2, "CO₂ is produced (%.3f mol)" % m.moles[_idx(&"carbon_dioxide")])
	check(m.moles[_idx(&"acetic_acid")] < 0.25, "acid is consumed")
	check(m.reaction_heat_joules < 0.0, "bicarbonate fizz is endothermic (Q=%.0f J)" % m.reaction_heat_joules)
	check(m.temperature_kelvin < 293.15, "and the mixture cools (T=%.2f K)" % m.temperature_kelvin)


func test_reactions_need_both_partners() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"water"), 5.0, 293.15)
	m.add_substance(_idx(&"acetic_acid"), 0.5, 293.15)
	var heat: float = _run(m, 2.0, 1.0)
	check_near(heat, 0.0, 0.0, "acid alone does nothing")
	check_near(m.moles[_idx(&"acetic_acid")], 0.5, 1e-12, "acid untouched")


func test_pva_and_borax_gel_into_slime() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"pva_glue"), 2.0, 293.15)
	var runny: float = m.get_liquid_viscosity_pas()
	m.add_substance(_idx(&"borax_solution"), 3.0, 293.15)
	var slime: float = m.get_liquid_viscosity_pas()
	check(slime > runny * 10.0 and slime > 5.0, "crosslinking turns glue into slime (%.2f -> %.2f Pa·s)" % [runny, slime])


func test_duskberry_indicator_follows_ph() -> void:
	var acidic: MixtureContainer = MixtureContainer.new()
	acidic.add_substance(_idx(&"water"), 3.0, 293.15)
	acidic.add_substance(_idx(&"duskberry_juice"), 0.2, 293.15)
	acidic.add_substance(_idx(&"acetic_acid"), 0.4, 293.15)
	var basic: MixtureContainer = MixtureContainer.new()
	basic.add_substance(_idx(&"water"), 3.0, 293.15)
	basic.add_substance(_idx(&"duskberry_juice"), 0.2, 293.15)
	basic.add_substance(_idx(&"borax_solution"), 0.6, 293.15)
	var ca: Color = acidic.get_contents_color()
	var cb: Color = basic.get_contents_color()
	check(acidic.get_ph() < 5.0 and basic.get_ph() > 9.0, "pH proxy separates acid (%.1f) and base (%.1f)" % [acidic.get_ph(), basic.get_ph()])
	check(ca.r > ca.g, "acid turns duskberry red")
	check(cb.g > cb.r, "base turns duskberry green")


func test_opposite_polarities_flare() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"moonwater"), 1.0, 293.15)
	m.add_substance(_idx(&"emberberry_juice"), 1.0, 293.15)
	var mass_before: float = m.get_total_mass_kg()
	var heat: float = m.step_reactions(SimConstants.TICK_SECONDS, 1.0)
	check(heat > 0.0 and m.arcane_flash > 0.0, "polarity annihilation releases heat and light")
	_run(m, 2.0, 1.0)
	check(m.temperature_kelvin > 300.0, "flare heats the mixture (T=%.1f K)" % m.temperature_kelvin)
	check_near(m.get_total_mass_kg(), mass_before, 1e-12, "flare conserves mass")


func test_soap_with_glycerin_is_a_stable_foamer() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"soap_solution"), 3.0, 293.15)
	m.add_substance(_idx(&"glycerin"), 0.5, 293.15)
	check(m.get_foaming() > 0.4, "soap foams")
	check(m.get_foam_stability() > 0.1, "glycerin stabilises bubbles")
