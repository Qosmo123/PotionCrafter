class_name PotionNamer
extends RefCounted
## Procedural nomenclature from a mixture's property vectors (no lookup of
## named recipes). Adjectives come from the strongest emergent traits, the noun
## from texture, and the "of ..." clause from the dominant arcane axis.
## Called from UI code a few times per second, never from the physics tick.

const MIN_ML: float = 0.5


static func name_for(mixture: MixtureContainer, foam_height_meters: float) -> String:
	var volume_ml: float = mixture.get_liquid_volume_m3() * 1e6
	if volume_ml < MIN_ML:
		return "Empty"
	var traits: Array[String] = []
	var ph: float = mixture.get_ph()
	var viscosity: float = mixture.get_liquid_viscosity_pas()
	var gel: float = mixture.get_gel_index()
	var aura: Color = mixture.get_emission_hdr()
	var glow: float = aura.r + aura.g + aura.b
	if mixture.gas_generation_mol_s > 0.002:
		traits.append("Effervescent")
	if mixture.arcane_flash > 0.05:
		traits.append("Flaring")
	if foam_height_meters > 0.004:
		traits.append("Frothing")
	if ph < 4.0:
		traits.append("Caustic")
	elif ph > 10.0:
		traits.append("Alkaline")
	if glow > 1.2:
		traits.append("Radiant")
	elif glow > 0.3:
		traits.append("Glimmering")
	if mixture.temperature_kelvin > 340.0:
		traits.append("Seething")
	elif mixture.temperature_kelvin < 278.0:
		traits.append("Frigid")

	var noun: String = "Draught"
	if gel > 0.35 or viscosity > 4.0:
		noun = "Slime" if gel > 0.35 else "Ichor"
	elif mixture.get_foaming() > 0.4 and mixture.get_foam_stability() > 0.1:
		noun = "Bubble Philtre"
	elif viscosity > 0.5:
		noun = "Syrup"
	elif mixture.get_total_thaums() / maxf(mixture.get_total_moles(), 1e-9) > 8.0:
		noun = "Elixir"
	elif ph < 5.0:
		noun = "Vitriol"
	elif ph > 9.0:
		noun = "Lye"

	var clause: String = _arcane_clause(mixture)
	var title: String = noun
	if traits.size() > 0:
		title = " ".join(traits.slice(0, 2)) + " " + noun
	if clause != "":
		title += " of " + clause
	return "%s [%s]" % [title, grade_for(mixture)]


## S..F grade from purity (dominant share), leftover reactive acid/base, and heat stress.
static func grade_for(mixture: MixtureContainer) -> String:
	var total: float = mixture.get_total_moles()
	if total <= 0.0:
		return "-"
	var dominant: float = 0.0
	for i: int in mixture.species_count:
		dominant = maxf(dominant, mixture.moles[i] / total)
	var ph_stress: float = absf(mixture.get_ph() - 7.0) / 7.0
	var thermal_stress: float = clampf(absf(mixture.temperature_kelvin - 293.15) / 120.0, 0.0, 1.0)
	var score: float = dominant * 0.55 + (1.0 - ph_stress) * 0.25 + (1.0 - thermal_stress) * 0.2
	if mixture.arcane_flash > 0.05 or mixture.gas_generation_mol_s > 0.002:
		score -= 0.15  # still reacting: unstable
	if score > 0.9:
		return "S"
	if score > 0.78:
		return "A"
	if score > 0.65:
		return "B"
	if score > 0.52:
		return "C"
	if score > 0.4:
		return "D"
	return "F"


## Composition line: chemical formulas with mole percentages, largest first.
static func formula_for(mixture: MixtureContainer, max_terms: int = 3) -> String:
	var total: float = mixture.get_total_moles()
	if total <= 0.0:
		return ""
	var order: Array[int] = []
	for i: int in mixture.species_count:
		if mixture.moles[i] / total > 0.005:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return mixture.moles[a] > mixture.moles[b])
	var parts: PackedStringArray = PackedStringArray()
	for k: int in mini(order.size(), max_terms):
		var s: SubstanceData = SubstanceRegistry.get_substance(order[k])
		parts.append("%s %d%%" % [s.chemical_formula, int(round(mixture.moles[order[k]] / total * 100.0))])
	return " · ".join(parts)


## Live reaction equations, written from the species actually reacting this tick.
static func equations_for(mixture: MixtureContainer) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for key: int in mixture.active_reaction_pairs:
		var a: SubstanceData = SubstanceRegistry.get_substance(key / 1024)
		var b: SubstanceData = SubstanceRegistry.get_substance(key % 1024)
		var products: PackedStringArray = PackedStringArray()
		var sources: Array[SubstanceData] = [a] if a == b else [a, b]
		for src: SubstanceData in sources:
			for p: Resource in src.reaction_products:
				var ps: SubstanceData = p as SubstanceData
				var label: String = ps.chemical_formula + ("↑" if ps.boiling_point_kelvin < mixture.temperature_kelvin else "")
				if not products.has(label):
					products.append(label)
		if a != b:
			lines.append("%s + %s → %s" % [a.chemical_formula, b.chemical_formula, " + ".join(products)])
		elif a.combustion_enthalpy_j_kg < 0.0 and mixture.burning:
			lines.append("%s + O₂ → %s  🔥" % [a.chemical_formula, " + ".join(products)])
		elif a.transmutation_valence > 0.0:
			lines.append("%s —(Æ, Δ)→ %s  ✦" % [a.chemical_formula, " + ".join(products)])
		else:
			lines.append("%s → %s" % [a.chemical_formula, " + ".join(products)])
	return lines


static func _arcane_clause(mixture: MixtureContainer) -> String:
	var mass: float = mixture.get_total_mass_kg()
	if mass <= 0.0:
		return ""
	var coupling: float = mixture.get_gravity_coupling()
	var best: String = ""
	var best_score: float = 0.12
	if 1.0 - coupling > best_score:
		best_score = 1.0 - coupling
		best = "Buoyant Ascension" if coupling < 0.0 else "Feathered Lightness"
	var vitality: float = _weighted(mixture, &"vitality_resonance")
	if vitality > best_score:
		best_score = vitality
		best = "Verdant Regeneration"
	var chronal: float = _weighted(mixture, &"chronal_dilation")
	if chronal > best_score:
		best_score = chronal
		best = "Lingering Stasis"
	var polarity: float = _weighted(mixture, &"polarity_charge")
	if absf(polarity) > best_score:
		best = "Kindled Embers" if polarity > 0.0 else "Lunar Stillness"
	return best


static func _weighted(mixture: MixtureContainer, property: StringName) -> float:
	var total: float = mixture.get_total_mass_kg()
	if total <= 0.0:
		return 0.0
	var acc: float = 0.0
	for i: int in mixture.species_count:
		var s: SubstanceData = SubstanceRegistry.get_substance(i)
		acc += mixture.moles[i] * s.molar_mass_kg_mol * (s.get(property) as float)
	return acc / total
