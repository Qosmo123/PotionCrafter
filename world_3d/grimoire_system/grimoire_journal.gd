class_name GrimoireJournal
extends Node
## The alchemist's persistent record: details of every discovery (traits,
## temperature curve, grade, sigil seed), the cellar of bottled potions,
## coins, and the commission board. Saved to user://grimoire.cfg in the real
## game; headless tools/tests never touch the save.

signal changed
signal toast(text: String, kind: StringName)

const SAVE_PATH: String = "user://grimoire.cfg"
const GRADES: String = "SABCDF"
const MAX_CELLAR: int = 60
const ACTIVE_COMMISSIONS: int = 3
const RADAR_AXES: PackedStringArray = ["Acidity", "Heat", "Thickness", "Glow", "Buoyancy", "Arcana", "Fizz", "Foam"]

static var instance: GrimoireJournal = null

@export var persist: bool = true

## recipe_id -> {time, grade, vessel, traits: Dictionary, curve: PackedFloat32Array}
var discoveries: Dictionary = {}
## Bottled potions, newest first: {name, grade, formula, time, recipe_id, color}
var cellar: Array[Dictionary] = []
var coins: int = 0
## {recipe_id, title, min_grade, reward}
var commissions: Array[Dictionary] = []
## mineral_id -> {count, first_time, best_value, best_name}
var collection: Dictionary = {}
## Grimoire entries the player has opened ("recipe:<id>", "mineral:<id>" -> true),
## so newly unlocked pages can wear a NEW badge. Additive save key.
var seen: Dictionary = {}
## Recipe pinned to the bench as a floating formula card ("" = none). Additive save key.
var pinned_recipe: String = ""
## Faceting mastery: cut name -> {count, best}. Additive save key.
var cut_mastery: Dictionary = {}

const MASTERY_CUTS: int = 3
const MASTERY_QUALITY: float = 0.7
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	_rng.seed = int(Time.get_unix_time_from_system())
	# Tools, tests and demo renders (launch args) never touch the player save.
	if get_tree().current_scene == null or not OS.get_cmdline_user_args().is_empty():
		persist = false
	_load()
	if RecipeBook.instance != null:
		RecipeBook.instance.recipe_discovered.connect(_on_recipe_discovered)
	_refill_commissions.call_deferred()


# --- Discoveries ---------------------------------------------------------------------

func _on_recipe_discovered(recipe: RecipeData, vessel: Vessel3D) -> void:
	var traits: Dictionary = RecipeBook.measure(vessel)
	discoveries[String(recipe.recipe_id)] = {
		"time": Time.get_unix_time_from_system(),
		"grade": PotionNamer.grade_for(vessel.mixture),
		"vessel": vessel.name,
		"traits": radar_values(traits),
		"curve": vessel.get_temperature_history_celsius(),
	}
	var secret: bool = recipe.category == RecipeData.Category.SECRET
	toast.emit(("Secret recipe unlocked: " if secret else "Recipe learned: ") + recipe.title, &"secret" if secret else &"discovery")
	_save()
	changed.emit()


func discovery_of(recipe_id: StringName) -> Dictionary:
	return discoveries.get(String(recipe_id), {})


## Normalised 0..1 values for the radar chart axes.
static func radar_values(traits: Dictionary) -> PackedFloat32Array:
	var v: PackedFloat32Array = PackedFloat32Array()
	v.append(clampf(absf(traits.get("ph", 7.0) - 7.0) / 7.0, 0.0, 1.0))
	v.append(clampf(traits.get("temperature_c", 20.0) / 120.0, 0.0, 1.0))
	v.append(clampf((log(maxf(traits.get("viscosity_pas", 0.001), 1e-4)) / log(10.0) + 3.0) / 5.0, 0.0, 1.0))
	v.append(clampf(traits.get("glow", 0.0) / 2.5, 0.0, 1.0))
	v.append(clampf((1.0 - traits.get("gravity_coupling", 1.0)) / 1.6, 0.0, 1.0))
	v.append(clampf(traits.get("thaums_per_mol", 0.0) / 40.0, 0.0, 1.0))
	v.append(clampf(traits.get("gas_rate", 0.0) / 0.05 + traits.get("burning", 0.0) * 0.5, 0.0, 1.0))
	v.append(clampf(traits.get("foam_m", 0.0) / 0.03 + traits.get("foaming", 0.0) * 0.3, 0.0, 1.0))
	return v


## Deterministic shareable seed for a potion's trait signature (same traits ->
## same sigil on PC and Android). Format: XXXX-XXXX-XXXX.
static func sigil_seed(values: PackedFloat32Array) -> String:
	var text: String = ""
	for f: float in values:
		text += "%02d" % int(round(clampf(f, 0.0, 1.0) * 63.0))
	var h: String = text.sha256_text().to_upper()
	return "%s-%s-%s" % [h.substr(0, 4), h.substr(4, 4), h.substr(8, 4)]


# --- Bottling, cellar, commissions ------------------------------------------------------

## Record a freshly corked potion; completes any commission it satisfies.
func record_bottle(vessel: Vessel3D) -> Dictionary:
	var m: MixtureContainer = vessel.mixture
	var entry: Dictionary = {
		"name": PotionNamer.name_for(m, vessel.foam_height_meters),
		"grade": PotionNamer.grade_for(m),
		"formula": PotionNamer.formula_for(m),
		"time": Time.get_unix_time_from_system(),
		"recipe_id": "",
		"color": m.get_contents_color().to_html(),
		"volume_ml": m.get_liquid_volume_m3() * 1e6,
		"composition": composition_of(m),
		"temperature_k": m.temperature_kelvin,
		"assay": vessel.get_meta(&"assay", {}),
	}
	var traits: Dictionary = RecipeBook.measure(vessel)
	if RecipeBook.instance != null:
		for recipe: RecipeData in RecipeBook.instance.recipes:
			if RecipeBook.matches(recipe, traits):
				entry["recipe_id"] = String(recipe.recipe_id)
				break
	cellar.push_front(entry)
	if cellar.size() > MAX_CELLAR:
		cellar.resize(MAX_CELLAR)
	toast.emit("Bottled: %s" % entry["name"], &"bottle")
	_complete_commissions(traits, entry["grade"])
	_save()
	changed.emit()
	return entry


## Substance id -> moles, for rebuilding a bottled mixture later.
static func composition_of(m: MixtureContainer) -> Dictionary:
	var out: Dictionary = {}
	for i: int in m.species_count:
		if m.moles[i] > 1e-9:
			out[String(SubstanceRegistry.get_substance(i).substance_id)] = m.moles[i]
	return out


static func mixture_from(entry: Dictionary) -> MixtureContainer:
	var m: MixtureContainer = MixtureContainer.new()
	var comp: Dictionary = entry.get("composition", {})
	for id: String in comp:
		var idx: int = SubstanceRegistry.index_of_id(StringName(id))
		if idx >= 0:
			m.add_substance(idx, float(comp[id]), float(entry.get("temperature_k", SimConstants.AMBIENT_TEMP_KELVIN)))
	return m


static func grade_at_least(grade: String, minimum: String) -> bool:
	return GRADES.find(grade) >= 0 and GRADES.find(grade) <= GRADES.find(minimum)


func _complete_commissions(traits: Dictionary, grade: String) -> void:
	if RecipeBook.instance == null:
		return
	for i: int in range(commissions.size() - 1, -1, -1):
		var order: Dictionary = commissions[i]
		var recipe: RecipeData = _recipe(StringName(order["recipe_id"]))
		if recipe != null and RecipeBook.matches(recipe, traits) and grade_at_least(grade, order["min_grade"]):
			coins += int(order["reward"])
			toast.emit("Commission fulfilled: %s  +%d ◉" % [order["title"], order["reward"]], &"coins")
			commissions.remove_at(i)
	_refill_commissions()


## Three first commissions that teach the basics, offered once.
const TUTORIAL_ORDERS: Array = [
	["volcano_fizz", "The Apprentice's Volcano", "Lesson 1 · pour vinegar onto Salt of Soda, watch it foam, then cork it in the cork & wax dish", 25],
	["levitation", "Weightless Dew", "Lesson 2 · moonwater whose gravity coupling drops below zero floats: bottle it and see", 35],
	["hot_ice", "Hot Ice", "Lesson 3 · heat on the burner, cool it slowly, then seed it with a pinch of crystals", 40],
]
var tutorials_offered: bool = false


func _offer_tutorials() -> void:
	if tutorials_offered or RecipeBook.instance == null:
		return
	tutorials_offered = true
	for k: int in range(TUTORIAL_ORDERS.size() - 1, -1, -1):  # lesson 1 ends up first
		var t: Array = TUTORIAL_ORDERS[k]
		if _recipe(StringName(t[0])) == null:
			continue
		commissions.push_front({"recipe_id": String(t[0]), "title": t[1], "min_grade": "D", "reward": int(t[3]),
			"client": t[2], "tutorial": true})
	if not commissions.is_empty() and commissions[0].get("tutorial", false):
		pin(String(commissions[0]["recipe_id"]))
		toast.emit("First commission: %s. It's pinned on screen; the Grimoire (G) lists all three lessons" % commissions[0]["title"], &"discovery")


func _refill_commissions() -> void:
	if RecipeBook.instance == null:
		return
	_offer_tutorials()
	var pool: Array[RecipeData] = []
	for recipe: RecipeData in RecipeBook.instance.recipes:
		var taken: bool = false
		for order: Dictionary in commissions:
			taken = taken or order["recipe_id"] == String(recipe.recipe_id)
		if not taken and (recipe.category != RecipeData.Category.SECRET or RecipeBook.instance.is_discovered(recipe)):
			pool.append(recipe)
	while commissions.size() < ACTIVE_COMMISSIONS and not pool.is_empty():
		var pick: RecipeData = pool.pop_at(_rng.randi_range(0, pool.size() - 1))
		var min_grade: String = ["C", "B", "B", "A"][_rng.randi_range(0, 3)]
		var base: int = [20, 35, 60, 15][int(pick.category)]
		var reward: int = base + (GRADES.length() - GRADES.find(min_grade)) * 5 + _rng.randi_range(0, 10)
		commissions.append({"recipe_id": String(pick.recipe_id), "title": pick.title, "min_grade": min_grade, "reward": reward,
			"client": ["the Apothecary Guild", "a nervous hedge-witch", "the Duke's physician", "a travelling bard", "the Lighthouse Keeper", "an anonymous letter"][_rng.randi_range(0, 5)]})
	changed.emit()


func _recipe(id: StringName) -> RecipeData:
	if RecipeBook.instance != null:
		for recipe: RecipeData in RecipeBook.instance.recipes:
			if recipe.recipe_id == id:
				return recipe
	return null


# --- Collection ----------------------------------------------------------------------------

## Log a collectible find (from cracking, sifting or crushing). Returns true if new.
func record_find(m: MineralData, specimen: Rock3D = null) -> bool:
	var id: String = String(m.mineral_id)
	var is_new: bool = not collection.has(id)
	var entry: Dictionary = collection.get(id, {"count": 0, "first_time": Time.get_unix_time_from_system(), "best_value": 0, "best_name": m.display_name})
	entry["count"] = int(entry["count"]) + 1
	if specimen != null and specimen.value() > int(entry["best_value"]):
		entry["best_value"] = specimen.value()
		entry["best_name"] = specimen.describe_name()
	elif int(entry["best_value"]) == 0:
		entry["best_value"] = m.value_coins
	collection[id] = entry
	if is_new:
		toast.emit("New find! %s (%s)" % [m.display_name, m.rarity_name()], &"secret" if m.rarity >= 3 else &"discovery")
	_save()
	changed.emit()
	return is_new


## Update the best specimen after polishing/faceting (no count change).
func record_specimen(specimen: Rock3D) -> void:
	var id: String = String(specimen.mineral.mineral_id)
	if not collection.has(id):
		record_find(specimen.mineral, specimen)
		return
	var entry: Dictionary = collection[id]
	if specimen.value() > int(entry["best_value"]):
		entry["best_value"] = specimen.value()
		entry["best_name"] = specimen.describe_name()
		toast.emit("New best specimen: %s  (%d ◉)" % [specimen.describe_name(), specimen.value()], &"coins")
		_save()
		changed.emit()


# --- Seen pages ------------------------------------------------------------------------------

func is_seen(key: String) -> bool:
	return seen.has(key)


func mark_seen(key: String) -> void:
	if seen.has(key):
		return
	seen[key] = true
	_save()


## Log a finished cut. Returns true the moment a cut becomes mastered.
func record_cut(cut_name: String, quality: float) -> bool:
	var was: bool = is_mastered(cut_name)
	var e: Dictionary = cut_mastery.get(cut_name, {"count": 0, "best": 0.0})
	e["count"] = int(e["count"]) + 1
	e["best"] = maxf(float(e["best"]), quality)
	cut_mastery[cut_name] = e
	_save()
	changed.emit()
	return not was and is_mastered(cut_name)


func is_mastered(cut_name: String) -> bool:
	var e: Dictionary = cut_mastery.get(cut_name, {})
	return int(e.get("count", 0)) >= MASTERY_CUTS and float(e.get("best", 0.0)) >= MASTERY_QUALITY


func pin(recipe_id: String) -> void:
	pinned_recipe = "" if pinned_recipe == recipe_id else recipe_id
	_save()
	changed.emit()


func pinned() -> RecipeData:
	return _recipe(StringName(pinned_recipe)) if pinned_recipe != "" else null


# --- Persistence ------------------------------------------------------------------------

func _save() -> void:
	if not persist:
		return
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("journal", "discoveries", discoveries)
	cfg.set_value("journal", "cellar", cellar)
	cfg.set_value("journal", "coins", coins)
	cfg.set_value("journal", "commissions", commissions)
	cfg.set_value("journal", "tutorials_offered", tutorials_offered)
	cfg.set_value("journal", "collection", collection)
	cfg.set_value("journal", "seen", seen)
	cfg.set_value("journal", "pinned", pinned_recipe)
	cfg.set_value("journal", "cut_mastery", cut_mastery)
	cfg.save(SAVE_PATH)


func _load() -> void:
	if not persist:
		return
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	discoveries = cfg.get_value("journal", "discoveries", {})
	var saved_cellar: Array = cfg.get_value("journal", "cellar", [])
	for e: Variant in saved_cellar:
		cellar.append(e as Dictionary)
	coins = cfg.get_value("journal", "coins", 0)
	collection = cfg.get_value("journal", "collection", {})
	seen = cfg.get_value("journal", "seen", {})
	pinned_recipe = cfg.get_value("journal", "pinned", "")
	cut_mastery = cfg.get_value("journal", "cut_mastery", {})
	tutorials_offered = bool(cfg.get_value("journal", "tutorials_offered", false))
	var saved_orders: Array = cfg.get_value("journal", "commissions", [])
	for o: Variant in saved_orders:
		commissions.append(o as Dictionary)
