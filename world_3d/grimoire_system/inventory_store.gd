class_name InventoryStore
extends Node3D
## Lab storage: what can be taken out (spawned onto the bench) and put back.
## Reagents and berries are unlimited stock bottles; glassware and tools are
## counted, and stashing a held item (E) returns it to storage.
## Things made in the Mineral Lab are kept too: gems, minerals and fossils
## (with their polish and cut) under Finds, and the powders and sands from
## the crusher and sifter, by weight, under Materials. Stashing a vessel
## keeps its contents as materials instead of rinsing them away.

signal changed

enum Category { REAGENTS, BERRIES, GLASSWARE, TOOLS, ROCKS, CHEMICALS, FUN, FINDS, MATERIALS }

const VESSEL_SCENE: PackedScene = preload("res://world_3d/vessels/vessel_3d.tscn")
const STIR_SCRIPT: Script = preload("res://tactile_3d/interactions/stir_tool_3d.gd")
const BERRY_SCRIPT: Script = preload("res://world_3d/terrarium/berry_3d.gd")
const PROFILE_DIR: String = "res://world_3d/vessels/profiles/"
const REAGENT_FILL_M3: float = 150e-6
const POWDER_FILL_M3: float = 15e-6
## One scoop of a stored material taken out at a time.
const MATERIAL_PORTION_KG: float = 0.03
## Less than this of a substance isn't worth keeping (dust, traces).
const MATERIAL_MIN_KG: float = 1e-4

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


## Where a satchel item would land if dropped at `screen`: the bench surface
## under the pointer, within arm's reach. {valid, position, reason}
func drop_point(camera: Camera3D, screen: Vector2) -> Dictionary:
	if grabber != null and grabber.is_side_view():
		return grabber.side_drop_point(screen)
	if camera == null:
		return {"valid": false, "position": Vector3.ZERO, "reason": "No camera"}
	var origin: Vector3 = camera.project_ray_origin(screen)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 8.0, SimConstants.LAYER_STATIC_BENCH)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"valid": false, "position": Vector3.ZERO, "reason": "Drop it onto the bench top"}
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if normal.y < 0.6:
		return {"valid": false, "position": pos, "reason": "That surface is too steep: drop it onto the bench top"}
	if grabber != null:
		var flat: Vector2 = Vector2(pos.x - grabber.global_position.x, pos.z - grabber.global_position.z)
		if flat.length() > grabber.reach_radius_meters:
			return {"valid": false, "position": pos, "reason": "Out of reach: drop it closer, or switch station"}
	return {"valid": true, "position": pos, "reason": ""}


## Take an item and put it straight into the hand (Shift-click / Shift+Enter).
func take_to_hand(id: String) -> RigidBody3D:
	var body: RigidBody3D = take(id, grabber.global_position + Vector3(0.0, grabber.hover_plane_y_meters - grabber.global_position.y, 0.15) if grabber != null else Vector3.INF)
	if body != null and grabber != null:
		grabber.grab(body)
		last_message = "In hand: %s" % find_item(id).get("label", "")
		changed.emit()
	return body


## Gather a recipe's ingredients from the shelves onto the bench (auto-fill).
## Only dispenses the containers: the player still mixes, heats and stirs, and
## the chemistry decides the result. Returns the labels that could not be
## found in storage (heat, stirring, products of other reactions...).
func gather(recipe: RecipeData) -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	var taken: PackedStringArray = PackedStringArray()
	for ing: String in recipe.ingredients:
		var id: String = match_ingredient(ing)
		if id == "" or take(id) == null:
			missing.append(ing)
		else:
			taken.append(String(find_item(id)["label"]))
	last_message = ("Gathered: %s" % ", ".join(taken)) if not taken.is_empty() else "Nothing to gather from storage"
	if not missing.is_empty():
		last_message += "   ·   still needed: %s" % ", ".join(missing)
	changed.emit()
	return missing


## "Brew Pinned Formula": pour each ingredient of a known recipe straight
## from the shelves into `vessel` (equal shares of the free space). This only
## skips the fetching and pouring: the mixture still has to be heated,
## stirred and allowed to react, and the chemistry decides what comes out.
## Returns the ingredients that aren't shelf items (heat, stirring...).
func dispense_into(recipe: RecipeData, vessel: Vessel3D) -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	var ids: PackedStringArray = PackedStringArray()
	for ing: String in recipe.ingredients:
		var id: String = match_ingredient(ing)
		if id == "" or find_item(id).get("count", 0) == 0:
			missing.append(ing)
		elif not id in ids:
			ids.append(id)
	if ids.is_empty():
		last_message = "None of these ingredients are on the shelves: " + ", ".join(missing)
		return missing
	var free_m3: float = maxf(vessel.capacity_m3 * 0.8 - vessel.mixture.get_liquid_volume_m3() - vessel.mixture.get_solid_volume_m3(), 0.0)
	if free_m3 < 5e-6:
		last_message = "That vessel is already full"
		missing = recipe.ingredients.duplicate()
		return missing
	var share_m3: float = minf(free_m3 / float(ids.size()), REAGENT_FILL_M3)
	var poured: PackedStringArray = PackedStringArray()
	for id: String in ids:
		var item: Dictionary = find_item(id)
		var subs: Array = item.get("substances", [])
		var ratios: Array = item.get("ratios", [])
		var ratio_sum: float = 0.0
		for k: int in subs.size():
			ratio_sum += float(ratios[k]) if k < ratios.size() else 1.0
		if subs.is_empty() and item.has("juice"):
			subs = [(item["juice"] as SubstanceData).substance_id]
			ratio_sum = 1.0
		for k: int in subs.size():
			var idx: int = SubstanceRegistry.index_of_id(StringName(subs[k]))
			if idx < 0:
				continue
			var s: SubstanceData = SubstanceRegistry.get_substance(idx)
			var part_m3: float = share_m3 * (float(ratios[k]) if k < ratios.size() else 1.0) / maxf(ratio_sum, 1e-9)
			vessel.mixture.add_substance(idx, part_m3 * s.density_kg_m3 / s.molar_mass_kg_mol, float(item.get("temp_k", SimConstants.AMBIENT_TEMP_KELVIN)))
		if int(item["count"]) > 0:
			item["count"] = int(item["count"]) - 1
		poured.append(String(item["label"]))
	last_message = "Poured in: %s" % ", ".join(poured)
	if not missing.is_empty():
		last_message += "   ·   still needed: %s" % ", ".join(missing)
	changed.emit()
	return missing


## Best storage item for an ingredient written in words ("Two scoops of
## Baking Soda" -> the baking-soda vial). Longest label match wins.
func match_ingredient(words: String) -> String:
	var w: String = words.to_lower().get_slice("(", 0).strip_edges()
	var best: String = ""
	var best_len: int = 0
	for item: Dictionary in items:
		if not (item["category"] in [Category.REAGENTS, Category.CHEMICALS, Category.FUN, Category.BERRIES]):
			continue
		var names: PackedStringArray = PackedStringArray([String(item["label"]).to_lower()])
		for sid: Variant in item.get("substances", []):
			var idx: int = SubstanceRegistry.index_of_id(StringName(sid))
			if idx >= 0:
				names.append(SubstanceRegistry.get_substance(idx).display_name.to_lower())
		for n: String in names:
			var core: String = n.get_slice("(", 0).replace(" juice", "").strip_edges()
			if core.length() > best_len and core.length() >= 3 and (w.contains(core) or (core.contains(w) and w.length() >= 4)):
				best = item["id"]
				best_len = core.length()
	return best


## Take an item out of storage and drop it onto the bench (or at `drop_at`,
## e.g. where it was dragged to). Returns the body, or null with last_message
## explaining why.
func take(id: String, drop_at: Vector3 = Vector3.INF) -> RigidBody3D:
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
		Category.FINDS:
			var find: Rock3D = Rock3D.new()
			find.mineral = item["mineral"]
			find.cut = int(item["cut"])
			find.polish = float(item["polish"])
			find.cut_quality = float(item["cut_quality"])
			find.mass_kg = float(item["mass_kg"])
			body = find
		Category.MATERIALS:
			var s: SubstanceData = SubstanceRegistry.get_substance(SubstanceRegistry.index_of_id(StringName(item["substances"][0])))
			var portion_kg: float = minf(float(item["kg"]), MATERIAL_PORTION_KG)
			var jar: Vessel3D = VESSEL_SCENE.instantiate() as Vessel3D
			jar.profile = load(PROFILE_DIR + String(item["profile"]) + ".tres") as VesselProfile
			jar.initial_substances = [s] as Array[Resource]
			jar.initial_moles = [portion_kg / s.molar_mass_kg_mol] as Array[float]
			item["kg"] = float(item["kg"]) - portion_kg
			body = jar
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
	if drop_at.is_finite():
		body.position = drop_at + Vector3(0.0, 0.12, 0.0)
	if body is StirTool3D:
		body.rotation.z = PI * 0.5
	_spawn_index += 1
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	host.add_child(body)
	if body is StirTool3D and not drop_at.is_finite():
		for crock: ToolCrock3D in ToolCrock3D.all_crocks:
			if crock.has_free_slot() and crock.place_tool(body as StirTool3D):
				break
	if item["category"] == Category.MATERIALS:
		_refresh_material(item)
	elif item["count"] > 0:
		item["count"] -= 1
	last_message = "Took out: %s" % item["label"]
	changed.emit()
	return body


## Put a body back into storage. Vessels are emptied into the sink first.
func stash(body: RigidBody3D) -> bool:
	if body == null or body.is_queued_for_deletion():
		return false
	var rock_body: Rock3D = body as Rock3D
	if rock_body != null and is_find(rock_body):
		if grabber != null and grabber.held_body == body:
			grabber.release()
		last_message = "Stored: %s (Finds)" % store_find(rock_body)
		changed.emit()
		return true
	var kept: String = ""
	if body is Vessel3D and (body as Vessel3D).mixture != null:
		kept = store_contents(body as Vessel3D)
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
	last_message = "Stored: %s%s" % [item["label"], ("  ·  kept " + kept) if kept != "" else ""]
	changed.emit()
	return true


# --- Mineral Lab finds and materials ------------------------------------------------

## Gems, minerals and fossils, and any stone that has been polished or cut,
## are finds (kept one by one); plain rocks and sand bags go back to the crates.
static func is_find(rock: Rock3D) -> bool:
	if rock.mineral == null:
		return false
	if rock.mineral.kind != MineralData.Kind.ROCK and rock.mineral.kind != MineralData.Kind.SAND:
		return true
	return rock.cut != RockMeshes.Cut.NONE or rock.polish > 0.3


## Put a find away (it leaves the bench). Returns its label.
func store_find(rock: Rock3D) -> String:
	var m: MineralData = rock.mineral
	var finish: int = 2 if rock.polish > 0.85 else (1 if rock.polish > 0.3 else 0)
	var id: String = "find:%s:%d:%d" % [m.mineral_id, rock.cut, finish]
	var item: Dictionary = find_item(id)
	if item.is_empty():
		var shelf: String = "Fossils" if m.kind == MineralData.Kind.FOSSIL else ("Gems" if m.kind == MineralData.Kind.GEM else "Minerals")
		if rock.cut != RockMeshes.Cut.NONE:
			shelf = "Cut gems"
		item = {"id": id, "category": Category.FINDS, "label": rock.describe_name(), "shelf": shelf,
			"detail": "%s · Mohs %.1f · about %d ◉" % [m.rarity_name(), m.hardness_mohs, rock.value()],
			"color": m.color, "count": 0, "mineral": m, "cut": rock.cut, "polish": rock.polish,
			"cut_quality": rock.cut_quality, "mass_kg": rock.mass_kg}
		_insert_sorted(item)
	item["count"] = int(item["count"]) + 1
	item["cut_quality"] = maxf(float(item["cut_quality"]), rock.cut_quality)
	if GrimoireJournal.instance != null:
		GrimoireJournal.instance.record_find(m)
	rock.queue_free()
	return String(item["label"])


## Empty `vessel` into storage: every substance in it is kept by weight
## (crushed powder, sifted sand, anything). Returns a short summary like
## "80 g Calcite Powder", or "" when there was nothing worth keeping.
func store_contents(vessel: Vessel3D) -> String:
	var mix: MixtureContainer = vessel.mixture
	if mix == null or mix.get_total_mass_kg() < MATERIAL_MIN_KG:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	var total_kg: float = 0.0
	for k: int in mix.active_count():
		var idx: int = mix.active_index(k)
		var s: SubstanceData = SubstanceRegistry.get_substance(idx)
		var kg: float = mix.moles[idx] * s.molar_mass_kg_mol
		if kg < MATERIAL_MIN_KG:
			continue
		var item: Dictionary = _material_item(s)
		item["kg"] = float(item["kg"]) + kg
		_refresh_material(item)
		total_kg += kg
		if parts.size() < 3:
			parts.append("%.0f g %s" % [kg * 1000.0, s.display_name])
	mix.clear()
	if parts.is_empty():
		return ""
	var text: String = ", ".join(parts)
	return text if total_kg > 0.0 else ""


func _material_item(s: SubstanceData) -> Dictionary:
	var id: String = "mat:" + String(s.substance_id)
	var item: Dictionary = find_item(id)
	if item.is_empty():
		var solid: bool = s.melting_point_kelvin > SimConstants.AMBIENT_TEMP_KELVIN
		item = {"id": id, "category": Category.MATERIALS, "label": s.display_name, "shelf": "Powders & sands" if solid else "Liquids",
			"detail": "", "color": s.base_albedo_rgba, "count": 0, "kg": 0.0, "substances": [s.substance_id], "ratios": [1.0],
			"profile": "vial" if solid else "apothecary_bottle", "tooltip": s.description}
		_insert_sorted(item)
	return item


## Count = scoops left; the row shows the weight.
func _refresh_material(item: Dictionary) -> void:
	var kg: float = maxf(float(item["kg"]), 0.0)
	item["count"] = int(ceil(kg / MATERIAL_PORTION_KG - 1e-6)) if kg >= MATERIAL_MIN_KG else 0
	var s: SubstanceData = SubstanceRegistry.get_substance(SubstanceRegistry.index_of_id(StringName(item["substances"][0])))
	item["detail"] = "%.0f g · %s" % [kg * 1000.0, s.chemical_formula]


## Keep a category's rows grouped by shelf, then by name.
func _insert_sorted(item: Dictionary) -> void:
	var at: int = items.size()
	for i: int in items.size():
		var other: Dictionary = items[i]
		if int(other["category"]) != int(item["category"]):
			if int(other["category"]) > int(item["category"]):
				at = mini(at, i)
			continue
		var a: String = "%s|%s" % [item.get("shelf", ""), item["label"]]
		var b: String = "%s|%s" % [other.get("shelf", ""), other["label"]]
		if a < b:
			at = i
			break
		at = i + 1
	items.insert(at, item)


## Total stored weight of a material (kg), for tests and the HUD.
func material_kg(substance_id: StringName) -> float:
	return float(find_item("mat:" + String(substance_id)).get("kg", 0.0))


## How many of a find are stored (any finish).
func find_count(mineral_id: StringName) -> int:
	var n: int = 0
	for item: Dictionary in items:
		if String(item["id"]).begins_with("find:%s:" % mineral_id):
			n += int(item["count"])
	return n


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
