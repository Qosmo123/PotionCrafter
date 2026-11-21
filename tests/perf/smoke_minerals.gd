extends SceneTree
## Headless smoke test for the Mineral Lab: crate stocking, hammer cracking,
## crank-driven crushing (mass conserved into the tray), shaker-driven sifting,
## polishing and faceting. Machines are driven through their real joints.
## Usage: godot --headless --path . --script res://tests/perf/smoke_minerals.gd

const SETTLE: int = 60
const RUN: int = 900

var _bench: Node3D
var _tick: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _crusher: RockCrusher3D
var _sifter: SandSifter3D
var _polisher: LapidaryWheel3D
var _faceter: LapidaryWheel3D
var _rock_mass: float = 0.0
var _bag_mass: float = 0.0
var _gem_p: Rock3D
var _gem_f: Rock3D


func _initialize() -> void:
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_bench)
	_crusher = _bench.get_node("MineralLab/RockCrusher") as RockCrusher3D
	_sifter = _bench.get_node("MineralLab/SandSifter") as SandSifter3D
	_polisher = _bench.get_node("MineralLab/Polisher") as LapidaryWheel3D
	_faceter = _bench.get_node("MineralLab/Faceter") as LapidaryWheel3D


func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick == SETTLE:
		_setup()
	if _tick > SETTLE:
		_drive()
	if _tick == SETTLE + RUN:
		_verify()
		_finish()
		return true
	return false


func _setup() -> void:
	var rocks: int = _bench.get_tree().get_nodes_in_group(&"collectibles").size()
	_check(rocks >= 11, "crates are stocked with rocks and sand bags (%d)" % rocks)
	var journal: GrimoireJournal = _bench.get_node("GrimoireJournal") as GrimoireJournal
	# Hammer a geode open.
	var geode: Rock3D = Rock3D.spawn(_bench, Rock3D.get_mineral("geode"), Vector3(3.2, 0.95, 0.22), 0.15)
	var before: int = _bench.get_tree().get_nodes_in_group(&"collectibles").size()
	for _i: int in 20:
		if is_instance_valid(geode) and not geode.is_queued_for_deletion():
			geode.strike(5.0)
	_check(not is_instance_valid(geode) or geode.is_queued_for_deletion(), "hammer blows crack a geode")
	_check(journal != null, "journal present")
	# Rock in the crusher hopper.
	var rock: Rock3D = Rock3D.spawn(_bench, Rock3D.get_mineral("fizzrock"), _crusher.global_transform * Vector3(0.0, 0.3, 0.0), 0.08)
	rock.exhausted = true
	_rock_mass = rock.mass_kg
	# Sand bag in the sifter hopper.
	var bag: Rock3D = Rock3D.spawn(_bench, Rock3D.get_mineral("desert_sand"), _sifter.global_transform * Vector3(0.0, 0.32, 0.0), 0.2)
	_bag_mass = bag.mass_kg
	# Gems on the running wheels.
	_polisher.toggle()
	_faceter.toggle()
	_gem_p = _place_gem("crystal_quartz", _polisher, 0.0)
	_gem_f = _place_gem("garnet", _faceter, 0.5)


func _place_gem(id: String, wheel: LapidaryWheel3D, polish: float) -> Rock3D:
	var gem: Rock3D = Rock3D.spawn(_bench, Rock3D.get_mineral(id), wheel.global_transform * Vector3(0.0, wheel.wheel_height_meters + 0.015, 0.0), 0.01)
	gem.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	gem.freeze = true
	gem.set_polish(polish)
	return gem


func _drive() -> void:
	# Crank: torque about the crusher's vertical axis through the real hinge.
	var crank: MachineHandle3D = _crusher._handle
	if crank != null:
		var arm: Vector3 = crank.global_position - (_crusher.global_transform * Vector3(0.0, _crusher.crank_height_meters, 0.0))
		crank.apply_central_force(Vector3.UP.cross(arm).normalized() * 3.0)
	# Shaker: alternate push along the slider.
	var shaker: MachineHandle3D = _sifter._handle
	if shaker != null:
		shaker.apply_central_force(_sifter.global_basis.x * (6.0 if (_tick / 10) % 2 == 0 else -6.0))


func _verify() -> void:
	var tray: Vessel3D = _bench.get_node("MineralLab/CrusherTray") as Vessel3D
	var powder_kg: float = tray.mixture.get_total_mass_kg()
	_check(absf(powder_kg - _rock_mass) < 1e-6, "crusher turns the whole rock into powder (%.1f g of %.1f g)" % [powder_kg * 1000.0, _rock_mass * 1000.0])
	var sifted: float = 0.0
	for n: String in ["SiftTrayCoarse", "SiftTrayMedium", "SiftTrayFine"]:
		sifted += (_bench.get_node("MineralLab/" + n) as Vessel3D).mixture.get_total_mass_kg()
	var left: float = 0.0
	for k: float in _sifter.charge_kg:
		left += k
	_check(sifted > _bag_mass * 0.3, "shaking sifts sand into the trays (%.0f g of %.0f g)" % [sifted * 1000.0, _bag_mass * 1000.0])
	_check(absf(sifted + (left if _sifter._charge_total_kg > 0.0 else 0.0) - _bag_mass) < 1e-6 or _sifter._charge_total_kg == 0.0, "sifting conserves sand mass")
	_check(_gem_p.polish > 0.5, "the polisher polishes quartz (%.0f%%)" % (_gem_p.polish * 100.0))
	_check(_gem_f.cut != RockMeshes.Cut.NONE, "the faceting machine cuts a garnet (cut %d, quality %.2f)" % [_gem_f.cut, _gem_f.cut_quality])
	print("powder %.1f g, sifted %.0f g, polish %.0f%%, cut %s q=%.2f value %d" % [powder_kg * 1000.0, sifted * 1000.0, _gem_p.polish * 100.0,
		RockMeshes.CUT_NAMES[_gem_f.cut], _gem_f.cut_quality, _gem_f.value()])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MINERAL SMOKE PASS")
		quit(0)
	else:
		for f: String in _failures:
			printerr("MINERAL SMOKE FAIL  " + f)
		quit(1)
