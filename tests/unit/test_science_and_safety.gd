extends "res://tests/unit/unit_test_base.gd"
## Science-bench physics (viscometer, volatility, air) and the WHMIS sheet.


func _idx(id: StringName) -> int:
	return SubstanceRegistry.index_of_id(id)


func _pure(id: StringName, mol: float = 2.0, t_k: float = 293.15) -> MixtureContainer:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(_idx(id), mol, t_k)
	return m


func test_falling_ball_orders_liquids_by_viscosity() -> void:
	var water_t: float = LabAssay.fall_time_s(998.0, 0.001)
	var glycerin_t: float = LabAssay.fall_time_s(1261.0, 1.41)
	var honey_t: float = LabAssay.fall_time_s(1420.0, 10.0)
	check(water_t < 0.5, "a steel ball drops through water in well under a second (%.2f s)" % water_t)
	check(glycerin_t > water_t * 20.0, "glycerin is far slower than water (%.2f s)" % glycerin_t)
	check(honey_t > glycerin_t * 5.0, "honey is slower still (%.1f s)" % honey_t)
	# In creeping flow the back-calculated viscosity matches the input (Stokes' law).
	var back: float = LabAssay.viscosity_from_fall(1420.0, honey_t)
	check(absf(back - 10.0) / 10.0 < 0.1, "Stokes back-calculation recovers honey's viscosity (%.2f)" % back)
	check(is_inf(LabAssay.fall_time_s(9000.0, 0.01)), "a steel ball floats on something denser than steel")


func test_vapour_pressure_and_flash_point() -> void:
	var water_kpa: float = _pure(&"water").get_vapor_pressure_kpa()
	var acetone_kpa: float = _pure(&"acetone").get_vapor_pressure_kpa()
	check(water_kpa > 1.5 and water_kpa < 4.5, "water ~2.3 kPa at 20 °C (got %.2f)" % water_kpa)
	check(acetone_kpa > water_kpa * 4.0, "acetone is far more volatile than water (%.1f kPa)" % acetone_kpa)
	var hot: MixtureContainer = _pure(&"water", 2.0, 360.0)
	check(hot.get_vapor_pressure_kpa() > water_kpa * 10.0, "hot water evaporates much faster")
	check(not is_nan(_pure(&"acetone").get_flash_point_kelvin()) and _pure(&"acetone").get_flash_point_kelvin() < 273.15, "acetone flash point below 0 °C")
	check(is_nan(_pure(&"water").get_flash_point_kelvin()), "water has no flash point")
	var brine: MixtureContainer = _pure(&"water", 2.0)
	brine.add_substance(_idx(&"salt_brine"), 2.0, 293.15)
	check(brine.get_vapor_pressure_kpa() <= water_kpa + 1e-6, "dissolved salt does not raise water's vapour pressure")


func test_air_fraction_and_assay_dictionary() -> void:
	check(absf(LabAssay.air_fraction(1.0, 1.0, 0.0) - 0.5) < 1e-6, "equal foam and liquid = 50% air")
	var a: Dictionary = LabAssay.assay(_pure(&"glycerin"), 0.0)
	for key: String in ["viscosity_pas", "fall_time_s", "density_kg_m3", "air_fraction", "vapor_kpa", "ph"]:
		check(a.has(key) and not is_nan(float(a[key])), "assay reports %s" % key)
	check(absf(float(a["density_kg_m3"]) - 1261.0) < 5.0, "hydrometer density of glycerin")


func test_safety_sheet_classifies_real_hazards() -> void:
	var acid: MixtureContainer = _pure(&"water", 3.0)
	acid.add_substance(_idx(&"hydrochloric_acid"), 1.0, 293.15)
	var s: Dictionary = SafetySheet.build(acid)
	check((s["pictograms"] as Array).has(SafetySheet.Pictogram.CORROSION), "strong acid gets the corrosion pictogram")
	check(not (s["pictograms"] as Array).has(SafetySheet.Pictogram.EXCLAMATION), "no exclamation mark alongside corrosion")
	check(s["signal"] == "DANGER", "strong acid is DANGER")
	var found_cas: bool = false
	for c: Array in s["composition"]:
		if String(c[2]) == "7647-01-0":
			found_cas = true
	check(found_cas, "composition lists HCl's CAS number")
	var solvent: Dictionary = SafetySheet.build(_pure(&"acetone"))
	check((solvent["pictograms"] as Array).has(SafetySheet.Pictogram.FLAME), "acetone is flammable")
	var water: Dictionary = SafetySheet.build(_pure(&"water"))
	check(water["signal"] == "NONE" and (water["pictograms"] as Array).is_empty(), "water is not classified")


func test_kid_potions_get_silly_hazards() -> void:
	var m: MixtureContainer = _pure(&"water", 2.0)
	m.add_substance(_idx(&"ghost_sneeze"), 0.6, 293.15)
	var s: Dictionary = SafetySheet.build(m)
	check(s["kid"], "a spooky ingredient makes it a kid potion")
	check((s["pictograms"] as Array).has(SafetySheet.Pictogram.SILLY), "kid potions get the silly pictogram")
	check(not (s["silly"] as PackedStringArray).is_empty(), "silly hazards are written")
	var ghosts: bool = false
	for line: String in s["silly"]:
		ghosts = ghosts or line.contains("ghost")
	check(ghosts, "spooky mixture warns about ghosts (from its spookiness value)")
