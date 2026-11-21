extends SceneTree
## Headless integration smoke test for the main bench scene.
## Usage: godot --headless --path . --script res://tests/perf/smoke_bench.gd
## Checks settling, pouring between vessels (with conservation), hot-plate
## heating, grabber spring tracking, and arcane gravity coupling.

const SETTLE_TICKS: int = 90
const POUR_TICKS: int = 240
const TOTAL_TICKS: int = SETTLE_TICKS + POUR_TICKS

var _bench: Node3D
var _tick: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _moon: Vessel3D
var _beaker: Vessel3D
var _spirits: Vessel3D
var _vial: Vessel3D
var _grabber: TactileGrabber3D
var _rod: StirTool3D
var _honey: Vessel3D
var _honey_start_y: float = 0.0
var _whisk_taken: RigidBody3D
var _vinegar_taken: Vessel3D
var _mass_before_pour: float = 0.0
var _spirits_start_kelvin: float = 0.0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main_bench.tscn") as PackedScene
	_bench = scene.instantiate() as Node3D
	root.add_child(_bench)
	_moon = _bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
	_beaker = _bench.get_node("Vessels/Beaker") as Vessel3D
	_spirits = _bench.get_node("Vessels/FlaskSpirits") as Vessel3D
	_vial = _bench.get_node("Vessels/VialQuicksilver") as Vessel3D
	_grabber = _bench.get_node("Grabber") as TactileGrabber3D
	_rod = _bench.get_node("StirTools/GlassRod") as StirTool3D
	_honey = _bench.get_node("Vessels/FlaskHoney") as Vessel3D


func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick == 1:
		# Spirits flask starts on the hot plate.
		var plate: Node3D = _bench.get_node("HotPlate") as Node3D
		_spirits.global_position = plate.global_position + Vector3(0.0, 0.01 + 0.5 * _spirits.profile.height_meters + 0.003, 0.0)
		_spirits_start_kelvin = _spirits.mixture.temperature_kelvin
		var cam: Camera3D = _bench.get_node("Camera3D") as Camera3D
		_check((-cam.global_basis.z).y < -0.05, "camera should look slightly down at the bench")
	if _tick == SETTLE_TICKS:
		_check_settled()
		_start_pour()
		_grabber.held_body = _vial
		_grabber._pointer_screen = root.get_visible_rect().size * 0.5
		var store: InventoryStore = _bench.get_node("InventoryStore") as InventoryStore
		_vinegar_taken = store.take("reagent:Vinegar") as Vessel3D
		_whisk_taken = store.take("tool:whisk")
		_check(_vinegar_taken != null and _whisk_taken != null, "satchel spawns a reagent bottle and a tool")
		_check(int(store.find_item("tool:whisk")["count"]) == 0, "taking the only whisk empties its slot")
		var chalk: ChalkDrawing3D = _bench.get_node("Chalk") as ChalkDrawing3D
		_honey_start_y = _honey.global_position.y
		var c: Vector2 = Vector2(_honey.global_position.x, _honey.global_position.z)
		var sigil: SigilRecognizer.Result = chalk.draw_world_stroke(ChalkDrawing3D.polygon_points(c, 0.07, 5))
		_check(sigil.kind == SigilRecognizer.Kind.PENTAGON, "chalk pentagram recognised (%s)" % sigil.describe())
	if _tick > SETTLE_TICKS:
		_stir_spirits()
	if _tick >= TOTAL_TICKS:
		_check_after_pour()
		_finish()
		return true
	return false


func _stir_spirits() -> void:
	# Drive the glass rod kinematically in circles inside the spirits bottle.
	if not _rod.freeze:
		_rod.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_rod.freeze = true
	var phase: float = float(_tick - SETTLE_TICKS) * SimConstants.TICK_SECONDS * 7.0
	var bottom: Vector3 = _spirits.global_transform * Vector3(0.0, _spirits.get_cavity_bottom_local_y() + 0.02, 0.0)
	var tip: Vector3 = bottom + Vector3(cos(phase), 0.0, sin(phase)) * 0.014
	_rod.global_transform = Transform3D(Basis.IDENTITY, tip + Vector3.UP * (0.5 * _rod.length_meters - 0.006))


func _check_settled() -> void:
	for node: Node in _bench.get_tree().get_nodes_in_group(&"vessels"):
		var v: Vessel3D = node as Vessel3D
		_check(v.global_position.y > 0.78, "%s fell through the bench (y=%.3f)" % [v.name, v.global_position.y])
		_check(v.global_basis.y.y > 0.95, "%s tipped over while settling" % v.name)
	var crock: ToolCrock3D = _bench.get_node("ToolCrock") as ToolCrock3D
	for tool_name: String in ["GlassRod", "SilverRod", "WoodenSpoon", "Whisk", "ArcaneWand"]:
		var tool: StirTool3D = _bench.get_node("StirTools/" + tool_name) as StirTool3D
		_check(crock.contains_xz(tool.global_position, 0.03) and tool.global_basis.y.y > 0.85, "%s should stand upright in the crock" % tool_name)
	var g: float = _moon.gravity_scale
	_check(g > 0.0 and g < 0.5, "moonwater should make its flask lighter (gravity_scale=%.3f)" % g)


func _start_pour() -> void:
	_moon.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_moon.freeze = true
	var tilt: Basis = Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(105.0))
	var axis: Vector3 = tilt.y
	var top_offset: Vector3 = axis * (0.5 * _moon.profile.height_meters)
	var target_lip: Vector3 = _beaker.global_position + Vector3(0.0, 0.12, 0.0)
	_moon.global_transform = Transform3D(tilt, target_lip - top_offset)
	_mass_before_pour = _moon.mixture.get_total_mass_kg() + _beaker.mixture.get_total_mass_kg()


func _check_after_pour() -> void:
	var beaker_kg: float = _beaker.mixture.get_total_mass_kg()
	var moon_kg: float = _moon.mixture.get_total_mass_kg()
	_check(beaker_kg > 0.01, "beaker should receive poured moonwater (got %.4f kg)" % beaker_kg)
	var accounted: float = moon_kg + beaker_kg + _moon.spilled_mass_kg + _moon.vented_mass_kg + _beaker.spilled_mass_kg + _beaker.vented_mass_kg
	_check(absf(accounted - _mass_before_pour) < 1e-9, "pour must conserve mass (drift %s kg)" % str(accounted - _mass_before_pour))
	_check(absf(_spirits.mixture.swirl_rad_s) > 1.0, "glass rod should spin the spirits (swirl=%.2f rad/s)" % _spirits.mixture.swirl_rad_s)
	_check(_honey.global_position.y > _honey_start_y + 0.03, "pentagram should levitate the honey flask (rose %.3f m)" % (_honey.global_position.y - _honey_start_y))
	_check(_vinegar_taken.mixture != null and _vinegar_taken.mixture.get_liquid_volume_m3() > 1e-4, "spawned vinegar bottle is filled (%.0f mL)" % (_vinegar_taken.mixture.get_liquid_volume_m3() * 1e6))
	var store: InventoryStore = _bench.get_node("InventoryStore") as InventoryStore
	_check(store.stash(_whisk_taken) and int(store.find_item("tool:whisk")["count"]) == 1, "stashing returns the whisk to storage")
	_check_bottling()
	var warmed: float = _spirits.mixture.temperature_kelvin - _spirits_start_kelvin
	_check(warmed > 5.0, "hot plate should warm the spirits flask (+%.2f K)" % warmed)
	_check(absf(_vial.global_position.y - _grabber.hover_plane_y_meters) < 0.03, "grabbed vial should track the hover plane (y=%.3f)" % _vial.global_position.y)
	print("swirl %.2f rad/s, " % _spirits.mixture.swirl_rad_s, "beaker %.1f mL, spilled %.2f g, spirits +%.1f K, vial y %.3f" % [
		_beaker.mixture.get_liquid_volume_m3() * 1e6, _moon.spilled_mass_kg * 1000.0, warmed, _vial.global_position.y])


func _check_bottling() -> void:
	var journal: GrimoireJournal = _bench.get_node("GrimoireJournal") as GrimoireJournal
	var hud: HudOverlay = _bench.get_node("HudOverlay") as HudOverlay
	var glue: Vessel3D = _bench.get_node("Vessels/ReagentGlue") as Vessel3D
	glue.mixture.add_substance(SubstanceRegistry.index_of_id(&"borax_solution"), 3.75, 293.15)
	journal.commissions = [{"recipe_id": "borax_slime", "title": "Borax Slime", "min_grade": "F", "reward": 50, "client": "a test"}]
	var coins_before: int = journal.coins
	hud.bottle(glue)
	_check(glue.sealed and not glue.open_top, "bottling corks the vessel")
	_check(journal.cellar.size() >= 1 and String(journal.cellar[0]["recipe_id"]) == "borax_slime", "the cellar records the slime as Borax Slime")
	_check(journal.coins == coins_before + 50, "the slime fulfils the commission (+50 coins)")
	_check(journal.commissions.size() == GrimoireJournal.ACTIVE_COMMISSIONS, "the board refills with new orders")
	hud.bottle(glue)
	_check(not glue.sealed and glue.open_top, "pressing B again uncorks")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE PASS")
		quit(0)
	else:
		for f: String in _failures:
			printerr("SMOKE FAIL  " + f)
		quit(1)
