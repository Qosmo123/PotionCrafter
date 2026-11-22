extends "res://tests/unit/unit_test_base.gd"
## Grain fineness (MixtureContainer.grain_surface): finely ground solids react
## on more surface, it mixes by solid mass on transfers, and grinding never
## touches mass or energy.


func _idx(id: StringName) -> int:
	return SubstanceRegistry.index_of_id(id)


func _fizz(surface: float) -> float:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"baking_soda"), 0.05, 293.15)
	m.grain_surface = surface
	m.add_substance(_idx(&"water"), 2.0, 293.15)
	m.add_substance(_idx(&"acetic_acid"), 0.05, 293.15)
	var start: float = m.moles[_idx(&"baking_soda")]
	for _i: int in 6:
		m.step_reactions(SimConstants.TICK_SECONDS, 1.0)
	return start - m.moles[_idx(&"baking_soda")]


func test_fine_powder_reacts_faster() -> void:
	var coarse: float = _fizz(1.0)
	var fine: float = _fizz(MixtureContainer.GRAIN_SURFACE_MAX)
	check(coarse > 0.0, "coarse soda reacts with vinegar (%.5f mol in 0.1 s)" % coarse)
	check(fine > coarse * 1.8, "finely ground soda reacts much faster (%.5f vs %.5f mol)" % [fine, coarse])


func test_grinding_is_bounded_and_conserves() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(&"calcite_powder"), 0.3, 293.15)
	var mass: float = m.get_total_mass_kg()
	var h: float = m.enthalpy_joules
	for _i: int in 50:
		m.grind(0.5)
	check(m.grain_surface > MixtureContainer.GRAIN_SURFACE_MAX * 0.95 and m.grain_surface <= MixtureContainer.GRAIN_SURFACE_MAX, "grinding approaches the finest grind (%.2f)" % m.grain_surface)
	check(absf(m.get_total_mass_kg() - mass) < 1e-9 and absf(m.enthalpy_joules - h) < 1e-6, "grinding itself changes neither mass nor energy")
	m.clear()
	check(m.grain_surface == 1.0, "a cleared vessel starts coarse again")


func test_fineness_mixes_by_solid_mass() -> void:
	var fine: MixtureContainer = MixtureContainer.new()
	fine.add_substance(_idx(&"calcite_powder"), 0.2, 293.15)
	fine.grain_surface = MixtureContainer.GRAIN_SURFACE_MAX
	var coarse: MixtureContainer = MixtureContainer.new()
	coarse.add_substance(_idx(&"calcite_powder"), 0.2, 293.15)
	fine.transfer_fraction_to(coarse, 1.0)
	var mid: float = (1.0 + MixtureContainer.GRAIN_SURFACE_MAX) * 0.5
	check(absf(coarse.grain_surface - mid) < 0.05, "equal masses of fine and coarse powder average out (%.2f)" % coarse.grain_surface)
	coarse.add_substance(_idx(&"calcite_powder"), 0.4, 293.15)
	check(coarse.grain_surface < mid, "fresh coarse powder dilutes the grind (%.2f)" % coarse.grain_surface)
