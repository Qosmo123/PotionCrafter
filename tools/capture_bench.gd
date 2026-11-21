extends SceneTree
## Renders the bench (non-headless) and saves a PNG for visual review.
## Usage: godot --path . --script res://tools/capture_bench.gd -- <out.png> [pour]

const WARMUP_FRAMES: int = 90

var _frames: int = 0
var _out_path: String = "user://bench_capture.png"
var _bench: Node3D


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	# Debug switches: strip node groups to bisect rendering problems.
	for node_name: String in ["DustMotes", "BenchParticleCollider", "ToolCrock"]:
		if args.has("no" + node_name.to_lower()) and _bench.has_node(node_name):
			_bench.get_node(node_name).free()
	VesselEffects.disabled = args.has("noeffects")
	root.add_child(_bench)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2 and OS.get_cmdline_user_args().has("pour"):
		var moon: Vessel3D = _bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
		var beaker: Vessel3D = _bench.get_node("Vessels/Beaker") as Vessel3D
		moon.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		moon.freeze = true
		var tilt: Basis = Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(105.0))
		moon.global_transform = Transform3D(tilt, beaker.global_position + Vector3(0.0, 0.12, 0.0) - tilt.y * 0.07)
	if _frames == 3 and OS.get_cmdline_user_args().has("satchel"):
		var panel: CanvasLayer = _bench.get_node("InventoryPanel") as CanvasLayer
		panel.call(&"toggle")
		var tabs: TabContainer = panel.find_children("*", "TabContainer", true, false)[0] as TabContainer
		tabs.current_tab = 4 if OS.get_cmdline_user_args().has("recipes") else 0
		panel.call(&"refresh")
	if OS.get_cmdline_user_args().has("demo"):
		_demo()
	if OS.get_cmdline_user_args().has("demo2"):
		_demo2()
	if _frames < WARMUP_FRAMES:
		return false
	var image: Image = root.get_texture().get_image()
	image.save_png(_out_path)
	print("saved ", _out_path)
	return true


## Staged showcase: fizzing indicator reaction, a whisked bubble philtre, an
## arcane flare, and glowing chalk sigils.
func _demo() -> void:
	var beaker: Vessel3D = _bench.get_node("Vessels/Beaker") as Vessel3D
	var bubble: Vessel3D = _bench.get_node("Vessels/BubbleBase") as Vessel3D
	var moon: Vessel3D = _bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
	if _frames == 2:
		var reg: Callable = func(id: StringName) -> int: return SubstanceRegistry.index_of_id(id)
		beaker.mixture.add_substance(reg.call(&"water"), 10.0, 293.15)
		beaker.mixture.add_substance(reg.call(&"duskberry_juice"), 0.4, 293.15)
		beaker.mixture.add_substance(reg.call(&"acetic_acid"), 1.0, 293.15)
		beaker.mixture.add_substance(reg.call(&"baking_soda"), 0.6, 293.15)
		moon.mixture.add_substance(reg.call(&"emberberry_juice"), 0.6, 293.15)
		var chalk: ChalkDrawing3D = _bench.get_node("Chalk") as ChalkDrawing3D
		chalk.draw_world_stroke(ChalkDrawing3D.polygon_points(Vector2(-0.2, 0.12), 0.075, 3))
		chalk.draw_world_stroke(ChalkDrawing3D.polygon_points(Vector2(0.62, 0.12), 0.08, 6))
		chalk.draw_world_stroke(ChalkDrawing3D.polygon_points(Vector2(-0.42, 0.1), 0.06, 5))
	bubble.add_agitation(0.5)
	beaker.add_agitation(0.2)


## Second showcase: elephant's toothpaste, spirit fire, three-layer strata,
## a verditer cloud and a transmutation in progress.
func _demo2() -> void:
	var reg: Callable = func(id: StringName) -> int: return SubstanceRegistry.index_of_id(id)
	var beaker: Vessel3D = _bench.get_node("Vessels/Beaker") as Vessel3D
	var spirits: Vessel3D = _bench.get_node("Vessels/FlaskSpirits") as Vessel3D
	var strata: Vessel3D = _bench.get_node("Vessels/ReagentVinegar") as Vessel3D
	var cloud: Vessel3D = _bench.get_node("Vessels/ReagentBorax") as Vessel3D
	var moon: Vessel3D = _bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
	if _frames == 2:
		beaker.mixture.add_substance(reg.call(&"water"), 6.0, 293.15)
		beaker.mixture.add_substance(reg.call(&"hydrogen_peroxide"), 3.0, 293.15)
		beaker.mixture.add_substance(reg.call(&"soap_solution"), 2.0, 293.15)
		beaker.mixture.add_substance(reg.call(&"potassium_iodide"), 0.4, 293.15)
		spirits.mixture.add_substance(reg.call(&"ethanol"), 8.0, 293.15)
		strata.mixture.clear()
		strata.mixture.add_substance(reg.call(&"water"), 4.0, 293.15)
		strata.mixture.add_substance(reg.call(&"quicksilver"), 0.5, 293.15)
		strata.mixture.add_substance(reg.call(&"salamander_oil"), 0.12, 293.15)
		cloud.mixture.add_substance(reg.call(&"copper_sulfate"), 0.8, 293.15)
		cloud.mixture.add_substance(reg.call(&"caustic_lye"), 0.8, 293.15)
		moon.mixture.add_substance(reg.call(&"quicksilver"), 0.6, 293.15)
		moon.mixture.add_heat(60000.0)
	spirits.ignition_source = true
	moon.external_heat_watts += 400.0
