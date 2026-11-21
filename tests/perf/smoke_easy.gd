extends SceneTree
## Smoke test for the easy controls on the real bench (side view).
## Usage: godot --path . --script res://tests/perf/smoke_easy.gd
##   Pour   hold the moonwater flask over the beaker: it tips and pours by
##          itself; moving away stops it and it comes back upright.
##   Stir   hold the glass rod over the beaker and circle the pointer: the
##          beaker's liquid spins.
##   Swirl  hold a flask in the open and circle the pointer: its liquid spins.
##   2D     loose objects stay in their lane; a held one is free in depth.

var _bench: Node3D
var _tick: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _grabber: TactileGrabber3D
var _camera: Camera3D
var _moon: Vessel3D
var _beaker: Vessel3D
var _spirits: Vessel3D
var _rod: StirTool3D
var _soda: Vessel3D
var _seat_x: float = 0.0
var _ring_x: float = 0.0
var _tap: WaterTap3D
var _burner: Burner3D
var _start_kelvin: float = 0.0
var _beaker_start_m3: float = 0.0
var _saw_pour_target: bool = false
var _max_roll: float = 0.0
var _max_beaker_swirl: float = 0.0
var _saw_stir_target: bool = false
var _max_spirits_swirl: float = 0.0
var _saw_swirling: bool = false
var _phase: float = 0.0
var _saw_pour_hint: bool = false
var _swirl_center: Vector2 = Vector2.ZERO


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main_bench.tscn") as PackedScene
	_bench = scene.instantiate() as Node3D
	root.add_child(_bench)
	_grabber = _bench.get_node("Grabber") as TactileGrabber3D
	_camera = _bench.get_node("Camera3D") as Camera3D
	_moon = _bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
	_beaker = _bench.get_node("Vessels/Beaker") as Vessel3D
	_spirits = _bench.get_node("Vessels/FlaskSpirits") as Vessel3D
	_rod = _bench.get_node("StirTools/GlassRod") as StirTool3D
	_soda = _bench.get_node("Vessels/VialSoda") as Vessel3D


func _screen_above(v: Vessel3D, up_m: float) -> Vector2:
	return _camera.unproject_position(v.global_transform * Vector3(0.0, v.get_lip_local_y() + up_m, 0.0))


## Feed the grabber a circling pointer, as a player drawing circles would.
func _circle_pointer(center: Vector2, radius_px: float) -> void:
	_phase += 0.32
	var p: Vector2 = center + Vector2(cos(_phase), sin(_phase)) * radius_px
	_grabber._note_motion(p - _grabber._pointer_screen)
	_grabber._pointer_screen = p


func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick == 60:
		_check(_moon.axis_lock_angular_x and _moon.axis_lock_angular_y and not _moon.axis_lock_angular_z, "loose vessels only tip sideways (2D)")
		_check(_beaker.mixture.get_liquid_volume_m3() < _beaker.capacity_m3 * 0.5, "the beaker has room to fill")
		_beaker_start_m3 = _beaker.mixture.get_liquid_volume_m3()
		_grabber.grab(_moon)
		_grabber._pointer_screen = _screen_above(_beaker, 0.1)
	if _tick > 60 and _tick < 330:
		_grabber._pointer_screen = _screen_above(_beaker, 0.1)
		_saw_pour_target = _saw_pour_target or _grabber.pour_target == _beaker
		_saw_pour_hint = _saw_pour_hint or _grabber.assist_hint().begins_with("Pouring")
		_max_roll = maxf(_max_roll, absf(_grabber.pour_roll_rad))
	if _tick == 330:
		var gained_ml: float = (_beaker.mixture.get_liquid_volume_m3() - _beaker_start_m3) * 1e6
		_check(_saw_pour_target, "holding the flask over the beaker picks it as the pour target")
		_check(_max_roll > 1.0, "the flask tips by itself (max %.2f rad)" % _max_roll)
		_check(gained_ml > 5.0, "moonwater pours into the beaker (+%.1f mL, spilled %.1f g)" % [gained_ml, _moon.spilled_mass_kg * 1000.0])
		_check(_saw_pour_hint, "the hint says it is pouring")
		# Move well away to the left.
		_grabber._pointer_screen = _camera.unproject_position(_beaker.global_position + Vector3(-0.42, 0.15, 0.0))
	if _tick == 430:
		_check(_grabber.pour_target == null, "moving away stops the pour")
		_check(absf(_grabber.pour_roll_rad) < 0.05, "the flask comes back upright (roll %.2f)" % _grabber.pour_roll_rad)
		_check(not _moon.is_pouring, "nothing pours once upright")
		_grabber.release()
	if _tick == 440:
		_grabber.grab(_rod)
		_grabber._pointer_screen = _screen_above(_beaker, 0.12)
	if _tick > 450 and _tick < 640:
		_circle_pointer(_screen_above(_beaker, 0.12), 26.0)
		_saw_stir_target = _saw_stir_target or _grabber.stir_target == _beaker
		_max_beaker_swirl = maxf(_max_beaker_swirl, absf(_beaker.mixture.swirl_rad_s))
	if _tick == 640:
		_check(_saw_stir_target, "holding the rod over the beaker starts stirring")
		_check(_max_beaker_swirl > 2.0, "circling the pointer spins the beaker's liquid (%.1f rad/s)" % _max_beaker_swirl)
		_grabber.release()
	if _tick == 650:
		_grabber.grab(_spirits)
		_swirl_center = _camera.unproject_position(_spirits.global_position + Vector3(0.0, 0.25, 0.0))
	if _tick > 660 and _tick < 820:
		# Out in the open, away from other vessels.
		_circle_pointer(_swirl_center, 30.0)
		_saw_swirling = _saw_swirling or _grabber.swirling
		_max_spirits_swirl = maxf(_max_spirits_swirl, absf(_spirits.mixture.swirl_rad_s))
	if _tick == 820:
		_check(_saw_swirling, "circling the pointer with a flask held swirls it")
		_check(_max_spirits_swirl > 3.0, "the flask's liquid spins (%.1f rad/s)" % _max_spirits_swirl)
		_grabber.put_down()
	if _tick == 960:
		_check(_grabber.held_body == null, "putting a flask down finishes by itself")
		_check(_spirits.global_basis.y.y > 0.99, "it is set down upright")
		# Seats: carry a vial to a free rack socket.
		var rack: SupportStand3D = _bench.get_node("Stands/TubeRack") as SupportStand3D
		_check(rack.seat_count() == 6, "the rack has six sockets")
		_check(not rack.is_seat_free(0) and rack.is_seat_free(4), "the vials fill the first sockets, the rest are free")
		_seat_x = rack.seat_floor_world(4).x
		_grabber.grab(_soda)
	if _tick > 960 and _tick < 1050:
		_grabber._pointer_screen = _camera.unproject_position(Vector3(_seat_x, 0.97, -0.1))
	if _tick == 1050:
		var seat: Dictionary = _grabber.dock_seat
		_check(not seat.is_empty() and int(seat.get("index", -1)) == 4, "over a free socket, the vial picks it as its seat (%s)" % str(seat.get("index", "none")))
		_check(_grabber.assist_hint().begins_with("Click to set it"), "the hint offers the rack ('%s')" % _grabber.assist_hint())
		_grabber.put_down()
	if _tick == 1170:
		_check(_grabber.held_body == null, "the vial is let go once seated")
		_check(absf(_soda.global_position.x - _seat_x) < 0.006, "the vial stands in its socket (off by %.1f mm)" % (absf(_soda.global_position.x - _seat_x) * 1000.0))
		_check(_soda.global_basis.y.y > 0.99, "the seated vial is upright")
		# A round flask onto a free cork ring.
		var ring: SupportStand3D = _bench.get_node("Stands/CorkRing3") as SupportStand3D
		_ring_x = ring.seat_floor_world(0).x
		_grabber.grab(_moon)
	if _tick > 1170 and _tick < 1320:
		_grabber._pointer_screen = _camera.unproject_position(Vector3(_ring_x, 1.05, -0.1))
	if _tick == 1320:
		_check(not _grabber.dock_seat.is_empty(), "over a free cork ring, the round flask picks it as its seat")
		_grabber.put_down()
	if _tick == 1460:
		_check(_grabber.held_body == null, "the flask is let go once seated")
		_check(absf(_moon.global_position.x - _ring_x) < 0.01, "the round flask sits in its cork ring (off by %.1f mm)" % (absf(_moon.global_position.x - _ring_x) * 1000.0))
		_check(_moon.global_basis.y.y > 0.98, "the seated flask is upright")
		# Water tap: set the beaker on the tap's tray.
		_tap = _bench.get_node("Stands/WaterTap") as WaterTap3D
		_beaker_start_m3 = _beaker.mixture.get_liquid_volume_m3()
		_grabber.grab(_beaker)
	if _tick > 1460 and _tick < 1640:
		_grabber._pointer_screen = _camera.unproject_position(_tap.global_position + Vector3(0.0, 0.16, 0.0))
	if _tick == 1640:
		_check(not _grabber.dock_seat.is_empty(), "over the tap's tray, the beaker picks it as its seat")
		_grabber.put_down()
	if _tick == 2240:
		_check(_grabber.held_body == null, "the beaker is set on the tray")
		var frac: float = _beaker.get_fill_fraction()
		_check(frac > 0.85 and frac < 0.95, "the tap fills it and stops when nearly full (%.0f%%)" % (frac * 100.0))
		_check(SpillPuddles3D.total_volume_m3() < 1e-7, "no spills so far")
		_tap.running_free = true
	if _tick == 2600:
		_check(_beaker.spilled_mass_kg > 0.005, "left running, the full beaker overflows (%.1f g)" % (_beaker.spilled_mass_kg * 1000.0))
		_check(SpillPuddles3D.total_volume_m3() > 2e-6, "the overflow makes a puddle on the bench (%.1f mL)" % (SpillPuddles3D.total_volume_m3() * 1e6))
		_tap.running_free = false
		# Burner: carry the beaker of water onto the gauze, light it.
		_burner = _bench.get_node("Stands/Burner") as Burner3D
		var plate: HotPlate3D = _bench.get_node("HotPlate") as HotPlate3D
		plate.set_level(1)
		_check(absf(plate.plate_temperature_kelvin - 420.0) < 0.1 and plate.heating_enabled, "the stove knob's low setting is 420 K")
		plate.set_level(0)
		_check(not plate.heating_enabled, "the stove's off setting stops heating")
		plate.set_level(3)
		_grabber.grab(_beaker)
	if _tick > 2600 and _tick < 2800:
		_grabber._pointer_screen = _camera.unproject_position(_burner.global_position + Vector3(0.0, 0.3, 0.0))
	if _tick == 2800:
		_check(not _grabber.dock_seat.is_empty(), "over the burner, the beaker picks the gauze as its seat")
		_grabber.put_down()
		_burner.toggle()
		_check(_burner.lit, "clicking the burner lights it")
	if _tick == 2900:
		_start_kelvin = _beaker.mixture.temperature_kelvin
	if _tick == 3200:
		var warmed: float = _beaker.mixture.temperature_kelvin - _start_kelvin
		_check(_grabber.held_body == null and absf(_beaker.global_position.x - _burner.global_position.x) < 0.02, "the beaker sits on the burner")
		_check(warmed > 1.0, "the lit burner heats the water (+%.1f K in 5 s)" % warmed)
		_burner.toggle()
		_finish()
		return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("EASY SMOKE PASS")
		quit(0)
	else:
		for f: String in _failures:
			printerr("EASY SMOKE FAIL  " + f)
		quit(1)
