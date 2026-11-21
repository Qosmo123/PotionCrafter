class_name SafetySheet
extends RefCounted
## Builds a WHMIS 2015 / GHS-style Safety Data Sheet for any mixture, derived
## purely from its property vector (never written per potion): hazard classes
## and pictograms, signal word, hazard + precaution statements, composition
## with CAS numbers, physical properties (measured values from the science
## bench when available), live reactions, and, for the kid-themed
## ingredients, a "Silly Hazards" section of property-driven jokes.

enum Pictogram { FLAME, FLAME_OVER_CIRCLE, SKULL, CORROSION, HEALTH, EXCLAMATION, ENVIRONMENT, GAS_CYLINDER, ARCANE, SILLY }
const PICTOGRAM_NAMES: PackedStringArray = ["Flammable", "Oxidizer", "Acute toxicity", "Corrosive", "Health hazard",
	"Irritant", "Environment", "Gas / cryogenic", "Arcane energy", "Silly hazard"]
const FUN_SHELVES: PackedStringArray = ["Spooky", "Slime Lab", "Space", "Candy Shop", "Hero Lab", "Movie Magic", "Fairy Tale", "Under the Sea"]


## {name, formula, signal, pictograms:[int], hazards:[str], precautions:[str],
##  composition:[[name, formula, cas, mass%]], first_aid:[str], fire:[str],
##  properties:[[label, value, measured]], reactions:[str], toxicology:[str],
##  silly:[str], label_notes:[str], kid:bool}
static func build(m: MixtureContainer, product_name: String = "", foam_height_m: float = 0.0, assay: Dictionary = {}) -> Dictionary:
	var sheet: Dictionary = {}
	sheet["name"] = product_name if product_name != "" else PotionNamer.name_for(m, foam_height_m)
	sheet["formula"] = PotionNamer.formula_for(m, 4)
	var total_kg: float = maxf(m.get_total_mass_kg(), 1e-12)
	var ph: float = m.get_ph()
	var flash_k: float = m.get_flash_point_kelvin()
	var tox: float = m.hazard_level(&"toxicity")
	var health: float = m.hazard_level(&"health")
	var env: float = m.hazard_level(&"environment")
	var oxid: float = m.hazard_level(&"oxidizer")
	var flam: float = m.hazard_level(&"flammable")
	var thaums_per_kg: float = m.get_total_thaums() / total_kg

	# --- Composition (by mass), and whether this is a kid-themed potion.
	var comp: Array = []
	var kid: bool = false
	var label_notes: PackedStringArray = PackedStringArray()
	var order: Array = []
	for i: int in m.species_count:
		if m.moles[i] > 0.0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _mass(m, a) > _mass(m, b))
	for i: int in order:
		var s: SubstanceData = SubstanceRegistry.get_substance(i)
		var pct: float = _mass(m, i) / total_kg * 100.0
		if pct < 0.05 and comp.size() >= 6:
			continue
		comp.append([s.display_name, s.chemical_formula, s.cas_number if s.cas_number != "" else ("n/a (arcane)" if s.thaumic_density_thaums_mol > 0.0 else "—"), pct])
		if s.shelf in FUN_SHELVES:
			kid = true
			if s.description != "" and label_notes.size() < 3:
				label_notes.append("%s: %s" % [s.display_name, s.description])
	sheet["composition"] = comp
	sheet["kid"] = kid
	sheet["label_notes"] = label_notes

	# --- Hazard classification → pictograms.
	var pics: Array[int] = []
	var hazards: PackedStringArray = PackedStringArray()
	var precautions: PackedStringArray = PackedStringArray()
	var cold: bool = m.temperature_kelvin < 150.0
	if flam > 0.25 or (not is_nan(flash_k) and flash_k < 333.0):
		pics.append(Pictogram.FLAME)
		if not is_nan(flash_k) and flash_k < 296.0:
			hazards.append("Highly flammable liquid and vapour (flash point %.0f °C)." % (flash_k - 273.15))
		else:
			hazards.append("Flammable liquid and vapour.")
		precautions.append("Keep away from heat, sparks, open flames and hot surfaces. No smoking (or dragons).")
	if oxid > 0.25:
		pics.append(Pictogram.FLAME_OVER_CIRCLE)
		hazards.append("May intensify fire; oxidizer.")
		precautions.append("Keep away from fuels, sugar, metal powders and anything that burns.")
	if tox > 0.6:
		pics.append(Pictogram.SKULL)
		hazards.append("Toxic if swallowed or inhaled.")
		precautions.append("Do not eat, drink or taste anything in the lab. Wash hands after handling.")
	if ph < 2.0 or ph > 12.0:
		pics.append(Pictogram.CORROSION)
		hazards.append("Causes severe skin burns and eye damage (pH %.1f)." % ph)
		precautions.append("Wear gloves, goggles and a lab coat. Always add acid to water, never water to acid.")
	if health > 0.5:
		pics.append(Pictogram.HEALTH)
		hazards.append("May cause damage to organs through prolonged exposure.")
		precautions.append("Do not breathe dust, fume or vapour. Use in a fume hood.")
	# GHS: the exclamation mark is not shown alongside corrosion or the skull.
	if not pics.has(Pictogram.CORROSION) and not pics.has(Pictogram.SKULL) and ((ph < 4.0 and ph >= 2.0) or (ph > 10.0 and ph <= 12.0) or (tox > 0.25 and tox <= 0.6)):
		pics.append(Pictogram.EXCLAMATION)
		hazards.append("Causes skin and eye irritation.")
		precautions.append("Rinse skin with plenty of water after contact.")
	if env > 0.4:
		pics.append(Pictogram.ENVIRONMENT)
		hazards.append("Toxic to aquatic life with long-lasting effects.")
		precautions.append("Never pour down the sink. Collect in a labelled waste jar.")
	if cold or m.gas_generation_mol_s > 0.02:
		pics.append(Pictogram.GAS_CYLINDER)
		hazards.append("Contains refrigerated liquefied gas; may cause cryogenic burns." if cold else "Releases gas rapidly; pressure builds in sealed containers.")
		precautions.append("Never cork a fizzing vessel. Handle cryogens with insulated gloves." if cold else "Never cork a fizzing vessel.")
	if thaums_per_kg > 200.0:
		pics.append(Pictogram.ARCANE)
		hazards.append("Arcane energy %.0f thaums/kg: may cause spontaneous sparkles or mild levitation." % thaums_per_kg)
		precautions.append("Keep inside a chalk warding circle when not in use.")
	if kid:
		pics.append(Pictogram.SILLY)
	sheet["pictograms"] = pics
	var danger: bool = pics.has(Pictogram.SKULL) or pics.has(Pictogram.CORROSION) or pics.has(Pictogram.HEALTH) or (not is_nan(flash_k) and flash_k < 296.0)
	var warning: bool = not pics.is_empty() and not (pics.size() == 1 and pics[0] == Pictogram.SILLY)
	sheet["signal"] = "DANGER" if danger else ("WARNING" if warning else ("SILLY" if kid else "NONE"))
	if hazards.is_empty():
		hazards.append("Not classified as hazardous under WHMIS 2015.")
		precautions.append("Normal lab care: goggles on, no tasting, label everything.")
	sheet["hazards"] = hazards
	sheet["precautions"] = precautions

	# --- First aid / fire.
	var aid: PackedStringArray = PackedStringArray()
	aid.append("Eyes: rinse cautiously with water for 15 minutes; remove contact lenses.")
	if ph < 4.0 or ph > 10.0:
		aid.append("Skin: remove contaminated clothing and rinse skin under running water.")
	if tox > 0.25:
		aid.append("If swallowed: rinse mouth. Do NOT induce vomiting. Call Poison Control.")
	if cold:
		aid.append("Frostbite: warm gently with lukewarm water, never rub.")
	aid.append("If you feel unwell, tell a grown-up / lab supervisor right away.")
	sheet["first_aid"] = aid
	var fire: PackedStringArray = PackedStringArray()
	if pics.has(Pictogram.FLAME):
		var fc: Color = m.get_flame_color()
		fire.append("Burns with a %s flame. Smother with a lid or use CO₂ / dry powder." % _color_word(fc))
	else:
		fire.append("Not flammable. Use any extinguisher suitable for surrounding fire.")
	if oxid > 0.25:
		fire.append("Oxidizer: feeds fires with oxygen. Flood with water.")
	sheet["fire"] = fire

	# --- Physical properties (measured on the science bench where possible).
	var props: Array = []
	var color: Color = m.get_contents_color()
	props.append(["Appearance", "%s %s" % [_color_word(color), "liquid" if m.get_liquid_volume_m3() > m.get_solid_volume_m3() else "solid"], false])
	props.append(["Odour", _odor_word(m.get_odor()), false])
	props.append(["pH", "%.1f" % float(assay.get("ph", ph)), assay.has("measured_hydrometer")])
	props.append(["Density", "%.3f g/mL" % (float(assay.get("density_kg_m3", m.get_liquid_density_kg_m3())) / 1000.0), assay.has("measured_hydrometer")])
	var mu: float = float(assay.get("viscosity_pas", m.get_liquid_viscosity_pas()))
	props.append(["Viscosity", "%s (%s)" % [LabAssay.format_viscosity(mu), LabAssay.describe(mu, LabAssay.VISCOSITY_LANDMARKS)], assay.has("measured_viscometer")])
	var vp: float = float(assay.get("vapor_kpa", m.get_vapor_pressure_kpa()))
	props.append(["Vapour pressure", "%.1f kPa  · volatility %s" % [vp, LabAssay.describe(vp, LabAssay.VOLATILITY_LANDMARKS)], assay.has("measured_volatility")])
	props.append(["Flash point", "none" if is_nan(flash_k) else "%.0f °C" % (flash_k - 273.15), assay.has("measured_volatility")])
	if assay.has("air_fraction"):
		props.append(["Air content", "%.0f %%" % (float(assay["air_fraction"]) * 100.0), assay.has("measured_air_meter")])
	props.append(["Temperature", "%.1f °C" % (m.temperature_kelvin - 273.15), false])
	if thaums_per_kg > 0.0:
		props.append(["Thaumic density", "%.0f thaums/kg" % thaums_per_kg, false])
	sheet["properties"] = props

	# --- Stability & reactivity.
	var rx: PackedStringArray = PotionNamer.equations_for(m)
	if rx.is_empty():
		rx.append("Stable under normal lab conditions. No reactions in progress.")
	sheet["reactions"] = rx
	var toxi: PackedStringArray = PackedStringArray()
	toxi.append("Acute toxicity: %s." % ("high" if tox > 0.6 else ("moderate" if tox > 0.25 else "low")))
	toxi.append("Chronic / organ hazard: %s." % ("yes" if health > 0.5 else "not expected"))
	toxi.append("Environmental hazard: %s." % ("yes, do not release" if env > 0.4 else "low"))
	sheet["toxicology"] = toxi
	sheet["silly"] = silly_hazards(m, foam_height_m) if kid else PackedStringArray()
	return sheet


static func _mass(m: MixtureContainer, i: int) -> float:
	return m.moles[i] * SubstanceRegistry.get_substance(i).molar_mass_kg_mol


## Joke warnings for kid potions, chosen by the mixture's own numbers.
static func silly_hazards(m: MixtureContainer, foam_height_m: float) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if m.get_spookiness() > 0.15:
		out.append("May attract friendly ghosts. Do not let them borrow your homework.")
	if m.get_gel_index() > 0.3 or m.get_liquid_viscosity_pas() > 20.0:
		out.append("Extremely sticky. Keep away from hair, pets, carpets and little brothers.")
	if m.get_odor() > 0.4:
		out.append("Smells like a troll's sock drawer. Open a window. Maybe two.")
	if m.get_glitter() > 0.2:
		out.append("Contains glitter. Glitter is forever. You will find it in your sandwich next year.")
	if m.get_electric() > 0.15:
		out.append("Static charge: hair may stand straight up. Great for photos.")
	if m.get_rainbow() > 0.15:
		out.append("May cause spontaneous rainbows. Unicorns not included.")
	if m.get_gravity_coupling() < 0.8:
		out.append("Lighter than it should be. Tie the bottle to the table so it doesn't float off.")
	if foam_height_m > 0.01 or m.get_foaming() > 0.3:
		out.append("Foams. A LOT. Use a bigger bucket than you think.")
	if m.gas_generation_mol_s > 0.002:
		out.append("Fizzes like an angry soda. Point away from your face and your teacher.")
	if m.get_emission_hdr().get_luminance() > 0.1:
		out.append("Glows in the dark. Not recommended as a night-light for nervous goblins.")
	if m.temperature_kelvin > 330.0:
		out.append("Toasty hot! Let it cool before you hold it, unless you are a dragon.")
	elif m.temperature_kelvin < 270.0:
		out.append("Brain-freeze cold. Penguins approve.")
	if m.get_magnetic() > 0.1:
		out.append("Magnetic: paperclips may follow you home.")
	if out.is_empty():
		out.append("Mostly harmless. May cause mild giggling.")
	return out


static func _color_word(c: Color) -> String:
	if c.v < 0.15:
		return "black"
	if c.s < 0.12:
		return "white" if c.v > 0.8 else ("grey" if c.v > 0.35 else "dark grey")
	var h: float = c.h * 360.0
	var words: Array = [[15, "red"], [40, "orange"], [65, "yellow"], [160, "green"], [200, "teal"], [250, "blue"], [290, "violet"], [335, "pink"], [361, "red"]]
	for pair: Array in words:
		if h < float(pair[0]):
			return ("pale " if c.s < 0.35 else "") + String(pair[1])
	return "red"


static func _odor_word(o: float) -> String:
	if o < 0.05:
		return "odourless"
	if o < 0.3:
		return "faint"
	if o < 0.6:
		return "strong"
	return "overpowering (stinky!)"
