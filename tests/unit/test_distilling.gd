extends "res://tests/unit/unit_test_base.gd"
## Distilling (StillHead3D): vapour sent into a condenser instead of the room
## keeps mass and energy, and what comes over first is what boils first.


func _idx(id: StringName) -> int:
	return SubstanceRegistry.index_of_id(id)


func test_vapour_to_condenser_conserves() -> void:
	var pot: MixtureContainer = MixtureContainer.new()
	pot.add_substance(_idx(&"water"), 1.0, 348.0)
	pot.add_substance(_idx(&"ethanol"), 0.3, 348.0)
	var cond: MixtureContainer = MixtureContainer.new()
	var mass: float = pot.get_total_mass_kg()
	var h: float = pot.enthalpy_joules
	var heat: float = 0.0
	for _i: int in 600:
		heat += pot.add_heat(300.0 * SimConstants.TICK_SECONDS)
		pot.vent_gas_to(cond, 1.0)
	check(cond.get_total_mass_kg() > 1e-4, "vapour reaches the condenser (%.2f g)" % (cond.get_total_mass_kg() * 1000.0))
	check_near(pot.get_total_mass_kg() + cond.get_total_mass_kg(), mass, 1e-9, "mass is kept")
	check_near(pot.enthalpy_joules + cond.enthalpy_joules, h + heat, 1e-3, "energy is kept")
	var eth: float = cond.moles[_idx(&"ethanol")]
	var wat: float = cond.moles[_idx(&"water")]
	check(eth > wat * 2.0, "spirit comes over before water (%.4f mol ethanol, %.4f mol water)" % [eth, wat])
	# Cooled to the room, the vapour condenses into liquid.
	var h_before: float = cond.enthalpy_joules
	var removed: float = 0.0
	for _i: int in 60:
		removed += StillHead3D.cool_arm(cond, SimConstants.TICK_SECONDS)
	check_near(cond.enthalpy_joules, h_before - removed, 1e-6, "the arm's heat goes to the room, all of it accounted")
	check(cond.get_gas_moles() < 1e-6 and cond.get_liquid_volume_m3() > 1e-7, "cooled vapour condenses to a liquid (%.1f K, gas %.5f mol, liquid %.3f mL)" % [cond.temperature_kelvin, cond.get_gas_moles(), cond.get_liquid_volume_m3() * 1e6])
