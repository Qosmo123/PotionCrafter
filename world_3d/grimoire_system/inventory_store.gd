class_name InventoryStore
extends Node3D
## Lab storage: what can be taken out (spawned onto the bench) and put back.
## Reagents and berries are unlimited stock bottles; glassware and tools are
## counted, and stashing a held item (E) returns it to storage.

signal changed

enum Category { REAGENTS, BERRIES, GLASSWARE, TOOLS, ROCKS, CHEMICALS, FUN }

const VESSEL_SCENE: PackedScene = preload("res://world_3d/vessels/vessel_3d.tscn")
const STIR_SCRIPT: Script = preload("res://tactile_3d/interactions/stir_tool_3d.gd")
const BERRY_SCRIPT: Script = preload("res://world_3d/terrarium/berry_3d.gd")
const PROFILE_DIR: String = "res://world_3d/vessels/profiles/"
const REAGENT_FILL_M3: float = 150e-6
const POWDER_FILL_M3: float = 15e-6

static var instance: InventoryStore = null

@export var grabber: TactileGrabber3D
@export var spawn_spacing_meters: float = 0.09

var items: Array[Dictionary] = []
var last_message: String = ""
var _spawn_index: int = 0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	_build_catalog()


func _build_catalog() -> void:
	# Reagent stock bottles: [label, substance ids, mole ratios, profile]
	var reagents: Array = [
		["Water", [&"water"], [1.0], "apothecary_bottle"],
		["Vinegar", [&"water", &"acetic_acid"], [5.0, 1.0], "apothecary_bottle"],
		["Salt of Soda (powder)", [&"baking_soda"], [1.0], "vial"],
		["Polyvinyl Mucilage", [&"pva_glue"], [1.0], "erlenmeyer"],
		["Borax Lye", [&"borax_solution"], [1.0], "apothecary_bottle"],
		["Saponified Lather", [&"soap_solution"], [1.0], "erlenmeyer"],
		["Sweet Oil of Glycerin", [&"glycerin"], [1.0], "apothecary_bottle"],
		["Spirit of Wine", [&"ethanol"], [1.0], "apothecary_bottle"],
		["Honey Syrup", [&"honey_syrup"], [1.0], "erlenmeyer"],
		["Moonwater", [&"moonwater"], [1.0], "apothecary_bottle"],
		["Quicksilver", [&"quicksilver"], [1.0], "vial"],
		["Oxygenated Water", [&"hydrogen_peroxide", &"water"], [1.0, 1.0], "apothecary_bottle"],
		["Catalyst of Iodine", [&"potassium_iodide"], [1.0], "vial"],
		["Lunar Caustic", [&"silver_nitrate"], [1.0], "apothecary_bottle"],
		["Sea Brine", [&"salt_brine"], [1.0], "apothecary_bottle"],
		["Blue Vitriol", [&"copper_sulfate"], [1.0], "erlenmeyer"],
		["Caustic Lye", [&"caustic_lye"], [1.0], "apothecary_bottle"],
		["Salamander Oil", [&"salamander_oil"], [1.0], "erlenmeyer"],
		["Chameleon Ink", [&"chameleon_ink"], [1.0], "vial"],
	]
	for r: Array in reagents:
		var first: SubstanceData = SubstanceRegistry.get_substance(SubstanceRegistry.index_of_id(r[1][0]))
		var main_sub: SubstanceData = SubstanceRegistry.get_substance(SubstanceRegistry.index_of_id(r[1][r[1].size() - 1]))
		items.append({"id": "reagent:" + r[0], "category": Category.REAGENTS, "label": r[0],
			"detail": main_sub.chemical_formula, "color": first.base_albedo_rgba.lerp(main_sub.base_albedo_rgba, 0.7),
			"count": -1, "substances": r[1], "ratios": r[2], "profile": r[3]})
	for juice_id: StringName in [&"glowberry_juice", &"emberberry_juice", &"frostberry_juice", &"duskberry_juice"]:
		var juice: SubstanceData = SubstanceRegistry.get_substance(SubstanceRegistry.index_of_id(juice_id))
		items.append({"id": "berry:" + String(juice_id), "category": Category.BERRIES,
			"label": juice.display_name.replace(" Juice", ""), "detail": juice.chemical_formula,
			"color": juice.base_albedo_rgba, "count": -1, "juice": juice})
	for glass: Array in [["round_flask", "Round-bottom Flask", 3], ["erlenmeyer", "Erlenmeyer Flask", 4], ["beaker", "Beaker", 4], ["apothecary_bottle", "Apothecary Bottle", 4], ["vial", "Test Tube", 6]]:
		items.append({"id": "glass:" + glass[0], "category": Category.GLASSWARE, "label": glass[1],
			"detail": "borosilicate", "color": Color(0.8, 0.92, 0.95, 0.5), "count": glass[2], "profile": glass[0]})
	# Stir tool presets mirror the bench tools.
	var tools: Array = [
		["glass_rod", "Glass Stirring Rod", 2, {"swirl_coupling": 5.0, "agitation_gain": 0.4}],
		["silver_rod", "Silver Rod", 1, {"swirl_coupling": 7.0, "agitation_gain": 0.5, "chirality_bias_rad_s": 1.5, "chirality_sign": -1.0}],
		["wooden_spoon", "Wooden Spoon", 2, {"radius_meters": 0.008, "tool_mass_kg": 0.04, "swirl_coupling": 10.0, "agitation_gain": 0.8, "drag_coefficient": 0.6}],
		["whisk", "Whisk", 1, {"length_meters": 0.2, "radius_meters": 0.018, "tool_mass_kg": 0.07, "swirl_coupling": 4.0, "agitation_gain": 2.5, "drag_coefficient": 0.9, "hover_offset_meters": -0.09}],
		["arcane_wand", "Arcane Wand", 1, {"tool_mass_kg": 0.025, "swirl_coupling": 8.0, "agitation_gain": 0.7, "chirality_bias_rad_s": 6.0}],
	]
	# Every rock and sand in the encyclopedia (minerals, gems and fossils are found, not bought).
	var rock_list: Array[MineralData] = []
	for m: MineralData in Rock3D.registry().values():
		if m.kind == MineralData.Kind.ROCK or m.kind == MineralData.Kind.SAND:
			rock_list.append(m)
	rock_list.sort_custom(func(a: MineralData, b: MineralData) -> bool: return a.kind < b.kind if a.kind != b.kind else a.display_name < b.display_name)
	for m: MineralData in rock_list:
		items.append({"id": "rock:" + String(m.mineral_id), "category": Category.ROCKS, "label": m.display_name,
			"shelf": "Sand bags" if m.kind == MineralData.Kind.SAND else "Rocks",
			"detail": "%s · Mohs %.1f" % [m.rarity_name(), m.hardness_mohs], "color": m.color, "count": -1, "mineral": m})
	_build_shelf_catalog()
	items.append({"id": "hammer", "category": Category.ROCKS, "label": "Geologist's Hammer", "detail": "Space to strike",
		"color": Color(0.4, 0.4, 0.45), "count": 1})
	for t: Array in tools:
		items.append({"id": "tool:" + t[0], "category": Category.TOOLS, "label": t[1], "detail": "stirring",
			"color": Color(0.85, 0.7, 0.45), "count": t[2], "model": "res://world_3d/props/%s.gltf" % t[0], "params": t[3]})


## Lab chemicals and kid ingredients straight from each substance's shelf,
## packed the way they really come: powders in vials, liquids in bottles,
## cryogens chilled (dry ice at 190 K, liquid nitrogen at 70 K).
func _build_shelf_catalog() -> void:
	var entries: Array[SubstanceData] = []
	for i: int in SubstanceRegistry.count():
		var s: SubstanceData = SubstanceRegistry.get_substance(i)
		if s.shelf != "":
			entries.append(s)
	entries.sort_custom(func(a: SubstanceData, b: SubstanceData) -> bool: return a.shelf < b.shelf if a.shelf != b.shelf else a.display_name < b.display_name)
	for s: SubstanceData in entries:
		var fun: bool = s.shelf in SafetySheet.FUN_SHELVES
		var temp_k: float = SimConstants.AMBIENT_TEMP_KELVIN
		var profile_name: String = "apothecary_bottle"
		var form: String = "liquid"
		if s.boiling_point_kelvin < 250.0:
			# Cryogens are kept at (or just below) their boiling/sublimation point.
			temp_k = maxf(s.boiling_point_kelvin - 3.0, 4.0)
			profile_name = "beaker"
			form = "cryogenic %s, %.0f °C" % ["solid" if s.melting_point_kelvin >= s.boiling_point_kelvin - 1.0 else "liquid", temp_k - 273.15]
		elif s.melting_point_kelvin > temp_k:
			profile_name = "vial"
			form = "powder"
		var detail: String = "%s · %s" % [s.chemical_formula, form]
		if s.cas_number != "":
			detail += " · CAS " + s.cas_number
		items.append({"id": "chem:" + String(s.substance_id), "category": Category.FUN if fun else Category.CHEMICALS,
			"label": s.display_name, "detail": detail, "shelf": s.shelf, "color": s.base_albedo_rgba, "count": -1,
			"substances": [s.substance_id], "ratios": [1.0], "profile": profile_name, "temp_k": temp_k, "tooltip": s.description})


func get_items(category: Category) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in items:
		if item["category"] == category:
			out.append(item)
	return out


func find_item(id: String) -> Dictionary:
	for item: Dictionary in items:
		if item["id"] == id:
			return item
	return {}


## Take an item out of storage and drop it onto the bench. Returns the body.
func take(id: String) -> RigidBody3D:
	var item: Dictionary = find_item(id)
	if item.is_empty():
		return null
	if item["count"] == 0:
		last_message = "No %s left in storage" % item["label"]
		changed.emit()
		return null
	var body: RigidBody3D = null
	match item["category"]:
		Category.REAGENTS, Category.CHEMICALS, Category.FUN:
			body = _make_vessel(item["profile"], item["substances"], item["ratios"])
			(body as Vessel3D).initial_temp_kelvin = float(item.get("temp_k", SimConstants.AMBIENT_TEMP_KELVIN))
		Category.GLASSWARE:
			body = _make_vessel(item["profile"], [], [])
		Category.BERRIES:
			var berry: Berry3D = BERRY_SCRIPT.new() as Berry3D
			berry.juice = item["juice"]
			body = berry
		Category.ROCKS:
			if item.has("mineral"):
				var rock: Rock3D = Rock3D.new()
				rock.mineral = item["mineral"]
				body = rock
			else:
				body = Hammer3D.new()
		Category.TOOLS:
			var tool: StirTool3D = STIR_SCRIPT.new() as StirTool3D
			tool.model = load(item["model"]) as PackedScene
			for key: String in item["params"]:
				tool.set(key, item["params"][key])
			body = tool
	body.set_meta(&"inventory_id", id)
	body.name = "%s_%d" % [String(item["label"]).replace(" ", ""), _spawn_index]
	var column: int = _spawn_index % 5
	body.position = global_position + Vector3((float(column) - 2.0) * spawn_spacing_meters, 0.0, 0.0)
	if body is StirTool3D:
		body.rotation.z = PI * 0.5
	_spawn_index += 1
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	host.add_child(body)
	if body is StirTool3D:
		for crock: ToolCrock3D in ToolCrock3D.all_crocks:
			if crock.has_free_slot() and crock.place_tool(body as StirTool3D):
				break
	if item["count"] > 0:
		item["count"] -= 1
	last_message = "Took out: %s" % item["label"]
	changed.emit()
	return body


## Put a body back into storage. Vessels are emptied into the sink first.
func stash(body: RigidBody3D) -> bool:
	if body == null:
		return false
	var id: String = String(body.get_meta(&"inventory_id", ""))
	if id == "":
		if body is Vessel3D and (body as Vessel3D).profile != null:
			id = "glass:" + (body as Vessel3D).profile.vessel_name
		elif body is Berry3D and (body as Berry3D).juice != null:
			id = "berry:" + String((body as Berry3D).juice.substance_id)
		elif body is Hammer3D:
			id = "hammer"
		elif body is Rock3D and (body as Rock3D).mineral != null:
			id = "rock:" + String((body as Rock3D).mineral.mineral_id)
		elif body is StirTool3D:
			var model_path: String = (body as StirTool3D).model.resource_path if (body as StirTool3D).model != null else ""
			id = "tool:" + model_path.get_file().get_basename()
	if (id.begins_with("reagent:") or id.begins_with("chem:")) and body is Vessel3D:
		id = "glass:" + (body as Vessel3D).profile.vessel_name
	var item: Dictionary = find_item(id)
	if item.is_empty():
		last_message = "That doesn't fit in storage"
		changed.emit()
		return false
	if item["count"] >= 0:
		item["count"] += 1
	if grabber != null and grabber.held_body == body:
		grabber.release()
	body.queue_free()
	last_message = "Stored: %s%s" % [item["label"], " (contents rinsed away)" if body is Vessel3D else ""]
	changed.emit()
	return true


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_E and grabber != null and grabber.held_body != null:
		stash(grabber.held_body)


func _make_vessel(profile_name: String, substance_ids: Array, ratios: Array) -> Vessel3D:
	var vessel: Vessel3D = VESSEL_SCENE.instantiate() as Vessel3D
	vessel.profile = load(PROFILE_DIR + profile_name + ".tres") as VesselProfile
	if substance_ids.is_empty():
		return vessel
	var fill_m3: float = POWDER_FILL_M3 if profile_name == "vial" else REAGENT_FILL_M3
	var ratio_sum: float = 0.0
	for r: float in ratios:
		ratio_sum += r
	var subs: Array[Resource] = []
	var moles: Array[float] = []
	for i: int in substance_ids.size():
		var s: SubstanceData = SubstanceRegistry.get_substance(SubstanceRegistry.index_of_id(substance_ids[i]))
		var share_m3: float = fill_m3 * float(ratios[i]) / ratio_sum
		subs.append(s)
		moles.append(share_m3 * s.density_kg_m3 / s.molar_mass_kg_mol)
	vessel.initial_substances = subs
	vessel.initial_moles = moles
	return vessel
