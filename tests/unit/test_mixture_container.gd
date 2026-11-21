extends "res://tests/unit/unit_test_base.gd"
## Conservation, phase-change and mixing-rule tests for MixtureContainer.

var water: int = SubstanceRegistry.index_of_id(&"water")
var ethanol: int = SubstanceRegistry.index_of_id(&"ethanol")
var quicksilver: int = SubstanceRegistry.index_of_id(&"quicksilver")
var honey: int = SubstanceRegistry.index_of_id(&"honey_syrup")
var moonwater: int = SubstanceRegistry.index_of_id(&"moonwater")


func test_registry_loads_starter_substances() -> void:
	check(SubstanceRegistry.count() >= 5, "registry should load >= 5 substances")
	for idx: int in [water, ethanol, quicksilver, honey, moonwater]:
		check(idx >= 0, "starter substance missing from registry")


func test_temperature_round_trip() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(water, 10.0, 300.0)
	check_near(m.temperature_kelvin, 300.0, 1e-6, "added water should report its arrival temperature")


func test_equal_water_mixes_to_mean_temperature() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(water, 5.0, 280.0)
	m.add_substance(water, 5.0, 360.0)
	check_near(m.temperature_kelvin, 320.0, 1e-6, "equal masses of water mix to the mean")


func test_mixing_conserves_enthalpy() -> void:
	var a: MixtureContainer = MixtureContainer.new()
	a.add_substance(water, 4.0, 300.0)
	var b: MixtureContainer = MixtureContainer.new()
	b.add_substance(quicksilver, 2.0, 420.0)
	var h_before: float = a.enthalpy_joules + b.enthalpy_joules
	var mass_before: float = a.get_total_mass_kg() + b.get_total_mass_kg()
	b.transfer_fraction_to(a, 1.0)
	check_near(a.enthalpy_joules + b.enthalpy_joules, h_before, absf(h_before) * 1e-12, "enthalpy conserved")
	check_near(a.get_total_mass_kg() + b.get_total_mass_kg(), mass_before, 1e-12, "mass conserved")
	check(a.temperature_kelvin > 300.0 and a.temperature_kelvin < 420.0, "mixed temperature lies between inputs")


func test_heating_water_plateaus_at_boiling_point() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(water, 1.0, 293.15)
	var mass_kg: float = m.get_total_mass_kg()
	var to_band_start: float = mass_kg * 4184.0 * (373.15 - 0.5 - 293.15)
	m.add_heat(to_band_start + mass_kg * 4184.0 * 0.5 + 0.5 * mass_kg * 2257000.0)
	check(m.temperature_kelvin > 372.6 and m.temperature_kelvin < 373.7, "half-boiled water sits on the boiling plateau")
	var gas_fraction: float = m.get_phase_fraction(water, MixtureContainer.Phase.GAS)
	check(gas_fraction > 0.4 and gas_fraction < 0.6, "roughly half the water is vapour (got %.3f)" % gas_fraction)


func test_liquid_pour_conserves_mass_and_energy() -> void:
	var src: MixtureContainer = MixtureContainer.new()
	src.add_substance(water, 8.0, 330.0)
	src.add_substance(ethanol, 2.0, 330.0)
	var dst: MixtureContainer = MixtureContainer.new()
	var mass_before: float = src.get_total_mass_kg()
	var h_before: float = src.enthalpy_joules
	var half_volume: float = src.get_liquid_volume_m3() * 0.5
	var moved: float = src.transfer_liquid_volume_to(dst, half_volume)
	check(moved > 0.0, "some mass moved")
	check_near(src.get_total_mass_kg() + dst.get_total_mass_kg(), mass_before, 1e-12, "pour conserves mass")
	check_near(src.enthalpy_joules + dst.enthalpy_joules, h_before, absf(h_before) * 1e-12, "pour conserves enthalpy")
	check_near(dst.temperature_kelvin, 330.0, 1e-6, "poured liquid keeps its temperature")
	check_near(dst.get_liquid_volume_m3(), half_volume, half_volume * 1e-9, "requested volume arrives")


func test_spill_reports_lost_mass() -> void:
	var src: MixtureContainer = MixtureContainer.new()
	src.add_substance(honey, 1.0, 293.15)
	var mass_before: float = src.get_total_mass_kg()
	var spilled: float = src.transfer_liquid_volume_to(null, 1.0)
	check_near(src.get_total_mass_kg() + spilled, mass_before, 1e-12, "spilled mass is fully accounted for")


func test_empty_transfer_resets_transfer_enthalpy() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(water, 1.0, 330.0)
	m.transfer_liquid_volume_to(null, 1e-5)
	check(m.last_transfer_enthalpy_joules > 0.0, "first spill carries enthalpy")
	m.transfer_liquid_volume_to(null, 1.0)
	m.transfer_liquid_volume_to(null, 1e-5)
	check_near(m.last_transfer_enthalpy_joules, 0.0, 0.0, "a no-op spill must not report stale enthalpy")


func test_venting_vapour_cools_the_liquid() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(water, 1.0, 373.15)
	var t_before: float = m.temperature_kelvin
	var mass_before: float = m.get_total_mass_kg()
	var h_before: float = m.enthalpy_joules
	var vented: float = m.vent_gas(1.0)
	check(vented > 0.0, "vapour escaped")
	check(m.temperature_kelvin < t_before, "evaporative cooling lowers temperature")
	check_near(m.get_total_mass_kg() + vented, mass_before, 1e-12, "vented mass accounted for")
	check_near(m.enthalpy_joules + m.last_transfer_enthalpy_joules, h_before, absf(h_before) * 1e-12, "vented enthalpy accounted for")


func test_thermal_relaxation_never_overshoots_ambient() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(water, 2.0, 360.0)
	var previous: float = m.temperature_kelvin
	var monotonic: bool = true
	for _i: int in 20000:
		m.step_thermal(SimConstants.TICK_SECONDS, SimConstants.AMBIENT_TEMP_KELVIN, 5.0)
		if m.temperature_kelvin > previous + 1e-9 or m.temperature_kelvin < SimConstants.AMBIENT_TEMP_KELVIN - 1e-9:
			monotonic = false
		previous = m.temperature_kelvin
	check(monotonic, "cooling is monotonic and never undershoots ambient")
	check_near(m.temperature_kelvin, SimConstants.AMBIENT_TEMP_KELVIN, 0.5, "settles at ambient")


func test_extreme_heat_is_clamped_and_finite() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(quicksilver, 0.1, 293.15)
	m.add_heat(1e15)
	check(not is_nan(m.temperature_kelvin) and not is_inf(m.temperature_kelvin), "temperature stays finite")
	check(m.temperature_kelvin <= SimConstants.MAX_TEMP_KELVIN, "temperature clamped to max")
	m.add_heat(-1e18)
	check(m.temperature_kelvin >= SimConstants.MIN_TEMP_KELVIN, "temperature clamped to min")
	check_near(SimConstants.sanitize_temp_kelvin(NAN), SimConstants.AMBIENT_TEMP_KELVIN, 0.0, "NaN sanitised to ambient")


func test_heat_is_ignored_when_empty() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	check_near(m.add_heat(5000.0), 0.0, 0.0, "empty container accepts no heat")
	check_near(m.enthalpy_joules, 0.0, 0.0, "empty container stores no enthalpy")


func test_viscosity_log_mixing() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	# Equal liquid volumes: 100 mL each.
	m.add_substance(water, 0.0998 / 0.018015, 293.15)
	m.add_substance(honey, 0.142 / 0.18016, 293.15)
	var expected: float = sqrt(0.001 * 10.0)
	check_near(m.get_liquid_viscosity_pas(), expected, expected * 1e-3, "equal-volume log mix is the geometric mean")


func test_gravity_coupling_is_mass_weighted() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(moonwater, 1.0, 293.15)
	check_near(m.get_gravity_coupling(), -0.6, 1e-9, "pure moonwater coupling")
	m.add_substance(water, 1.0, 293.15)
	check_near(m.get_gravity_coupling(), 0.2, 1e-9, "equal-mass blend averages coupling")
