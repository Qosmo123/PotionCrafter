class_name LabAssay
extends RefCounted
## Physics of the science-bench instruments. Everything is computed from the
## mixture's own property vector, never looked up per potion.
##   * Falling-ball viscometer: terminal velocity of a steel ball with a drag
##     coefficient valid from creeping (Stokes) flow to turbulent flow.
##   * Air-content meter: foam + held gas volume fraction.
##   * Volatility tester: Raoult/Clausius-Clapeyron vapour pressure, flash point.
##   * Hydrometer: buoyant float depth from liquid density.

const BALL_DENSITY_KG_M3: float = 7800.0
const BALL_RADIUS_METERS: float = 0.002
const COLUMN_METERS: float = 0.2
const G_M_S2: float = 9.81

## Viscosity landmarks for kid-friendly comparisons (Pa·s).
const VISCOSITY_LANDMARKS: Array = [[0.0003, "thinner than water (like acetone)"], [0.0015, "water-thin"],
	[0.01, "like milk or warm syrup"], [0.1, "like olive oil"], [1.0, "like glycerin or maple syrup"],
	[25.0, "honey-thick"], [100.0, "like ketchup or toothpaste"], [5000.0, "gloopy slime"], [1e30, "nearly solid, like tar or pitch"]]
const VOLATILITY_LANDMARKS: Array = [[0.5, "LOW (like cooking oil)"], [5.0, "MODERATE (like water)"],
	[15.0, "HIGH (like rubbing alcohol)"], [40.0, "VERY HIGH (like acetone)"], [1e30, "EXTREME (boils away fast!)"]]


## Terminal fall speed of a sphere in a fluid. Iterates the drag balance with
## the Schiller-Naumann drag law (Stokes at low Reynolds number, ~0.44 at high).
static func terminal_velocity_m_s(fluid_density_kg_m3: float, viscosity_pas: float,
		ball_radius_m: float = BALL_RADIUS_METERS, ball_density_kg_m3: float = BALL_DENSITY_KG_M3) -> float:
	var mu: float = maxf(viscosity_pas, 1e-6)
	var drho: float = ball_density_kg_m3 - fluid_density_kg_m3
	if drho <= 0.0:
		return 0.0  # the ball floats
	var rho_f: float = maxf(fluid_density_kg_m3, 1.0)
	var v: float = 2.0 / 9.0 * drho * G_M_S2 * ball_radius_m * ball_radius_m / mu
	for _i: int in 40:
		var re: float = maxf(rho_f * v * 2.0 * ball_radius_m / mu, 1e-9)
		var cd: float = 24.0 / re * (1.0 + 0.15 * pow(re, 0.687)) if re < 1000.0 else 0.44
		var v_new: float = sqrt(8.0 * ball_radius_m * G_M_S2 * drho / (3.0 * rho_f * cd))
		v = lerpf(v, v_new, 0.5)
	return v


## Seconds for the ball to fall the column (INF if it floats).
static func fall_time_s(fluid_density_kg_m3: float, viscosity_pas: float) -> float:
	var v: float = terminal_velocity_m_s(fluid_density_kg_m3, viscosity_pas)
	return COLUMN_METERS / v if v > 0.0 else INF


## Viscosity back-calculated from the fall time (what a real lab does).
static func viscosity_from_fall(fluid_density_kg_m3: float, time_s: float) -> float:
	var v: float = COLUMN_METERS / maxf(time_s, 1e-6)
	return 2.0 / 9.0 * (BALL_DENSITY_KG_M3 - fluid_density_kg_m3) * G_M_S2 * BALL_RADIUS_METERS * BALL_RADIUS_METERS / v


static func describe(value: float, landmarks: Array) -> String:
	for pair: Array in landmarks:
		if value < float(pair[0]):
			return pair[1]
	return landmarks.back()[1]


## Fraction of a sample's volume that is air: foam on top plus gas trapped in
## gels (bubbly slime) and fizz still bubbling out.
static func air_fraction(foam_m3: float, liquid_m3: float, held_gas_m3: float) -> float:
	var total: float = foam_m3 + liquid_m3 + held_gas_m3
	return clampf((foam_m3 + held_gas_m3) / total, 0.0, 1.0) if total > 0.0 else 0.0


## Gas volume (m³) at the mixture's temperature and 1 atm (ideal gas law).
static func gas_volume_m3(moles_value: float, temperature_k: float) -> float:
	return moles_value * SimConstants.GAS_CONSTANT_J_MOL_K * temperature_k / 101325.0


## Hydrometer float: fraction of the stem sunk below the surface. A float of
## fixed mass sinks deeper in light liquids (alcohol) and rides high in syrups.
static func hydrometer_depth_fraction(fluid_density_kg_m3: float) -> float:
	return clampf(remap(fluid_density_kg_m3, 700.0, 1600.0, 0.95, 0.15), 0.05, 0.98)


## Seconds for 10 mL in an open dish to half-evaporate (rough mass-transfer
## estimate: rate ∝ vapour pressure). Water at room temperature ≈ a day.
static func evaporation_half_life_s(vapor_pressure_kpa: float) -> float:
	return 86400.0 * 2.3 / maxf(vapor_pressure_kpa, 1e-4)


static func format_duration(seconds: float) -> String:
	if is_inf(seconds):
		return "forever"
	if seconds < 90.0:
		return "%.0f s" % seconds
	if seconds < 5400.0:
		return "%.0f min" % (seconds / 60.0)
	if seconds < 172800.0:
		return "%.1f h" % (seconds / 3600.0)
	return "%.0f days" % (seconds / 86400.0)


static func format_viscosity(pas: float) -> String:
	if pas < 1.0:
		return "%s mPa·s" % String.num(pas * 1000.0, 2 if pas < 0.01 else 0)
	return "%s Pa·s" % String.num(pas, 1 if pas < 100.0 else 0)


## All measurements for one sample, as stored on a vessel and shown on the
## safety sheet: {viscosity_pas, fall_time_s, density_kg_m3, air_fraction,
## fizz_ml_s, vapor_kpa, flash_k, ph, temperature_k}.
static func assay(m: MixtureContainer, foam_m3: float) -> Dictionary:
	var rho: float = m.get_liquid_density_kg_m3()
	var mu: float = m.get_liquid_viscosity_pas()
	var gel: float = m.get_gel_index()
	var held_gas_m3: float = gas_volume_m3(m.gas_generation_mol_s * 2.0, m.temperature_kelvin) * (0.2 + gel)
	return {
		"viscosity_pas": mu,
		"fall_time_s": fall_time_s(rho, mu),
		"density_kg_m3": rho,
		"air_fraction": air_fraction(foam_m3, m.get_liquid_volume_m3(), held_gas_m3),
		"fizz_ml_s": gas_volume_m3(m.gas_generation_mol_s, m.temperature_kelvin) * 1e6,
		"vapor_kpa": m.get_vapor_pressure_kpa(),
		"flash_k": m.get_flash_point_kelvin(),
		"ph": m.get_ph(),
		"temperature_k": m.temperature_kelvin,
	}
