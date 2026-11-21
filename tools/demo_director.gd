class_name DemoDirector
extends Node
## Stages showcase scenarios from launch arguments (inert in normal play).
## Render a still from the real game launch (see tools/render_still.sh):
##   godot --path . --resolution 1280x720 -- shot=_renders/out.png demo2
## Arguments after "--": shot=<png>, pour, demo, demo2, satchel, recipes.
## Performance: "fps" (frame times per preset and station), "cost" (per-script
## cost table, vessel breakdown and triangle budget).

const SHOT_FRAME: int = 100

var _frames: int = 0
var _args: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	set_process(not _args.is_empty())
	if _args.has("cost"):
		add_child.call_deferred((load("res://tools/cost_probe.gd") as GDScript).new())
	if _args.has("fps"):
		add_child.call_deferred((load("res://tools/fps_probe.gd") as GDScript).new())


func _process(_delta: float) -> void:
	_frames += 1
	var bench: Node = get_parent()
	if _frames == 2 and _args.has("pour"):
		var moon: Vessel3D = bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
		var beaker: Vessel3D = bench.get_node("Vessels/Beaker") as Vessel3D
		moon.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		moon.freeze = true
		var tilt: Basis = Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(105.0))
		moon.global_transform = Transform3D(tilt, beaker.global_position + Vector3(0.0, 0.12, 0.0) - tilt.y * 0.07)
	if _frames == 2 and _args.has("stored") and InventoryStore.instance != null:
		# A few finds and materials already put away in the cabinet.
		var store: InventoryStore = InventoryStore.instance
		for pair: Array in [["amethyst", 0, 0.0], ["emerald", 1, 0.9], ["ammonite_fossil", 0, 0.5], ["hiddenite", 0, 0.0], ["garnet", 0, 0.9], ["amethyst", 0, 0.0]]:
			var r: Rock3D = Rock3D.new()
			r.mineral = Rock3D.get_mineral(pair[0])
			r.mass_kg = r.mineral.typical_mass_kg
			r.cut = int(pair[1])
			r.polish = float(pair[2])
			store.store_find(r)
		for mat: Array in [[&"calcite_powder", 0.08], [&"quartz_sand_fine", 0.12], [&"garnet_sand", 0.045], [&"malachite_powder", 0.03]]:
			var item: Dictionary = store._material_item(SubstanceRegistry.get_substance(SubstanceRegistry.index_of_id(mat[0])))
			item["kg"] = mat[1]
			store._refresh_material(item)
	if _frames == 3 and _args.has("satchel"):
		var panel: CanvasLayer = bench.get_node("InventoryPanel") as CanvasLayer
		panel.call(&"toggle")
		var tabs: TabContainer = panel.find_children("*", "TabContainer", true, false)[0] as TabContainer
		tabs.current_tab = 9 if _args.has("recipes") else (4 if _args.has("rocks") else (5 if _args.has("chem") else (6 if _args.has("fun") else (8 if _args.has("materials") else (7 if _args.has("finds") else 0)))))
		panel.call(&"refresh")
		if _args.has("compact"):
			panel.call(&"set_compact", true)
	if _frames == 6 and _args.has("pin") and GrimoireJournal.instance != null and RecipeBook.instance != null:
		GrimoireJournal.instance.pin(String(RecipeBook.instance.recipes[0].recipe_id))
	if _frames == SHOT_FRAME - 10 and _args.has("satchel") and (_args.has("drag") or _args.has("card")):
		# Phase 2 showcase: a row mid-drag over the bench, or its hover card.
		var panel: CanvasLayer = bench.get_node("InventoryPanel") as CanvasLayer
		var rows: Array = panel.find_children("*", "SatchelItemButton", true, false).filter(func(n: Node) -> bool: return (n as Control).is_visible_in_tree())
		var row: SatchelItemButton = rows[3 if rows.size() > 3 else 0] as SatchelItemButton
		if _args.has("drag"):
			row.dragging = true
			panel.call(&"_on_drag_started", row)
			var screen: Vector2 = get_viewport().get_visible_rect().size * Vector2(0.36, 0.62)
			panel.call(&"_on_drag_moved", row, screen)
		else:
			var tip: PanelContainer = PanelContainer.new()
			tip.add_theme_stylebox_override(&"panel", CosmicTheme.theme().get_stylebox(&"panel", &"TooltipPanel"))
			tip.theme = CosmicTheme.theme()
			tip.add_child(SatchelItemButton.build_card(row.item))
			tip.position = row.get_global_rect().position + Vector2(-420.0, 0.0)
			(panel.get_child(0) as Control).add_child(tip)
	if _args.has("crush"):
		_crush_demo(bench)
	if _args.has("rocks"):
		_rocks_demo(bench)
	if _args.has("facet"):
		_facet_demo(bench)
	if _args.has("brew"):
		_brew_demo(bench)
	if _args.has("seal"):
		_seal_demo(bench)
	if _args.has("easy"):
		_easy_demo(bench)
	if _args.has("machines"):
		_machines_demo(bench)
	if _args.has("bottles"):
		_bottles_demo(bench)
	if _args.has("pourshot") and _frames == SHOT_FRAME - 5:
		# Mid-pour still: spirits into the beaker, honey onto the bench.
		var beaker: Vessel3D = bench.get_node("Vessels/Beaker") as Vessel3D
		var spirits: Vessel3D = bench.get_node("Vessels/FlaskSpirits") as Vessel3D
		var honey: Vessel3D = bench.get_node("Vessels/FlaskHoney") as Vessel3D
		for pair: Array in [[spirits, beaker.global_position + Vector3(-0.07, 0.17, 0.0), 1.95], [honey, Vector3(-0.32, 1.05, 0.3), 2.2]]:
			var v: Vessel3D = pair[0]
			v.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			v.freeze = true
			v.global_transform = Transform3D(Basis(Vector3(0.0, 0.0, -1.0), float(pair[2])), pair[1])
	if _args.has("noliquid") and _frames == 50:
		for v: Vessel3D in Vessel3D.all_vessels:
			var l: Node3D = v.get_node_or_null("Liquid") as Node3D
			if l != null:
				l.visible = false
				v.set_process(false)
	if _args.has("liquids") and _frames == 95:
		var cam3: Camera3D = get_viewport().get_camera_3d()
		for v: Vessel3D in Vessel3D.all_vessels:
			if not cam3.is_position_behind(v.global_position):
				var px: Vector2 = cam3.unproject_position(v.global_position)
				var vs: Vector2 = get_viewport().get_visible_rect().size
				print("VES %-16s px (%.0f%%, %.0f%%)  %s  turb %.2f  col %s" % [v.name, px.x / vs.x * 100.0, px.y / vs.y * 100.0, PotionNamer.formula_for(v.mixture), v.mixture.get_liquid_turbidity(), v.mixture.get_contents_color()])
	if _args.has("liquids") and _frames == 2:
		var cam: LabCamera3D = bench.get_node("Camera3D") as LabCamera3D
		cam.set("_zoom_target", 0.45)
	if _frames == SHOT_FRAME - 8 and _args.has("book"):
		var book: GrimoireBookUI = bench.get_node("GrimoireBookUI") as GrimoireBookUI
		book.open(1 if _args.has("formulas") else 0)
		for i: int in book._entries.size():
			var e: Dictionary = book._entries[i]
			if (e.get("kind") == "recipe" and e.get("known", false)) or (_args.has("formulas") and e.get("kind") == "substance" and (e["substance"] as SubstanceData).thaumic_density_thaums_mol > 20.0):
				book._select(i)
				break
	if _frames == SHOT_FRAME - 8 and _args.has("help"):
		(bench.get_node("HudOverlay") as HudOverlay).toggle_help()
	if _frames == SHOT_FRAME - 8 and (_args.has("sds") or _args.has("sds_acid")) and SafetySheetUI.instance != null:
		var m: MixtureContainer = MixtureContainer.new()
		if _args.has("sds_acid"):
			m.add_substance(_reg(&"water"), 3.0, 293.15)
			m.add_substance(_reg(&"hydrochloric_acid"), 1.0, 293.15)
		else:
			m.add_substance(_reg(&"water"), 2.0, 293.15)
			m.add_substance(_reg(&"ghost_sneeze"), 0.6, 293.15)
			m.add_substance(_reg(&"glow_worm_goo"), 0.4, 293.15)
			m.add_substance(_reg(&"dragon_snot"), 0.3, 293.15)
		SafetySheetUI.instance.open_for_mixture(m)
	if _args.has("science") and _frames == 2:
		var cam3: LabCamera3D = get_parent().get_node("Camera3D") as LabCamera3D
		cam3.go_to_station(2)
		# Put samples on each instrument's pad.
		var pairs: Array = [["SampleHoney", "Viscometer"], ["SampleSoap", "AirMeter"], ["SampleAcetone", "VolatilityTester"], ["SampleGlycerin", "Hydrometer"]]
		for pair: Array in pairs:
			var v: Vessel3D = get_parent().get_node("ScienceBench/" + String(pair[0])) as Vessel3D
			var inst: Node3D = get_parent().get_node("ScienceBench/" + String(pair[1])) as Node3D
			v.global_position = inst.global_transform * Vector3(0.0, 0.085, 0.06)
		var soap: Vessel3D = get_parent().get_node("ScienceBench/SampleSoap") as Vessel3D
		soap.foam_height_meters = 0.03
	if _args.has("lab"):
		_lab(bench)
	if _frames == SHOT_FRAME - 8 and _args.has("collection"):
		var book: GrimoireBookUI = bench.get_node("GrimoireBookUI") as GrimoireBookUI
		if GrimoireJournal.instance != null:
			for id: String in ["star_sapphire", "precious_opal", "diamond", "amethyst", "emerald"]:
				var found_m: MineralData = Rock3D.get_mineral(id)
				if found_m != null:
					GrimoireJournal.instance.record_find(found_m)
		book.open(2)
		for i: int in book._entries.size():
			var e: Dictionary = book._entries[i]
			if e.get("kind") == "mineral" and e.get("found", false) and (e["mineral"] as MineralData).mineral_id == &"star_sapphire":
				book._select(i)
				break
	if _args.has("demo"):
		_demo(bench)
	if _args.has("demo2"):
		_demo2(bench)
	for arg: String in _args:
		if arg.begins_with("shot=") and _frames == SHOT_FRAME:
			var image: Image = get_viewport().get_texture().get_image()
			var err: int = image.save_png(arg.substr(5)) if image != null else ERR_CANT_CREATE
			printerr("shot ", arg.substr(5), " err=", err)
			get_tree().quit()


static func _reg(id: StringName) -> int:
	return SubstanceRegistry.index_of_id(id)


## Fizzing indicator reaction, whisked bubble philtre, arcane flare, chalk sigils.
func _demo(bench: Node) -> void:
	var beaker: Vessel3D = bench.get_node("Vessels/Beaker") as Vessel3D
	var bubble: Vessel3D = bench.get_node("Vessels/BubbleBase") as Vessel3D
	var moon: Vessel3D = bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
	if _frames == 2:
		beaker.mixture.add_substance(_reg(&"water"), 10.0, 293.15)
		beaker.mixture.add_substance(_reg(&"duskberry_juice"), 0.4, 293.15)
		beaker.mixture.add_substance(_reg(&"acetic_acid"), 1.0, 293.15)
		beaker.mixture.add_substance(_reg(&"baking_soda"), 0.6, 293.15)
		moon.mixture.add_substance(_reg(&"emberberry_juice"), 0.6, 293.15)
		var chalk: ChalkDrawing3D = bench.get_node("Chalk") as ChalkDrawing3D
		chalk.draw_world_stroke(ChalkDrawing3D.polygon_points(Vector2(-0.2, 0.12), 0.075, 3))
		chalk.draw_world_stroke(ChalkDrawing3D.polygon_points(Vector2(0.62, 0.12), 0.08, 6))
		chalk.draw_world_stroke(ChalkDrawing3D.polygon_points(Vector2(-0.42, 0.1), 0.06, 5))
	bubble.add_agitation(0.5)
	beaker.add_agitation(0.2)


## Elephant's toothpaste, spirit fire, three-layer strata, verditer cloud, transmutation.
func _demo2(bench: Node) -> void:
	var beaker: Vessel3D = bench.get_node("Vessels/Beaker") as Vessel3D
	var spirits: Vessel3D = bench.get_node("Vessels/FlaskSpirits") as Vessel3D
	var strata: Vessel3D = bench.get_node("Vessels/ReagentVinegar") as Vessel3D
	var cloud: Vessel3D = bench.get_node("Vessels/ReagentBorax") as Vessel3D
	var moon: Vessel3D = bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
	if _frames == 2:
		beaker.mixture.add_substance(_reg(&"water"), 6.0, 293.15)
		beaker.mixture.add_substance(_reg(&"hydrogen_peroxide"), 3.0, 293.15)
		beaker.mixture.add_substance(_reg(&"soap_solution"), 2.0, 293.15)
		beaker.mixture.add_substance(_reg(&"potassium_iodide"), 0.4, 293.15)
		spirits.mixture.add_substance(_reg(&"ethanol"), 8.0, 293.15)
		strata.mixture.clear()
		strata.mixture.add_substance(_reg(&"water"), 4.0, 293.15)
		strata.mixture.add_substance(_reg(&"quicksilver"), 0.5, 293.15)
		strata.mixture.add_substance(_reg(&"salamander_oil"), 0.12, 293.15)
		cloud.mixture.add_substance(_reg(&"copper_sulfate"), 0.8, 293.15)
		cloud.mixture.add_substance(_reg(&"caustic_lye"), 0.8, 293.15)
		moon.mixture.add_substance(_reg(&"quicksilver"), 0.6, 293.15)
		moon.mixture.add_heat(60000.0)
	spirits.ignition_source = true
	moon.external_heat_watts += 400.0


## Mineral Lab showcase: faceted gems on display, a stone on the running
## polisher, a rock in the crusher and a few logged finds.
func _lab(bench: Node) -> void:
	if _frames == 2:
		var cam: LabCamera3D = bench.get_node("Camera3D") as LabCamera3D
		cam.go_to_station(1)
		if _args.has("zoom"):
			cam.set("_zoom_target", 0.42)
		var cuts: Array = [["ruby", RockMeshes.Cut.HEART], ["star_sapphire", RockMeshes.Cut.CABOCHON], ["amethyst", RockMeshes.Cut.CUSHION],
			["diamond", RockMeshes.Cut.ROUND], ["peridot", RockMeshes.Cut.TRILLION], ["emerald", RockMeshes.Cut.EMERALD], ["garnet", RockMeshes.Cut.PRINCESS],
			["aquamarine", RockMeshes.Cut.OVAL], ["tanzanite", RockMeshes.Cut.PEAR], ["citrine", RockMeshes.Cut.MARQUISE], ["black_opal", RockMeshes.Cut.CABOCHON],
			["paraiba", RockMeshes.Cut.ASSCHER], ["imperial_topaz", RockMeshes.Cut.RADIANT], ["tigers_eye", RockMeshes.Cut.CABOCHON]]
		for i: int in cuts.size():
			var m: MineralData = Rock3D.get_mineral(cuts[i][0])
			var row: int = i / 7
			var gem: Rock3D = Rock3D.spawn(bench, m, (Vector3(2.79 + 0.068 * float(i % 7), 0.99 - 0.075 * float(row), 0.32) if _args.has("zoom") else Vector3(2.62 + 0.075 * float(i % 7), 0.83, 0.42 - 0.07 * float(row))), m.typical_mass_kg * 2.5)
			gem.set_polish(1.0)
			if _args.has("zoom"):
				gem.freeze = true
				gem.rotation = Vector3(0.95, 0.3 * float(i % 3), 0.0)
			gem.apply_cut(cuts[i][1], 0.9)
			if GrimoireJournal.instance != null:
				GrimoireJournal.instance.record_find(m, gem)
		for id: String in ["ammonite_fossil", "gold_nugget", "fool_gold_cube", "moonstone"]:
			var find: MineralData = Rock3D.get_mineral(id)
			Rock3D.spawn(bench, find, Vector3(3.2 + randf_range(-0.04, 0.04), 0.9, 0.22), find.typical_mass_kg)
			if GrimoireJournal.instance != null:
				GrimoireJournal.instance.record_find(find)
		var crusher: RockCrusher3D = bench.get_node("MineralLab/RockCrusher") as RockCrusher3D
		Rock3D.spawn(bench, Rock3D.get_mineral("malachite_ore"), crusher.global_transform * Vector3(0.0, 0.3, 0.0), 0.08)
		var polisher: LapidaryWheel3D = bench.get_node("MineralLab/Polisher") as LapidaryWheel3D
		polisher.toggle()
		var stone: Rock3D = Rock3D.spawn(bench, Rock3D.get_mineral("fluorite_octahedron"), polisher.global_transform * Vector3(0.0, polisher.wheel_height_meters + 0.02, 0.0), 0.02)
		stone.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		stone.freeze = true


## Phase 3 crusher showcase: a cracked geode glowing on the anvil, a rare find
## being revealed, and the Load Next Rock button.
var _crush_rock: Rock3D = null


func _crush_demo(bench: Node) -> void:
	if _frames == 2:
		var cam: LabCamera3D = bench.get_node("Camera3D") as LabCamera3D
		cam.go_to_station(1)
		cam.set("_zoom_target", 0.3)
	var anvil: Node3D = get_tree().get_first_node_in_group(&"anvil") as Node3D
	if anvil == null:
		return
	if _frames == 30:
		var top: Vector3 = AnvilLoader.anvil_top(anvil)
		_crush_rock = Rock3D.spawn(bench, Rock3D.get_mineral("geode"), top + Vector3(0.0, 0.04, 0.0), 0.25)
	if _frames == SHOT_FRAME - 20 and _crush_rock != null:
		_crush_rock.integrity = _crush_rock.integrity_max * 0.3
		_crush_rock.strike(0.0001)
	if _frames == SHOT_FRAME - 12:
		var opal: Rock3D = Rock3D.spawn(bench, Rock3D.get_mineral("precious_opal"), AnvilLoader.anvil_top(anvil) + Vector3(0.12, 0.03, 0.04), 0.02)
		Rock3D._reveal(opal, opal.mineral)


## Phase 3 faceting showcase: a polished sapphire mid-cut with prism rays,
## the steadiness ring and the cut picker open.
var _facet_stone: Rock3D = null


func _facet_demo(bench: Node) -> void:
	var f: LapidaryWheel3D = LapidaryWheel3D.faceter
	if f == null:
		return
	if _frames == 2:
		var cam: LabCamera3D = bench.get_node("Camera3D") as LabCamera3D
		cam.go_to_station(1)
		cam.set("_zoom_target", 0.0)
		f.toggle()
		f.select_cut(RockMeshes.Cut.ROUND)
	if _frames == 20:
		_facet_stone = Rock3D.spawn(bench, Rock3D.get_mineral("sapphire"), f.global_position + Vector3(0.02, f.wheel_height_meters + 0.03, 0.0), 0.012)
		_facet_stone.set_polish(1.0)
	if _frames == SHOT_FRAME - 25 and _facet_stone != null:
		f.set("_cut_progress", 0.72)
		f.live_steadiness = 0.9
	if _frames == SHOT_FRAME - 20:
		var panel: Node = f.get_child(f.get_child_count() - 1)
		if panel.has_method(&"set_open"):
			panel.call(&"set_open", true)


## Phase 3 alchemy showcase: a discovered recipe pinned as the ghost
## parchment, checking the moonwater flask live, with nebula steam rising.
func _brew_demo(bench: Node) -> void:
	if _frames == 3 and RecipeBook.instance != null and GrimoireJournal.instance != null:
		for r: RecipeData in RecipeBook.instance.recipes:
			if r.recipe_id == &"levitation":
				RecipeBook.instance.discovered[r.recipe_id] = true
				GrimoireJournal.instance.pin(String(r.recipe_id))
	if _frames == 10 and HudOverlay.instance != null:
		HudOverlay.instance.set("_pin_vessel", bench.get_node("Vessels/FlaskMoonwater"))


## Easy handling: a beaker filling at the tap, the burner lit under a flask,
## a puddle on the bench, and a vial in the hand with the free rack sockets
## glowing where it can go.
func _easy_demo(bench: Node) -> void:
	var grabber: TactileGrabber3D = bench.get_node("Grabber") as TactileGrabber3D
	var cam: Camera3D = bench.get_node("Camera3D") as Camera3D
	if _frames == 3:
		var tap: WaterTap3D = bench.get_node("Stands/WaterTap") as WaterTap3D
		var beaker: Vessel3D = bench.get_node("Vessels/Beaker") as Vessel3D
		beaker.global_position = tap.global_position + Vector3(0.0, 0.015 + 0.05, 0.0)
		var burner: Burner3D = bench.get_node("Stands/Burner") as Burner3D
		burner.toggle()
		var honey: Vessel3D = bench.get_node("Vessels/FlaskHoney") as Vessel3D
		honey.global_position = burner.global_position + Vector3(0.0, burner.gauze_height_meters + 0.075, 0.0)
		var color: Color = Color(0.3, 0.75, 0.45, 0.6)
		SpillPuddles3D.spill(bench, Vector3(-0.2, 0.9, 0.3), 1.2e-5, color)
		SpillPuddles3D.spill(bench, Vector3(-0.17, 0.9, 0.33), 4e-6, color)
	if _frames == 20:
		grabber.grab(bench.get_node("Vessels/VialSoda") as Vessel3D)
	if _frames > 20:
		var rack: SupportStand3D = bench.get_node("Stands/TubeRack") as SupportStand3D
		grabber._pointer_screen = cam.unproject_position(rack.seat_floor_world(4) + Vector3(0.0, 0.17, 0.0))


## Bottling: a row of corked, wax-sealed bottles (one per grade colour) and
## one still mid-pour, glowing hot.
func _seal_demo(bench: Node) -> void:
	if _frames == 2:
		var cam: LabCamera3D = bench.get_node("Camera3D") as LabCamera3D
		cam.set("_zoom_target", 0.45)
	if _frames != 30 and _frames != SHOT_FRAME - 7:
		return
	var filled: Array[Vessel3D] = []
	for v: Vessel3D in Vessel3D.all_vessels:
		if v.mixture != null and v.mixture.get_liquid_volume_m3() > 2e-6 and (v.profile == null or not v.profile.vessel_name.contains("beaker")):
			filled.append(v)
	var grades: PackedStringArray = ["S", "A", "B", "C", "D", "F", "B"]
	var count: int = mini(filled.size(), grades.size())
	for i: int in count:
		var v: Vessel3D = filled[i]
		var last: bool = i == count - 1
		if last != (_frames != 30):
			continue
		v.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		v.freeze = true
		v.global_transform = Transform3D(Basis.IDENTITY, Vector3(-0.29 + 0.098 * float(i), 1.02, 0.25))
		if not v.sealed:
			v.toggle_seal()
		var seal: BottleSeal3D = v.get("_seal") as BottleSeal3D
		seal.seal(grades[i], 3 + i % 6, not last)
		print("SEAL %s %s grade %s" % [v.name, v.profile.vessel_name if v.profile != null else "cyl", grades[i]])


## 4K rock and gem surfaces: a row of rough specimens, frozen for a close look.
func _rocks_demo(bench: Node) -> void:
	if _frames == 2:
		var cam: LabCamera3D = bench.get_node("Camera3D") as LabCamera3D
		cam.go_to_station(1)
		cam.set("_zoom_target", 0.35)
	if _frames != 40:
		return
	var ids: Array = ["granite", "basalt", "sandstone", "shale", "gneiss", "pyrite_cluster", "galena",
		"amethyst", "emerald", "ruby", "trilobite", "malachite_ore", "river_sand"]
	if _args.has("newgems"):
		ids = ["pegmatite", "kimberlite", "eclogite", "ruby_marble", "copper_gossan", "gem_gravel", "travertine",
			"hiddenite", "taaffeite", "hauyne", "tugtupite", "clinohumite", "pink_sapphire", "chrysocolla"]
	for i: int in ids.size():
		var m: MineralData = Rock3D.get_mineral(ids[i])
		if m == null:
			continue
		var row: int = i / 7
		var rock: Rock3D = Rock3D.spawn(bench, m, Vector3(2.66 + 0.11 * float(i % 7), 1.08 - 0.11 * float(row), 0.35), m.typical_mass_kg * (3.0 if m.kind != MineralData.Kind.ROCK else 1.0))
		rock.freeze = true
		rock.rotation = Vector3(0.5, 0.4 * float(i), 0.2)



## Mineral Lab machines: a rock grinding in the crusher (gauge part-way), a
## bag in the sifter, and a rock carried over the crusher with its drop
## marker glowing.
func _machines_demo(bench: Node) -> void:
	var cam: LabCamera3D = bench.get_node("Camera3D") as LabCamera3D
	var grabber: TactileGrabber3D = bench.get_node("Grabber") as TactileGrabber3D
	var crusher: RockCrusher3D = bench.get_node("MineralLab/RockCrusher") as RockCrusher3D
	var sifter: SandSifter3D = bench.get_node("MineralLab/SandSifter") as SandSifter3D
	if _frames == 2:
		cam.go_to_station(1)
	if _frames == 70:
		Rock3D.spawn(bench, Rock3D.get_mineral("meteorite"), crusher.global_transform * Vector3(0.0, crusher.hopper_height_meters + 0.02, 0.0), 0.12)
		Rock3D.spawn(bench, Rock3D.get_mineral("desert_sand"), sifter.global_transform * Vector3(0.0, sifter.deck_height_meters + 0.12, 0.0), 0.2)
	if _frames == 90:
		crusher.set("_work_joules", crusher.required_work_joules(crusher.get("_current")) * 0.4 if crusher.get("_current") != null else 0.0)
		var held: Rock3D = Rock3D.spawn(bench, Rock3D.get_mineral("fizzrock"), Vector3(2.8, 1.0, 0.1), 0.06)
		grabber.grab(held)
	if _frames > 90:
		grabber._pointer_screen = cam.unproject_position(Vector3(2.62, 1.2, 0.1))


## Bottle seats: a flask in the hand over the spare bottle board (its free
## rings glowing) and the burner on a medium flame under the honey.
func _bottles_demo(bench: Node) -> void:
	var cam: Camera3D = bench.get_node("Camera3D") as Camera3D
	var grabber: TactileGrabber3D = bench.get_node("Grabber") as TactileGrabber3D
	if _frames == 3:
		var burner: Burner3D = bench.get_node("Stands/Burner") as Burner3D
		burner.set_level(2)
		var beaker: Vessel3D = bench.get_node("Vessels/Beaker") as Vessel3D
		beaker.global_position = burner.global_position + Vector3(0.0, burner.gauze_height_meters + 0.06, 0.0)
	if _frames == 20:
		grabber.grab(bench.get_node("Vessels/FlaskSpirits") as Vessel3D)
	if _frames > 20:
		var board: SupportStand3D = bench.get_node("Stands/BottleBoardSpare") as SupportStand3D
		grabber._pointer_screen = cam.unproject_position(board.seat_floor_world(0) + Vector3(0.0, 0.2, 0.0))
