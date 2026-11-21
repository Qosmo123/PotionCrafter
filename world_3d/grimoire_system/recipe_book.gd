class_name RecipeBook
extends Node
## Loads every RecipeData in content/recipes/, watches all vessels a few times
## a second, and records discoveries when a vessel's measured traits fall
## inside a recipe's signature. Discoveries persist in user://grimoire.cfg.

signal recipe_discovered(recipe: RecipeData, vessel: Vessel3D)

const RECIPE_DIR: String = "res://content/recipes/"
const SAVE_PATH: String = "user://grimoire.cfg"
const CHECK_INTERVAL_SECONDS: float = 0.5

static var instance: RecipeBook = null

@export var persist: bool = true

var recipes: Array[RecipeData] = []
var discovered: Dictionary = {}
var last_discovery_text: String = ""
var _timer: float = 0.0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	recipes = load_all()
	# Headless tools/tests run without a current scene: never touch the player's save.
	# Tools, tests and demo renders (launch args) never touch the player save.
	if get_tree().current_scene == null or not OS.get_cmdline_user_args().is_empty():
		persist = false
	if persist:
		var cfg: ConfigFile = ConfigFile.new()
		if cfg.load(SAVE_PATH) == OK:
			for key: String in cfg.get_section_keys("discovered") if cfg.has_section("discovered") else PackedStringArray():
				discovered[StringName(key)] = true


static func load_all() -> Array[RecipeData]:
	var out: Array[RecipeData] = []
	var files: PackedStringArray = DirAccess.get_files_at(RECIPE_DIR)
	files.sort()
	for file_name: String in files:
		var path: String = file_name.trim_suffix(".remap")
		if path.ends_with(".tres"):
			var recipe: RecipeData = load(RECIPE_DIR + path) as RecipeData
			if recipe != null:
				out.append(recipe)
	return out


func is_discovered(recipe: RecipeData) -> bool:
	return discovered.has(recipe.recipe_id)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL_SECONDS
	for vessel: Vessel3D in Vessel3D.all_vessels:
		if vessel.mixture == null or vessel.mixture.get_liquid_volume_m3() * 1e6 < 1.0:
			continue
		var traits: Dictionary = measure(vessel)
		for recipe: RecipeData in recipes:
			if not is_discovered(recipe) and matches(recipe, traits):
				_discover(recipe, vessel)


func _discover(recipe: RecipeData, vessel: Vessel3D) -> void:
	discovered[recipe.recipe_id] = true
	var prefix: String = "Secret recipe unlocked" if recipe.category == RecipeData.Category.SECRET else "Recipe discovered"
	last_discovery_text = "✦ %s: %s" % [prefix, recipe.title]
	recipe_discovered.emit(recipe, vessel)
	AudioHaptics.tick()
	if persist:
		var cfg: ConfigFile = ConfigFile.new()
		cfg.load(SAVE_PATH)
		cfg.set_value("discovered", String(recipe.recipe_id), Time.get_unix_time_from_system())
		cfg.save(SAVE_PATH)


static func matches(recipe: RecipeData, traits: Dictionary) -> bool:
	var n: int = mini(recipe.condition_traits.size(), mini(recipe.condition_min.size(), recipe.condition_max.size()))
	if n == 0:
		return false
	for i: int in n:
		var value: float = traits.get(recipe.condition_traits[i], 0.0)
		if value < recipe.condition_min[i] or value > recipe.condition_max[i]:
			return false
	return true


## Measured traits of a vessel's contents (all emergent quantities).
static func measure(vessel: Vessel3D) -> Dictionary:
	var traits: Dictionary = measure_mixture(vessel.mixture, vessel.foam_height_meters, vessel.is_boiling)
	var layers: int = 0
	for g: int in 3:
		if vessel.mixture.get_group_volume_m3(g) > 1e-7:
			layers += 1
	traits["layers"] = float(layers)
	traits["emulsion"] = vessel.emulsion_level
	traits["foam_overflow"] = vessel.foam_overflow_rate_m_s
	return traits


static func measure_mixture(m: MixtureContainer, foam_m: float, boiling: bool) -> Dictionary:
	var aura: Color = m.get_emission_hdr()
	var total: float = maxf(m.get_total_moles(), 1e-12)
	var traits: Dictionary = {
		"ph": m.get_ph(),
		"temperature_c": m.temperature_kelvin - 273.15,
		"viscosity_pas": m.get_liquid_viscosity_pas(),
		"gel": m.get_gel_index(),
		"glow": aura.r + aura.g + aura.b,
		"gravity_coupling": m.get_gravity_coupling(),
		"foaming": m.get_foaming(),
		"foam_stability": m.get_foam_stability(),
		"foam_m": foam_m,
		"gas_rate": m.gas_generation_mol_s,
		"flash": m.arcane_flash,
		"swirl": absf(m.swirl_rad_s),
		"thaums_per_mol": m.get_total_thaums() / total,
		"volume_ml": m.get_liquid_volume_m3() * 1e6,
		"boiling": 1.0 if boiling else 0.0,
		"burning": 1.0 if m.burning else 0.0,
		"spooky": m.get_spookiness(),
		"electric": m.get_electric(),
		"rainbow": m.get_rainbow(),
		"toxic": m.hazard_level(&"toxic"),
		"flame_r": m.get_flame_color().r,
		"flame_g": m.get_flame_color().g,
		"flame_b": m.get_flame_color().b,
		"glitter": m.get_glitter(),
		"odor": m.get_odor(),
		"magnetic": m.get_magnetic(),
		"precipitate_ml": m.get_solid_volume_m3() * 1e6,
		"transmuting": m.transmutation_rate_mol_s,
		"layers": 1.0,
	}
	for i: int in m.species_count:
		if m.moles[i] > 0.0:
			traits["fraction:" + String(SubstanceRegistry.get_substance(i).substance_id)] = m.moles[i] / total
	return traits
