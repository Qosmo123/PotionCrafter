class_name MixtureContainer
extends RefCounted
## Conserved multi-species mixture.
##
## State is moles per species plus one total enthalpy value. Temperature and
## phase fractions are derived from those, so moving moles and enthalpy around
## conserves mass and energy by construction (to float64 rounding).
##
## Each species' specific enthalpy h(T) is piecewise-linear and strictly rising:
##   h(T) = c*T + L_fusion*melt(T) + L_vapor*boil(T)
## where melt()/boil() ramp 0->1 across a 1 K band around the transition point.
## Inverting h(T) by bisection gives temperature. Phase fractions, latent heat
## plateaus, and evaporative cooling all come out of that one curve.
##
## Hot-loop safe: every buffer is allocated in _init(); no per-tick allocation.

enum Phase { SOLID, LIQUID, GAS }

const PHASE_BAND_KELVIN: float = 1.0
const BISECTION_ITERATIONS: int = 52
const MIN_MASS_KG: float = 1e-12
const SWIRL_BASE_DAMPING_PER_S: float = 0.35
const PROTON_TRANSFER_RATE_PER_S: float = 2.5
const NEUTRALISATION_ENTHALPY_J_MOL: float = -55800.0  # strong acid + strong base -> water
const POLARITY_RATE_PER_S: float = 1.2
const THAUM_ENERGY_J: float = 350.0
const ACTIVATION_ENERGY_J_MOL: float = 30000.0
const GEL_EXPONENT: float = 12.0
const PRECIPITATION_RATE_PER_S: float = 6.0
const PRECIPITATION_ENTHALPY_J_MOL: float = -15000.0
const CATALYSIS_GAIN: float = 30000.0
const BURN_MAX_KG_S: float = 0.0006
## Most flame heat escapes to the room; this share goes into the contents.
const FLAME_HEAT_FRACTION: float = 0.04
const MIN_FUEL_FRACTION: float = 0.25
const TRANSMUTATION_RATE_PER_S: float = 0.05
const REDOX_RATE_PER_S: float = 3.0
const COMPLEXATION_RATE_PER_S: float = 4.0
const DISSOLUTION_RATE_PER_S: float = 1.5
const CRYSTALLIZATION_RATE_PER_S: float = 2.5
const SHEAR_GAIN: float = 60.0

var species_count: int = 0
var moles: PackedFloat64Array = PackedFloat64Array()
var enthalpy_joules: float = 0.0
var temperature_kelvin: float = SimConstants.AMBIENT_TEMP_KELVIN
## Angular momentum injected by stirring (rad/s, sign = chirality).
var swirl_rad_s: float = 0.0
## Energy added or removed by the temperature-range safety clamp, kept so audits still balance.
var clamp_correction_joules: float = 0.0
## Enthalpy carried by the most recent phase transfer (for audits).
var last_transfer_enthalpy_joules: float = 0.0
## Cumulative chemical/thaumic heat released by reactions (for energy audits).
var reaction_heat_joules: float = 0.0
## Gas produced by reactions during the last step (mol/s), drives fizz visuals.
var gas_generation_mol_s: float = 0.0
## Arcane flash intensity from polarity annihilation; decays each step.
var arcane_flash: float = 0.0
## Packed (a * 1024 + b) keys of species pairs that reacted in the last step
## (a == b for single-species channels: decomposition, combustion, transmutation).
var active_reaction_pairs: PackedInt32Array = PackedInt32Array()
## Combustion state: once lit, burns while fuel and air last.
var burning: bool = false
var burn_rate_kg_s: float = 0.0
## New solid precipitate formed per second (drives the cloudy suspension).
var precipitation_rate_mol_s: float = 0.0
var transmutation_rate_mol_s: float = 0.0
## Lingering smell from odorous gases released by reactions (decays over time).
var odor_memory: float = 0.0
## Stirring/shaking intensity, set by the vessel each tick (drives shear-thickening).
var shear_rate: float = 0.0
var redox_rate_mol_s: float = 0.0

var _molar_mass_kg_mol: PackedFloat64Array = PackedFloat64Array()
var _specific_heat_j_kg_k: PackedFloat64Array = PackedFloat64Array()
var _melting_point_kelvin: PackedFloat64Array = PackedFloat64Array()
var _boiling_point_kelvin: PackedFloat64Array = PackedFloat64Array()
var _latent_fusion_j_kg: PackedFloat64Array = PackedFloat64Array()
var _latent_vapor_j_kg: PackedFloat64Array = PackedFloat64Array()
var _density_kg_m3: PackedFloat64Array = PackedFloat64Array()
var _log_viscosity: PackedFloat64Array = PackedFloat64Array()
var _gravity_coupling: PackedFloat64Array = PackedFloat64Array()
var _thaums_per_mol: PackedFloat64Array = PackedFloat64Array()
var _turbidity: PackedFloat64Array = PackedFloat64Array()
var _albedo: PackedColorArray = PackedColorArray()
var _emission: PackedColorArray = PackedColorArray()
var _acid_strength: PackedFloat64Array = PackedFloat64Array()
var _base_strength: PackedFloat64Array = PackedFloat64Array()
var _proton_enthalpy_j_mol: PackedFloat64Array = PackedFloat64Array()
var _polarity: PackedFloat64Array = PackedFloat64Array()
var _crosslink: PackedFloat64Array = PackedFloat64Array()
var _crosslinker: PackedFloat64Array = PackedFloat64Array()
var _foaming: PackedFloat64Array = PackedFloat64Array()
var _foam_stability: PackedFloat64Array = PackedFloat64Array()
var _indicator: PackedFloat64Array = PackedFloat64Array()
var _indicator_acid: PackedColorArray = PackedColorArray()
var _indicator_base: PackedColorArray = PackedColorArray()
## Flattened product table: species i's products are [_product_start[i], _product_start[i+1]).
var _product_start: PackedInt32Array = PackedInt32Array()
var _product_index: PackedInt32Array = PackedInt32Array()
var _product_fraction: PackedFloat64Array = PackedFloat64Array()
var _group: PackedInt32Array = PackedInt32Array()
var _precipitant: PackedFloat64Array = PackedFloat64Array()
var _decomp_rate: PackedFloat64Array = PackedFloat64Array()
var _decomp_enthalpy: PackedFloat64Array = PackedFloat64Array()
var _catalyst: PackedFloat64Array = PackedFloat64Array()
var _combustion_j_kg: PackedFloat64Array = PackedFloat64Array()
var _flash_kelvin: PackedFloat64Array = PackedFloat64Array()
var _autoignition_kelvin: PackedFloat64Array = PackedFloat64Array()
var _transmute: PackedFloat64Array = PackedFloat64Array()
var _thermo: PackedFloat64Array = PackedFloat64Array()
var _thermo_cold: PackedColorArray = PackedColorArray()
var _thermo_hot: PackedColorArray = PackedColorArray()
var _thermo_cold_k: PackedFloat64Array = PackedFloat64Array()
var _thermo_hot_k: PackedFloat64Array = PackedFloat64Array()
var _glitter: PackedFloat64Array = PackedFloat64Array()
var _odor: PackedFloat64Array = PackedFloat64Array()
var _magnetic: PackedFloat64Array = PackedFloat64Array()
var _oxid: PackedFloat64Array = PackedFloat64Array()
var _reduc: PackedFloat64Array = PackedFloat64Array()
var _redox_h: PackedFloat64Array = PackedFloat64Array()
var _redox_act: PackedFloat64Array = PackedFloat64Array()
var _ligand: PackedFloat64Array = PackedFloat64Array()
var _complexable: PackedFloat64Array = PackedFloat64Array()
var _diss_h: PackedFloat64Array = PackedFloat64Array()
var _dissolves: PackedFloat64Array = PackedFloat64Array()
var _cryst: PackedFloat64Array = PackedFloat64Array()
var _cryst_h: PackedFloat64Array = PackedFloat64Array()
var _shear: PackedFloat64Array = PackedFloat64Array()
var _flame_col: PackedColorArray = PackedColorArray()
var _flame_str: PackedFloat64Array = PackedFloat64Array()
var _tox: PackedFloat64Array = PackedFloat64Array()
var _health: PackedFloat64Array = PackedFloat64Array()
var _env: PackedFloat64Array = PackedFloat64Array()
var _spooky: PackedFloat64Array = PackedFloat64Array()
var _electric: PackedFloat64Array = PackedFloat64Array()
var _rainbow: PackedFloat64Array = PackedFloat64Array()
## Redox and complexation product tables (same flattened layout as the default table).
var _rx_start: PackedInt32Array = PackedInt32Array()
var _rx_index: PackedInt32Array = PackedInt32Array()
var _rx_fraction: PackedFloat64Array = PackedFloat64Array()
var _cx_start: PackedInt32Array = PackedInt32Array()
var _cx_index: PackedInt32Array = PackedInt32Array()
var _cx_fraction: PackedFloat64Array = PackedFloat64Array()


func _init() -> void:
	SubstanceRegistry.ensure_loaded()
	species_count = SubstanceRegistry.count()
	moles.resize(species_count)
	moles.fill(0.0)
	_molar_mass_kg_mol.resize(species_count)
	_specific_heat_j_kg_k.resize(species_count)
	_melting_point_kelvin.resize(species_count)
	_boiling_point_kelvin.resize(species_count)
	_latent_fusion_j_kg.resize(species_count)
	_latent_vapor_j_kg.resize(species_count)
	_density_kg_m3.resize(species_count)
	_log_viscosity.resize(species_count)
	_gravity_coupling.resize(species_count)
	_thaums_per_mol.resize(species_count)
	_turbidity.resize(species_count)
	_albedo.resize(species_count)
	_emission.resize(species_count)
	_acid_strength.resize(species_count)
	_base_strength.resize(species_count)
	_proton_enthalpy_j_mol.resize(species_count)
	_polarity.resize(species_count)
	_crosslink.resize(species_count)
	_crosslinker.resize(species_count)
	_foaming.resize(species_count)
	_foam_stability.resize(species_count)
	_indicator.resize(species_count)
	_indicator_acid.resize(species_count)
	_indicator_base.resize(species_count)
	_product_start.resize(species_count + 1)
	_group.resize(species_count)
	_precipitant.resize(species_count)
	_decomp_rate.resize(species_count)
	_decomp_enthalpy.resize(species_count)
	_catalyst.resize(species_count)
	_combustion_j_kg.resize(species_count)
	_flash_kelvin.resize(species_count)
	_autoignition_kelvin.resize(species_count)
	_transmute.resize(species_count)
	_thermo.resize(species_count)
	_thermo_cold.resize(species_count)
	_thermo_hot.resize(species_count)
	_thermo_cold_k.resize(species_count)
	_thermo_hot_k.resize(species_count)
	_glitter.resize(species_count)
	_odor.resize(species_count)
	_magnetic.resize(species_count)
	for arr_name: String in ["_oxid", "_reduc", "_redox_h", "_redox_act", "_ligand", "_complexable", "_diss_h", "_dissolves",
			"_cryst", "_cryst_h", "_shear", "_flame_str", "_tox", "_health", "_env", "_spooky", "_electric", "_rainbow"]:
		var arr: PackedFloat64Array = get(arr_name)
		arr.resize(species_count)
		set(arr_name, arr)
	_flame_col.resize(species_count)
	_rx_start.resize(species_count + 1)
	_cx_start.resize(species_count + 1)
	for i: int in species_count:
		var s: SubstanceData = SubstanceRegistry.get_substance(i)
		_molar_mass_kg_mol[i] = maxf(s.molar_mass_kg_mol, 1e-6)
		_specific_heat_j_kg_k[i] = maxf(s.specific_heat_j_kg_k, 1.0)
		_melting_point_kelvin[i] = s.melting_point_kelvin
		_boiling_point_kelvin[i] = maxf(s.boiling_point_kelvin, s.melting_point_kelvin + PHASE_BAND_KELVIN)
		_latent_fusion_j_kg[i] = maxf(s.latent_heat_fusion_j_kg, 0.0)
		_latent_vapor_j_kg[i] = maxf(s.latent_heat_vaporization_j_kg, 0.0)
		_density_kg_m3[i] = maxf(s.density_kg_m3, 1e-3)
		_log_viscosity[i] = log(maxf(s.viscosity_pas, 1e-7))
		_gravity_coupling[i] = s.gravity_coupling
		_thaums_per_mol[i] = s.thaumic_density_thaums_mol
		_turbidity[i] = s.turbidity
		_albedo[i] = s.base_albedo_rgba
		_emission[i] = s.emissive_aura_hdr
		# Acid/base strength from pKa; water-like solvents (pKa >= 14) stay inert.
		_acid_strength[i] = clampf((6.5 - s.pka_acidity) / 6.5, 0.0, 1.0)
		_base_strength[i] = clampf((s.pka_acidity - 8.0) / 6.0, 0.0, 1.0) if s.pka_acidity < 14.0 else 0.0
		_proton_enthalpy_j_mol[i] = s.proton_transfer_enthalpy_j_mol
		_polarity[i] = s.polarity_charge
		_crosslink[i] = s.crosslink_sites
		_crosslinker[i] = s.crosslinker_strength
		_foaming[i] = s.foaming
		_foam_stability[i] = s.foam_stability
		_indicator[i] = s.indicator_strength
		_indicator_acid[i] = s.indicator_acid_color
		_indicator_base[i] = s.indicator_base_color
		_group[i] = s.miscibility_group
		_precipitant[i] = s.precipitant_charge
		_decomp_rate[i] = s.decomposition_rate_per_s
		_decomp_enthalpy[i] = s.decomposition_enthalpy_j_mol
		_catalyst[i] = s.catalyst_strength
		_combustion_j_kg[i] = s.combustion_enthalpy_j_kg
		# Flash point: vapour lights from a flame/spark; autoignition: lights by heat alone.
		_flash_kelvin[i] = s.boiling_point_kelvin - 70.0 * s.flammability
		_autoignition_kelvin[i] = 700.0 - 380.0 * s.flammability
		_transmute[i] = s.transmutation_valence
		_thermo[i] = s.thermochromic_strength
		_thermo_cold[i] = s.thermo_cold_color
		_thermo_hot[i] = s.thermo_hot_color
		_thermo_cold_k[i] = s.thermo_cold_kelvin
		_thermo_hot_k[i] = s.thermo_hot_kelvin
		_glitter[i] = s.glitter
		_odor[i] = s.odor
		_magnetic[i] = s.magnetic
		_oxid[i] = s.oxidizer_strength
		_reduc[i] = s.reducer_strength
		_redox_h[i] = s.redox_enthalpy_j_mol
		_redox_act[i] = s.redox_activation_kelvin
		_ligand[i] = s.ligand_strength
		_complexable[i] = s.complexable
		_dissolves[i] = 1.0 if s.dissolves_in_water else 0.0
		_diss_h[i] = s.dissolution_enthalpy_j_mol
		_cryst[i] = 1.0 if s.crystallizes_on_seed else 0.0
		_cryst_h[i] = s.crystallization_enthalpy_j_mol
		_shear[i] = s.shear_thickening
		_flame_col[i] = s.flame_color
		_flame_str[i] = s.flame_strength
		_tox[i] = s.toxicity
		_health[i] = s.health_hazard
		_env[i] = s.environmental_hazard
		_spooky[i] = s.spookiness
		_electric[i] = s.electric_charge
		_rainbow[i] = s.rainbow
		if s.flash_point_kelvin > 0.0:
			_flash_kelvin[i] = s.flash_point_kelvin
		_rx_start[i] = _rx_index.size()
		_append_table(s.redox_products, s.redox_fractions, _rx_index, _rx_fraction)
		_cx_start[i] = _cx_index.size()
		_append_table(s.complex_products, s.complex_fractions, _cx_index, _cx_fraction)
		_product_start[i] = _product_index.size()
		var product_count: int = mini(s.reaction_products.size(), s.reaction_product_mass_fractions.size())
		var fraction_sum: float = 0.0
		for k: int in product_count:
			fraction_sum += maxf(s.reaction_product_mass_fractions[k], 0.0)
		for k: int in product_count:
			var product_index: int = SubstanceRegistry.index_of(s.reaction_products[k] as SubstanceData)
			if product_index < 0 or fraction_sum <= 0.0:
				continue
			_product_index.append(product_index)
			_product_fraction.append(maxf(s.reaction_product_mass_fractions[k], 0.0) / fraction_sum)
	_product_start[species_count] = _product_index.size()
	_rx_start[species_count] = _rx_index.size()
	_cx_start[species_count] = _cx_index.size()


func _append_table(products: Array[Resource], fractions: PackedFloat32Array, index_out: PackedInt32Array, fraction_out: PackedFloat64Array) -> void:
	var n: int = mini(products.size(), fractions.size())
	var total: float = 0.0
	for k: int in n:
		total += maxf(fractions[k], 0.0)
	for k: int in n:
		var pi: int = SubstanceRegistry.index_of(products[k] as SubstanceData)
		if pi >= 0 and total > 0.0:
			index_out.append(pi)
			fraction_out.append(maxf(fractions[k], 0.0) / total)


# --- Mutation -----------------------------------------------------------------

## Add `amount_moles` of species `index` arriving at `temp_kelvin`.
func add_substance(index: int, amount_moles: float, temp_kelvin: float) -> void:
	if index < 0 or index >= species_count:
		return
	if not (amount_moles > 0.0) or is_inf(amount_moles):
		return
	var t: float = SimConstants.sanitize_temp_kelvin(temp_kelvin)
	moles[index] += amount_moles
	enthalpy_joules += amount_moles * _molar_mass_kg_mol[index] * specific_enthalpy_j_kg(index, t)
	_solve_temperature()


## Add (or remove, if negative) heat. Ignored when the vessel holds no mass.
## Returns the joules actually accepted.
func add_heat(joules: float) -> float:
	if is_nan(joules) or is_inf(joules) or get_total_mass_kg() < MIN_MASS_KG:
		return 0.0
	enthalpy_joules += joules
	_solve_temperature()
	return joules


## Move `fraction` of everything (all phases) into `dst`. Exact: enthalpy scales with amount.
func transfer_fraction_to(dst: MixtureContainer, fraction: float) -> float:
	last_transfer_enthalpy_joules = 0.0
	var f: float = clampf(fraction, 0.0, 1.0)
	if f <= 0.0:
		return 0.0
	var moved_mass_kg: float = 0.0
	for i: int in species_count:
		var amount: float = moles[i] * f
		moles[i] -= amount
		moved_mass_kg += amount * _molar_mass_kg_mol[i]
		if dst != null:
			dst.moles[i] += amount
	var moved_enthalpy: float = enthalpy_joules * f
	enthalpy_joules -= moved_enthalpy
	last_transfer_enthalpy_joules = moved_enthalpy
	if dst != null:
		dst.enthalpy_joules += moved_enthalpy
		dst._solve_temperature()
	_solve_temperature()
	return moved_mass_kg


## Pour up to `volume_m3` of the liquid phase into `dst` (null = spilled/lost).
## Returns the mass moved in kg.
func transfer_liquid_volume_to(dst: MixtureContainer, volume_m3: float) -> float:
	last_transfer_enthalpy_joules = 0.0
	var liquid_m3: float = get_liquid_volume_m3()
	if liquid_m3 <= 0.0 or not (volume_m3 > 0.0):
		return 0.0
	return _move_phase(dst, Phase.LIQUID, clampf(volume_m3 / liquid_m3, 0.0, 1.0))


## Release `fraction` of the gas phase to the room. Vapour leaves carrying its
## full latent heat, so the remaining liquid cools (evaporative cooling).
## Returns the mass vented in kg.
func vent_gas(fraction: float) -> float:
	return _move_phase(null, Phase.GAS, clampf(fraction, 0.0, 1.0))


## Relax toward ambient through a thermal conductance (W/K), unconditionally
## stable (exponential integrator). Stirring speeds up exchange; swirl decays
## faster in viscous liquids. Returns the heat exchanged with the room in joules.
func step_thermal(delta_s: float, ambient_kelvin: float, conductance_w_k: float) -> float:
	var viscosity_pas: float = get_liquid_viscosity_pas()
	swirl_rad_s *= exp(-delta_s * (SWIRL_BASE_DAMPING_PER_S + 25.0 * viscosity_pas))
	var heat_capacity_j_k: float = get_heat_capacity_j_k()
	if heat_capacity_j_k <= 0.0 or conductance_w_k <= 0.0:
		return 0.0
	var effective_g: float = conductance_w_k * (1.0 + 0.15 * absf(swirl_rad_s))
	var alpha: float = 1.0 - exp(-effective_g * delta_s / heat_capacity_j_k)
	var target_h: float = enthalpy_at(SimConstants.sanitize_temp_kelvin(ambient_kelvin))
	var q: float = (target_h - enthalpy_joules) * alpha
	enthalpy_joules += q
	_solve_temperature()
	return q


func clear() -> void:
	moles.fill(0.0)
	enthalpy_joules = 0.0
	swirl_rad_s = 0.0


# --- Reactions ----------------------------------------------------------------------

## Advance every reaction channel by `delta_s`. `mixing` (0..2) is how well
## stirred/agitated the contents are. Returns the total enthalpy change in
## joules: reaction heat plus the sensible/latent difference between products
## and reactants converted at the current temperature (so audits balance exactly).
## Channels (all driven by property vectors, never by named pairs):
##   proton transfer: any acid (pKa < 6.5) with any base (8 < pKa < 14)
##   polarity annihilation: any +polarity arcane species with any -polarity one
## A species is only consumed if it declares reaction products, so mass is
## always conserved exactly.
func step_reactions(delta_s: float, mixing: float, air_access: bool = true, ignition_source: bool = false) -> float:
	gas_generation_mol_s = 0.0
	redox_rate_mol_s = 0.0
	burn_rate_kg_s = 0.0
	precipitation_rate_mol_s = 0.0
	transmutation_rate_mol_s = 0.0
	arcane_flash *= exp(-delta_s * 3.0)
	odor_memory *= exp(-delta_s * 0.15)
	active_reaction_pairs.resize(0)
	if get_total_mass_kg() < MIN_MASS_KG:
		burning = false
		return 0.0
	var t: float = temperature_kelvin
	var arrhenius: float = clampf(exp(-ACTIVATION_ENERGY_J_MOL / SimConstants.GAS_CONSTANT_J_MOL_K
		* (1.0 / t - 1.0 / SimConstants.AMBIENT_TEMP_KELVIN)), 0.0, 50.0)
	var mix_factor: float = 0.35 + clampf(mixing, 0.0, 2.0)
	var heat_j: float = 0.0
	var chem_j: float = 0.0
	var gas_before: float = get_gas_moles()
	var catalysis_sum: float = 0.0
	var total_n: float = maxf(get_total_moles(), 1e-12)
	for c: int in species_count:
		catalysis_sum += _catalyst[c] * moles[c] / total_n
	for i: int in species_count:
		if moles[i] <= 0.0:
			continue
		var i_has: bool = _product_start[i + 1] != _product_start[i]
		for j: int in range(i + 1, species_count):
			if moles[j] <= 0.0:
				continue
			var j_has: bool = _product_start[j + 1] != _product_start[j]
			# Redox: oxidizer + reducer (either way round), frozen below activation unless burning.
			var ox: int = -1
			var red: int = -1
			if _oxid[i] > 0.0 and _reduc[j] > 0.0:
				ox = i
				red = j
			elif _oxid[j] > 0.0 and _reduc[i] > 0.0:
				ox = j
				red = i
			if ox >= 0 and _rx_start[ox + 1] != _rx_start[ox] and _rx_start[red + 1] != _rx_start[red]:
				var act: float = maxf(_redox_act[ox], _redox_act[red])
				if t >= act or (burning and act <= 2500.0):
					var kr: float = REDOX_RATE_PER_S * _oxid[ox] * _reduc[red] * mix_factor * (1.0 + catalysis_sum * 300.0) * (arrhenius if act <= 0.0 else 1.0)
					var extent_r: float = minf(_condensed_moles(ox, t), _condensed_moles(red, t)) * (1.0 - exp(-kr * delta_s))
					if extent_r > 1e-12:
						heat_j += -extent_r * _redox_h[ox]
						chem_j += _consume(ox, extent_r, t, 1)
						chem_j += _consume(red, extent_r, t, 1)
						redox_rate_mol_s += extent_r / maxf(delta_s, 1e-6)
						active_reaction_pairs.append(i * 1024 + j)
			# Complexation: ligand wraps a complexable ion into a coloured complex.
			var lig: int = -1
			var cpx: int = -1
			if _ligand[i] > 0.0 and _complexable[j] > 0.0:
				lig = i
				cpx = j
			elif _ligand[j] > 0.0 and _complexable[i] > 0.0:
				lig = j
				cpx = i
			if lig >= 0 and _cx_start[cpx + 1] != _cx_start[cpx]:
				var kc: float = COMPLEXATION_RATE_PER_S * _ligand[lig] * _complexable[cpx] * mix_factor
				var extent_c: float = minf(_condensed_moles(lig, t), _condensed_moles(cpx, t)) * (1.0 - exp(-kc * delta_s))
				if extent_c > 1e-12:
					chem_j += _consume(cpx, extent_c, t, 2)
					chem_j += _consume_into(lig, extent_c, cpx, t)
					active_reaction_pairs.append(i * 1024 + j)
			if not (i_has and j_has):
				continue
			# Proton transfer (either direction).
			var ab: float = _acid_strength[i] * _base_strength[j] + _acid_strength[j] * _base_strength[i]
			if ab > 0.0:
				var k: float = PROTON_TRANSFER_RATE_PER_S * ab * arrhenius * mix_factor
				var extent: float = minf(_condensed_moles(i, t), _condensed_moles(j, t)) * (1.0 - exp(-k * delta_s))
				if extent > 1e-12:
					heat_j += -extent * (NEUTRALISATION_ENTHALPY_J_MOL * ab + _proton_enthalpy_j_mol[i] + _proton_enthalpy_j_mol[j])
					chem_j += _consume(i, extent, t)
					chem_j += _consume(j, extent, t)
					active_reaction_pairs.append(i * 1024 + j)
			# Precipitation: dissolved cation meets precipitating anion.
			var pq: float = -_precipitant[i] * _precipitant[j]
			if pq > 0.0:
				var kq: float = PRECIPITATION_RATE_PER_S * pq * mix_factor
				var extent_q: float = minf(_condensed_moles(i, t), _condensed_moles(j, t)) * (1.0 - exp(-kq * delta_s))
				if extent_q > 1e-12:
					heat_j += -extent_q * PRECIPITATION_ENTHALPY_J_MOL
					chem_j += _consume(i, extent_q, t)
					chem_j += _consume(j, extent_q, t)
					precipitation_rate_mol_s += extent_q / maxf(delta_s, 1e-6)
					active_reaction_pairs.append(i * 1024 + j)
			# Polarity annihilation (arcane).
			var pp: float = -_polarity[i] * _polarity[j]
			if pp > 0.0:
				var kp: float = POLARITY_RATE_PER_S * pp * mix_factor
				var extent_p: float = minf(_condensed_moles(i, t), _condensed_moles(j, t)) * (1.0 - exp(-kp * delta_s))
				if extent_p > 1e-12:
					var qp: float = extent_p * (_thaums_per_mol[i] + _thaums_per_mol[j]) * absf(_polarity[i] - _polarity[j]) * THAUM_ENERGY_J
					chem_j += _consume(i, extent_p, t)
					chem_j += _consume(j, extent_p, t)
					heat_j += qp
					arcane_flash = minf(arcane_flash + qp / 1500.0, 4.0)
					active_reaction_pairs.append(i * 1024 + j)
	var single: Vector2 = _step_single_species_channels(delta_s, t, arrhenius, air_access, ignition_source)
	heat_j += single.x
	chem_j += single.y
	if heat_j != 0.0:
		enthalpy_joules += heat_j
		reaction_heat_joules += heat_j
	_solve_temperature()
	gas_generation_mol_s = maxf(get_gas_moles() - gas_before, 0.0) / maxf(delta_s, 1e-6)
	return heat_j + chem_j


## Decomposition (catalysed), combustion and transmutation. Returns (heat, conversion enthalpy).
func _step_single_species_channels(delta_s: float, t: float, arrhenius: float, air_access: bool, ignition_source: bool) -> Vector2:
	var heat_j: float = 0.0
	var chem_j: float = 0.0
	var total_moles: float = get_total_moles()
	if total_moles <= 0.0:
		return Vector2.ZERO
	var catalysis: float = 0.0
	var thaums_per_mol: float = get_total_thaums() / total_moles
	var fuel_moles: float = 0.0
	var can_light: bool = false
	for i: int in species_count:
		if moles[i] <= 0.0:
			continue
		catalysis += _catalyst[i] * moles[i] / total_moles
		if _combustion_j_kg[i] < 0.0:
			fuel_moles += _condensed_moles(i, t)
			if t >= _autoignition_kelvin[i] or (ignition_source and t >= _flash_kelvin[i]):
				can_light = true
	var fuel_fraction: float = fuel_moles / total_moles
	if not air_access or fuel_fraction < MIN_FUEL_FRACTION:
		burning = false
	elif can_light:
		burning = true

	var aqueous_fraction: float = 0.0
	var any_solid: bool = false
	for w: int in species_count:
		if moles[w] > 0.0:
			if _group[w] == 0:
				aqueous_fraction += _species_phase_volume_m3(w, Phase.LIQUID)
			if _species_phase_volume_m3(w, Phase.SOLID) > 1e-9 and _cryst[w] == 0.0:
				any_solid = true
	var liquid_total: float = maxf(get_liquid_volume_m3(), 1e-12)
	aqueous_fraction = aqueous_fraction / liquid_total if get_liquid_volume_m3() > 0.0 else 0.0
	for i: int in species_count:
		if moles[i] <= 0.0 or _product_start[i + 1] == _product_start[i]:
			continue
		var n: float = _condensed_moles(i, t)
		if _dissolves[i] > 0.0 and aqueous_fraction > 0.3:
			var extent_s: float = n * (1.0 - exp(-DISSOLUTION_RATE_PER_S * delta_s))
			if extent_s > 1e-12:
				heat_j += -extent_s * _diss_h[i]
				chem_j += _consume(i, extent_s, t)
				active_reaction_pairs.append(i * 1024 + i)
			continue
		if _cryst[i] > 0.0:
			if any_solid:
				var extent_x: float = n * (1.0 - exp(-CRYSTALLIZATION_RATE_PER_S * delta_s))
				if extent_x > 1e-12:
					heat_j += -extent_x * _cryst_h[i]
					chem_j += _consume(i, extent_x, t)
					active_reaction_pairs.append(i * 1024 + i)
			continue
		if _decomp_rate[i] > 0.0:
			# Only kinetically hindered (slow) decompositions are catalysed; intrinsic fast
			# decays such as an excited molecule emitting light are not.
			var kd: float = _decomp_rate[i] * arrhenius * ((1.0 + CATALYSIS_GAIN * catalysis) if _decomp_rate[i] < 0.05 else 1.0)
			var extent_d: float = n * (1.0 - exp(-kd * delta_s))
			if extent_d > 1e-12:
				heat_j += -extent_d * _decomp_enthalpy[i]
				chem_j += _consume(i, extent_d, t)
				active_reaction_pairs.append(i * 1024 + i)
				n = _condensed_moles(i, t)
		if burning and _combustion_j_kg[i] < 0.0 and n > 0.0:
			var share: float = n / maxf(fuel_moles, 1e-12)
			var burn_kg: float = minf(BURN_MAX_KG_S * share * delta_s, n * _molar_mass_kg_mol[i])
			if burn_kg > 0.0:
				heat_j += -burn_kg * _combustion_j_kg[i] * FLAME_HEAT_FRACTION
				chem_j += _consume(i, burn_kg / _molar_mass_kg_mol[i], t)
				burn_rate_kg_s += burn_kg / maxf(delta_s, 1e-6)
				active_reaction_pairs.append(i * 1024 + i)
				n = _condensed_moles(i, t)
		if _transmute[i] > 0.0 and n > 0.0 and thaums_per_mol > 10.0 and t > 330.0:
			var kt: float = TRANSMUTATION_RATE_PER_S * _transmute[i] * clampf((thaums_per_mol - 10.0) / 30.0, 0.0, 1.0) * clampf((t - 330.0) / 60.0, 0.0, 1.0)
			var extent_t: float = n * (1.0 - exp(-kt * delta_s))
			if extent_t > 1e-12:
				chem_j += _consume(i, extent_t, t)
				transmutation_rate_mol_s += extent_t / maxf(delta_s, 1e-6)
				active_reaction_pairs.append(i * 1024 + i)
	return Vector2(heat_j, chem_j)


## Flame-test colour: weighted by each species' flame strength (orange if none).
func get_flame_color() -> Color:
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	var w_total: float = 0.0
	for i: int in species_count:
		if moles[i] <= 0.0 or _flame_str[i] <= 0.0:
			continue
		var w: float = moles[i] * _flame_str[i] * _flame_str[i]
		r += _flame_col[i].r * w
		g += _flame_col[i].g * w
		b += _flame_col[i].b * w
		w_total += w
	if w_total <= 0.0:
		return Color(1.0, 0.5, 0.12)
	return Color(r / w_total, g / w_total, b / w_total)


## WHMIS-style hazard level: the worst component, scaled by how much of it is present.
func hazard_level(kind: StringName) -> float:
	var values: PackedFloat64Array = _tox
	match kind:
		&"health": values = _health
		&"environment": values = _env
		&"oxidizer": values = _oxid
		&"flammable": values = PackedFloat64Array()
	var total: float = maxf(get_total_moles(), 1e-12)
	var worst: float = 0.0
	for i: int in species_count:
		if moles[i] <= 0.0:
			continue
		var share: float = clampf(moles[i] / total * 6.0, 0.0, 1.0)
		var v: float = (values[i] if not values.is_empty() else (1.0 if _combustion_j_kg[i] < 0.0 else 0.0) * clampf(1.0 - (_flash_kelvin[i] - 250.0) / 150.0, 0.0, 1.0))
		worst = maxf(worst, v * share)
	return worst


func get_spookiness() -> float:
	return clampf(_condensed_weighted(_spooky) * 4.0, 0.0, 1.0)


func get_electric() -> float:
	return clampf(_condensed_weighted(_electric) * 4.0, 0.0, 1.0)


func get_rainbow() -> float:
	return clampf(_condensed_weighted(_rainbow) * 4.0, 0.0, 1.0)


## Red-hot glow of very hot contents (blackbody-ish), as HDR colour.
func get_incandescence() -> Color:
	var t: float = temperature_kelvin
	if t < 800.0:
		return Color(0.0, 0.0, 0.0)
	var k: float = clampf((t - 800.0) / 1700.0, 0.0, 1.0)
	return Color(1.0, lerpf(0.15, 0.85, k), lerpf(0.0, 0.6, k * k)) * (k * 6.0 + 0.4)


## Sparkle of condensed contents (volume-weighted, solids included).
func get_glitter() -> float:
	# A few percent of flakes already looks very sparkly: perceived glitter saturates fast.
	return clampf(_condensed_weighted(_glitter) * 8.0, 0.0, 1.0)


func get_magnetic() -> float:
	return _condensed_weighted(_magnetic)


## Smell: odorous species present plus the lingering memory of released gas.
func get_odor() -> float:
	return clampf(_condensed_weighted(_odor) + odor_memory, 0.0, 1.0)


func _condensed_weighted(values: PackedFloat64Array) -> float:
	var total_m3: float = 0.0
	var acc: float = 0.0
	for i: int in species_count:
		if moles[i] <= 0.0:
			continue
		var v: float = moles[i] * (1.0 - _boil_fraction(i, temperature_kelvin)) * _molar_mass_kg_mol[i] / _density_kg_m3[i]
		acc += values[i] * v
		total_m3 += v
	return acc / total_m3 if total_m3 > 0.0 else 0.0


## Liquid volume of one miscibility group (0 aqueous, 1 oil, 2 liquid metal).
func get_group_volume_m3(group: int) -> float:
	var total: float = 0.0
	for i: int in species_count:
		if _group[i] == group:
			total += _species_phase_volume_m3(i, Phase.LIQUID)
	return total


func get_group_density_kg_m3(group: int) -> float:
	var v_total: float = 0.0
	var m_total: float = 0.0
	for i: int in species_count:
		if _group[i] == group:
			var v: float = _species_phase_volume_m3(i, Phase.LIQUID)
			v_total += v
			m_total += v * _density_kg_m3[i]
	return m_total / v_total if v_total > 0.0 else 0.0


## Colour of one liquid group (-1 = all condensed), or of the solids (solids_only).
func get_layer_color(group: int, solids_only: bool = false) -> Color:
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	var a: float = 0.0
	var total_m3: float = 0.0
	var weight_total: float = 0.0
	var ph_t: float = -1.0
	for i: int in species_count:
		if moles[i] <= 0.0:
			continue
		var v: float
		if solids_only:
			v = _species_phase_volume_m3(i, Phase.SOLID)
		elif group >= 0:
			if _group[i] != group:
				continue
			v = _species_phase_volume_m3(i, Phase.LIQUID)
		else:
			v = moles[i] * (1.0 - _boil_fraction(i, temperature_kelvin)) * _molar_mass_kg_mol[i] / _density_kg_m3[i]
		if v <= 0.0:
			continue
		var c: Color = _albedo[i]
		if _indicator[i] > 0.0:
			if ph_t < 0.0:
				ph_t = get_ph() / 14.0
			# Typical indicator windows: acid colour below ~pH 5, base colour above ~pH 9.
			if ph_t < 0.5:
				c = _indicator_acid[i].lerp(c, smoothstep(0.3, 0.46, ph_t))
			else:
				c = c.lerp(_indicator_base[i], smoothstep(0.54, 0.66, ph_t))
			v *= 1.0 + 20.0 * _indicator[i]
		if _thermo[i] > 0.0:
			var tt: float = clampf((temperature_kelvin - _thermo_cold_k[i]) / maxf(_thermo_hot_k[i] - _thermo_cold_k[i], 1.0), 0.0, 1.0)
			c = _thermo_cold[i].lerp(c, smoothstep(0.0, 0.5, tt)) if tt < 0.5 else c.lerp(_thermo_hot[i], smoothstep(0.5, 1.0, tt))
			v *= 1.0 + 20.0 * _thermo[i]
		var w: float = v * (0.04 + c.a * c.a)
		r += c.r * w
		g += c.g * w
		b += c.b * w
		a += c.a * v
		total_m3 += v
		weight_total += w
	if total_m3 <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	return Color(r / weight_total, g / weight_total, b / weight_total, a / total_m3)


## Acidity proxy on a 0-14 scale from the excess of acid over base strength.
func get_ph() -> float:
	var acid: float = 0.0
	var base: float = 0.0
	var total: float = 0.0
	for i: int in species_count:
		var n: float = moles[i] * (1.0 - _boil_fraction(i, temperature_kelvin))
		acid += n * _acid_strength[i]
		base += n * _base_strength[i]
		total += n
	if total <= 0.0:
		return 7.0
	return clampf(7.0 + 7.0 * tanh((base - acid) / total * 12.0), 0.0, 14.0)


## Liquid-volume-weighted surfactant strength and foam stability.
func get_foaming() -> float:
	return _liquid_weighted(_foaming)


func get_foam_stability() -> float:
	return _liquid_weighted(_foam_stability)


## Crosslink gel index (0 = runny, ~0.5+ = slime).
func get_gel_index() -> float:
	return sqrt(_liquid_weighted(_crosslink) * _liquid_weighted(_crosslinker))


func _liquid_weighted(values: PackedFloat64Array) -> float:
	var total_m3: float = 0.0
	var acc: float = 0.0
	for i: int in species_count:
		var v: float = _species_phase_volume_m3(i, Phase.LIQUID)
		acc += values[i] * v
		total_m3 += v
	return acc / total_m3 if total_m3 > 0.0 else 0.0


func _condensed_moles(index: int, t_kelvin: float) -> float:
	return moles[index] * (1.0 - _boil_fraction(index, t_kelvin))


## Convert `amount` moles of species `index` into its declared products at
## temperature T, conserving mass and carrying sensible+latent enthalpy across.
## Returns the enthalpy change (J) caused by the conversion.
## table: 0 = reaction_products, 1 = redox_products, 2 = complex_products.
func _consume(index: int, amount: float, t_kelvin: float, table: int = 0) -> float:
	return _convert(index, amount, index, t_kelvin, table)


## Consume `source` but distribute its mass through `owner`'s complex table (ligands).
func _consume_into(source: int, amount: float, owner: int, t_kelvin: float) -> float:
	return _convert(source, amount, owner, t_kelvin, 2)


func _convert(index: int, amount: float, owner: int, t_kelvin: float, table: int) -> float:
	var amt: float = minf(amount, moles[index])
	if amt <= 0.0:
		return 0.0
	var starts: PackedInt32Array = _product_start if table == 0 else (_rx_start if table == 1 else _cx_start)
	var idx: PackedInt32Array = _product_index if table == 0 else (_rx_index if table == 1 else _cx_index)
	var frac: PackedFloat64Array = _product_fraction if table == 0 else (_rx_fraction if table == 1 else _cx_fraction)
	if starts[owner + 1] == starts[owner]:
		return 0.0
	var mass_kg: float = amt * _molar_mass_kg_mol[index]
	moles[index] -= amt
	var delta_h: float = -mass_kg * specific_enthalpy_j_kg(index, t_kelvin)
	for k: int in range(starts[owner], starts[owner + 1]):
		var p: int = idx[k]
		var product_mass: float = mass_kg * frac[k]
		moles[p] += product_mass / _molar_mass_kg_mol[p]
		delta_h += product_mass * specific_enthalpy_j_kg(p, t_kelvin)
		if _odor[p] > 0.0:
			odor_memory = minf(odor_memory + product_mass * _odor[p] * 400.0, 1.0)
	enthalpy_joules += delta_h
	return delta_h


# --- Thermodynamic curve --------------------------------------------------------

func specific_enthalpy_j_kg(index: int, t_kelvin: float) -> float:
	return (_specific_heat_j_kg_k[index] * t_kelvin
		+ _latent_fusion_j_kg[index] * _melt_fraction(index, t_kelvin)
		+ _latent_vapor_j_kg[index] * _boil_fraction(index, t_kelvin))


## Total enthalpy the current contents would have at temperature `t_kelvin`.
func enthalpy_at(t_kelvin: float) -> float:
	var total: float = 0.0
	for i: int in species_count:
		var n: float = moles[i]
		if n > 0.0:
			total += n * _molar_mass_kg_mol[i] * specific_enthalpy_j_kg(i, t_kelvin)
	return total


# --- Queries ------------------------------------------------------------------

func get_total_moles() -> float:
	var total: float = 0.0
	for i: int in species_count:
		total += moles[i]
	return total


func get_total_mass_kg() -> float:
	var total: float = 0.0
	for i: int in species_count:
		total += moles[i] * _molar_mass_kg_mol[i]
	return total


func get_heat_capacity_j_k() -> float:
	var total: float = 0.0
	for i: int in species_count:
		total += moles[i] * _molar_mass_kg_mol[i] * _specific_heat_j_kg_k[i]
	return total


func get_phase_fraction(index: int, phase: Phase) -> float:
	return _phase_fraction(index, phase, temperature_kelvin)


func get_liquid_volume_m3() -> float:
	return _phase_volume_m3(Phase.LIQUID)


func get_solid_volume_m3() -> float:
	return _phase_volume_m3(Phase.SOLID)


func get_gas_moles() -> float:
	var total: float = 0.0
	for i: int in species_count:
		total += moles[i] * _boil_fraction(i, temperature_kelvin)
	return total


## Volume-weighted colour of condensed contents (liquid + solid), with
## indicator and thermochromic dyes applied.
func get_contents_color() -> Color:
	return get_layer_color(-1)


## Mass-weighted HDR aura; dilution dims the glow.
func get_emission_hdr() -> Color:
	var mass_kg: float = get_total_mass_kg()
	if mass_kg < MIN_MASS_KG:
		return Color(0.0, 0.0, 0.0, 0.0)
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	for i: int in species_count:
		var w: float = minf(moles[i] * _molar_mass_kg_mol[i] / mass_kg * 8.0, 1.0)
		var c: Color = _emission[i]
		r += c.r * w
		g += c.g * w
		b += c.b * w
	return Color(r, g, b, 1.0)


func get_liquid_turbidity() -> float:
	var total_m3: float = 0.0
	var acc: float = 0.0
	for i: int in species_count:
		var v: float = _species_phase_volume_m3(i, Phase.LIQUID)
		acc += _turbidity[i] * v
		total_m3 += v
	return acc / total_m3 if total_m3 > 0.0 else 0.0


## Arrhenius log-mixing rule over liquid volume fractions: ln(eta) = sum(phi_i * ln(eta_i)).
func get_liquid_viscosity_pas() -> float:
	var total_m3: float = 0.0
	var acc: float = 0.0
	for i: int in species_count:
		var v: float = _species_phase_volume_m3(i, Phase.LIQUID)
		acc += _log_viscosity[i] * v
		total_m3 += v
	if total_m3 <= 0.0:
		return 0.001
	var shear_factor: float = 1.0 + SHEAR_GAIN * _liquid_weighted(_shear) * clampf(shear_rate, 0.0, 2.0)
	return exp(acc / total_m3 + GEL_EXPONENT * get_gel_index()) * shear_factor


func get_liquid_density_kg_m3() -> float:
	var total_m3: float = 0.0
	var total_kg: float = 0.0
	for i: int in species_count:
		var v: float = _species_phase_volume_m3(i, Phase.LIQUID)
		total_m3 += v
		total_kg += v * _density_kg_m3[i]
	return total_kg / total_m3 if total_m3 > 0.0 else 1000.0


## Mass-weighted gravity coupling (1 = normal weight, <0 = levitating).
func get_gravity_coupling() -> float:
	var mass_kg: float = get_total_mass_kg()
	if mass_kg < MIN_MASS_KG:
		return 1.0
	var acc: float = 0.0
	for i: int in species_count:
		acc += moles[i] * _molar_mass_kg_mol[i] * _gravity_coupling[i]
	return acc / mass_kg


## Vapour pressure of the condensed contents (Raoult's law over the
## Clausius-Clapeyron pure-component pressures, anchored at 101.325 kPa at
## each species' boiling point). Dissolved salts barely evaporate, so they
## dilute and lower the water's pressure, just like real brine.
func get_vapor_pressure_kpa() -> float:
	var t: float = clampf(temperature_kelvin, SimConstants.MIN_TEMP_KELVIN, SimConstants.MAX_TEMP_KELVIN)
	var condensed_mol: float = 0.0
	var acc_kpa: float = 0.0
	for i: int in species_count:
		if moles[i] <= 0.0:
			continue
		var n_cond: float = moles[i] * (1.0 - _boil_fraction(i, t))
		if n_cond <= 0.0:
			continue
		condensed_mol += n_cond
		var l_molar: float = maxf(_latent_vapor_j_kg[i] * _molar_mass_kg_mol[i], 1000.0)
		var exponent: float = clampf(l_molar / SimConstants.GAS_CONSTANT_J_MOL_K * (1.0 / _boiling_point_kelvin[i] - 1.0 / t), -60.0, 3.0)
		acc_kpa += n_cond * 101.325 * exp(exponent)
	return acc_kpa / condensed_mol if condensed_mol > 0.0 else 0.0


## Lowest flash point among flammable species present above ~5% (NAN if none).
func get_flash_point_kelvin() -> float:
	var total: float = maxf(get_total_moles(), 1e-12)
	var lowest: float = NAN
	for i: int in species_count:
		if moles[i] / total < 0.05 or _combustion_j_kg[i] >= 0.0:
			continue
		if is_nan(lowest) or _flash_kelvin[i] < lowest:
			lowest = _flash_kelvin[i]
	return lowest


func get_total_thaums() -> float:
	var total: float = 0.0
	for i: int in species_count:
		total += moles[i] * _thaums_per_mol[i]
	return total


# --- Internals ----------------------------------------------------------------

func _melt_fraction(index: int, t_kelvin: float) -> float:
	return clampf((t_kelvin - _melting_point_kelvin[index]) / PHASE_BAND_KELVIN + 0.5, 0.0, 1.0)


func _boil_fraction(index: int, t_kelvin: float) -> float:
	return clampf((t_kelvin - _boiling_point_kelvin[index]) / PHASE_BAND_KELVIN + 0.5, 0.0, 1.0)


func _phase_fraction(index: int, phase: Phase, t_kelvin: float) -> float:
	var melt: float = _melt_fraction(index, t_kelvin)
	var boil: float = _boil_fraction(index, t_kelvin)
	match phase:
		Phase.SOLID:
			return 1.0 - melt
		Phase.LIQUID:
			return maxf(melt - boil, 0.0)
		_:
			return boil


## Specific enthalpy of a species held entirely in one phase at T.
func _phase_specific_enthalpy_j_kg(index: int, phase: Phase, t_kelvin: float) -> float:
	var sensible: float = _specific_heat_j_kg_k[index] * t_kelvin
	match phase:
		Phase.SOLID:
			return sensible
		Phase.LIQUID:
			return sensible + _latent_fusion_j_kg[index]
		_:
			return sensible + _latent_fusion_j_kg[index] + _latent_vapor_j_kg[index]


func _species_phase_volume_m3(index: int, phase: Phase) -> float:
	return moles[index] * _phase_fraction(index, phase, temperature_kelvin) * _molar_mass_kg_mol[index] / _density_kg_m3[index]


func _phase_volume_m3(phase: Phase) -> float:
	var total: float = 0.0
	for i: int in species_count:
		total += _species_phase_volume_m3(i, phase)
	return total


## Move `fraction` of one phase into dst (null = leaves the system), carrying
## that phase's own specific enthalpy. Returns moved mass in kg.
func _move_phase(dst: MixtureContainer, phase: Phase, fraction: float) -> float:
	last_transfer_enthalpy_joules = 0.0
	if fraction <= 0.0:
		return 0.0
	var t: float = temperature_kelvin
	var moved_mass_kg: float = 0.0
	var moved_enthalpy: float = 0.0
	for i: int in species_count:
		var amount: float = moles[i] * _phase_fraction(i, phase, t) * fraction
		if amount <= 0.0:
			continue
		var mass_kg: float = amount * _molar_mass_kg_mol[i]
		moles[i] = maxf(moles[i] - amount, 0.0)
		moved_mass_kg += mass_kg
		moved_enthalpy += mass_kg * _phase_specific_enthalpy_j_kg(i, phase, t)
		if dst != null:
			dst.moles[i] += amount
	if moved_mass_kg <= 0.0:
		return 0.0
	enthalpy_joules -= moved_enthalpy
	last_transfer_enthalpy_joules = moved_enthalpy
	if dst != null:
		dst.enthalpy_joules += moved_enthalpy
		dst._solve_temperature()
	_solve_temperature()
	return moved_mass_kg


## Invert the strictly rising h(T) curve by bisection (fixed iteration count).
func _solve_temperature() -> void:
	if get_total_mass_kg() < MIN_MASS_KG:
		return
	if is_nan(enthalpy_joules) or is_inf(enthalpy_joules):
		var reset_h: float = enthalpy_at(SimConstants.AMBIENT_TEMP_KELVIN)
		clamp_correction_joules += reset_h - (0.0 if is_nan(enthalpy_joules) else enthalpy_joules)
		enthalpy_joules = reset_h
		temperature_kelvin = SimConstants.AMBIENT_TEMP_KELVIN
		return
	var h_lo: float = enthalpy_at(SimConstants.MIN_TEMP_KELVIN)
	if enthalpy_joules <= h_lo:
		clamp_correction_joules += h_lo - enthalpy_joules
		enthalpy_joules = h_lo
		temperature_kelvin = SimConstants.MIN_TEMP_KELVIN
		return
	var h_hi: float = enthalpy_at(SimConstants.MAX_TEMP_KELVIN)
	if enthalpy_joules >= h_hi:
		clamp_correction_joules += h_hi - enthalpy_joules
		enthalpy_joules = h_hi
		temperature_kelvin = SimConstants.MAX_TEMP_KELVIN
		return
	var lo: float = SimConstants.MIN_TEMP_KELVIN
	var hi: float = SimConstants.MAX_TEMP_KELVIN
	for _iter: int in BISECTION_ITERATIONS:
		var mid: float = 0.5 * (lo + hi)
		if enthalpy_at(mid) < enthalpy_joules:
			lo = mid
		else:
			hi = mid
	temperature_kelvin = 0.5 * (lo + hi)
