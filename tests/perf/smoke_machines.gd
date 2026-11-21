extends SceneTree
## Smoke test: the Mineral Lab machines driven through the real hand, the way
## a player uses the mouse (not by pushing bodies directly).
## Usage: godot --path . --resolution 1280x720 --script res://tests/perf/smoke_machines.gd
##   Sifter   carry a sand bag over the sifter, click: it drops in; drag the
##            shaker handle left and right: it travels its stroke and sifts.
##   Crusher  carry a rock over the crusher, click: it drops in; drag the
##            crank in circles: the rock is ground to powder.

const TICKS_PER_S: float = 60.0

var _bench: Node3D
var _grabber: TactileGrabber3D
var _camera: LabCamera3D
var _crusher: RockCrusher3D
var _sifter: SandSifter3D
var _failures: PackedStringArray = PackedStringArray()
var _step: int = 0
var _step_ticks: int = 0
var _total: int = 0
var _item: Rock3D
var _min_x: float = INF
var _max_x: float = -INF
var _base: Vector2
var _phase: float = 0.0
var _tray_start_kg: float = 0.0


func _initialize() -> void:
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_bench)
	_grabber = _bench.get_node("Grabber") as TactileGrabber3D
	_camera = _bench.get_node("Camera3D") as LabCamera3D
	_crusher = _bench.get_node("MineralLab/RockCrusher") as RockCrusher3D
	_sifter = _bench.get_node("MineralLab/SandSifter") as SandSifter3D


func _click(at: Vector2) -> void:
	_grabber._pointer_screen = at
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = at
	e.pressed = true
	_grabber._unhandled_input(e)
	var up: InputEventMouseButton = e.duplicate() as InputEventMouseButton
	up.pressed = false
	_grabber._unhandled_input(up)


func _move(p: Vector2) -> void:
	_grabber._note_motion(p - _grabber._pointer_screen)
	_grabber._pointer_screen = p


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _next() -> void:
	_step += 1
	_step_ticks = 0


func _until(condition: bool, seconds: float) -> bool:
	return condition or _step_ticks > int(seconds * TICKS_PER_S)


func _tray_kg(v: Vessel3D) -> float:
	return v.mixture.get_total_mass_kg() if v.mixture != null else 0.0


func _physics_process(_d: float) -> bool:
	_total += 1
	_step_ticks += 1
	match _step:
		0:
			_camera.go_to_station(1)
			_next()
		1:  # Let the camera arrive and everything settle, then take a sand bag.
			if _step_ticks > 80:
				_item = Rock3D.spawn(_bench, Rock3D.get_mineral("desert_sand"), _sifter.global_transform * Vector3(-0.3, 0.05, 0.42), 0.2)
				_next()
		2:
			if _step_ticks == 40:
				_click(_camera.unproject_position(_item.global_position))
			if _step_ticks > 45:
				_check(_grabber.held_body == _item, "the sand bag can be picked up")
				_next()
		3:  # Carry it over the sifter.
			_move(_camera.unproject_position(_sifter.global_transform * Vector3(0.0, 0.4, 0.0)))
			if _until(_grabber.intake_target != null and absf(_item.global_position.x - _sifter.global_position.x) < 0.03, 8.0):
				_check(_grabber.intake_target != null, "carrying a sand bag over the sifter marks it as the drop target")
				_check(_grabber.assist_hint().contains("sand sifter"), "the hint says to click to drop it in (\"%s\")" % _grabber.assist_hint())
				_click(_grabber._pointer_screen)
				_next()
		4:
			if _until(_sifter._charge_total_kg > 0.0, 3.0):
				_check(_sifter._charge_total_kg > 0.0, "the sand bag drops into the sifter")
				_base = _camera.unproject_position(_sifter._handle.global_position)
				_click(_base)
				_next()
		5:
			if _step_ticks > 5:
				_check(_grabber.held_body == _sifter._handle, "the shaker handle can be grabbed")
				_next()
		6:  # Shake at a human pace: about one stroke a second, a hand-width wide.
			_phase += TAU * 1.1 / TICKS_PER_S
			_move(_base + Vector2(sin(_phase) * 90.0, 0.0))
			var lx: float = (_sifter.global_transform.affine_inverse() * _sifter._handle.global_position).x
			_min_x = minf(_min_x, lx)
			_max_x = maxf(_max_x, lx)
			if _step_ticks > int(5.0 * TICKS_PER_S):
				var travel: float = _max_x - _min_x
				_check(travel > SandSifter3D.STROKE_METERS * 1.4, "dragging the handle shakes the sieve through its stroke (%.0f of %.0f mm)" % [travel * 1000.0, SandSifter3D.STROKE_METERS * 2000.0])
				var sifted: float = 0.0
				for k: int in 3:
					sifted += _tray_kg(_sifter.trays[k])
				_check(sifted > 0.02, "shaking sifts sand into the trays (%.0f g)" % (sifted * 1000.0))
				_grabber.release()
				_item = Rock3D.spawn(_bench, Rock3D.get_mineral("fizzrock"), _crusher.global_transform * Vector3(-0.15, 0.05, 0.42), 0.08)
				_next()
		7:  # A rock into the crusher.
			if _step_ticks == 40:
				_click(_camera.unproject_position(_item.global_position))
			if _step_ticks > 45:
				_move(_camera.unproject_position(_crusher.global_transform * Vector3(0.0, _crusher.hopper_height_meters + 0.12, 0.0)))
				if _until(_grabber.intake_target != null and absf(_item.global_position.x - _crusher.global_position.x) < 0.03, 8.0):
					_check(_grabber.intake_target != null, "carrying a rock over the crusher marks it as the drop target")
					_click(_grabber._pointer_screen)
					_next()
		8:
			if _until(_crusher._current != null, 3.0):
				_check(_crusher._current == _item, "the rock drops into the crusher hopper")
				_tray_start_kg = _tray_kg(_crusher.tray)
				_click(_camera.unproject_position(_crusher._handle.global_position))
				_next()
		9:  # Turn the crank: circle the pointer round the crank axis.
			if _step_ticks == 3:
				_check(_grabber.held_body == _crusher._handle, "the crank can be grabbed")
			var axis: Vector3 = _crusher.global_transform * Vector3(0.0, _crusher.crank_height_meters, 0.0)
			_phase += TAU * 0.8 / TICKS_PER_S
			var at: Vector3 = axis + Vector3(cos(_phase), 0.0, sin(_phase)) * RockCrusher3D.CRANK_RADIUS_METERS
			_move(_camera.unproject_position(at))
			if _until(_crusher._current == null, 25.0):
				_check(_crusher._current == null, "cranking grinds the rock (progress %.0f%%)" % (_crusher.progress * 100.0))
				_check(_tray_kg(_crusher.tray) > _tray_start_kg + 0.05, "the powder lands in the crusher's beaker (+%.0f g)" % ((_tray_kg(_crusher.tray) - _tray_start_kg) * 1000.0))
				_grabber.release()
				_next()
		10:
			print("SMOKE MACHINES %s (%d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
			quit(0 if _failures.is_empty() else 1)
	return false
