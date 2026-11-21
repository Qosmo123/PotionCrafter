extends SceneTree
## Smoke test for the easy controls on the real bench (side view).
## Usage: godot --path . --script res://tests/perf/smoke_easy.gd
## Each step waits for its outcome (with a time limit) rather than checking
## at fixed ticks, so it holds whatever the hand speeds are.
##   Pour   hold the moonwater flask over the beaker: it tips and pours by
##          itself; moving away stops it and it comes back upright.
##   Stir   hold the glass rod over the beaker and circle the pointer.
##   Swirl  hold a flask in the open and circle the pointer.
##   Seats  a vial into a free rack socket, a round flask onto a cork ring.
##   Tap    the beaker on the tap tray fills and stops; left running it
##          overflows into a puddle.
##   Heat   stove knob settings; the beaker on the lit burner warms up.

const TICKS_PER_S: float = 60.0

var _bench: Node3D
var _failures: PackedStringArray = PackedStringArray()
var _grabber: TactileGrabber3D
var _camera: Camera3D
var _moon: Vessel3D
var _beaker: Vessel3D
var _spirits: Vessel3D
var _rod: StirTool3D
var _soda: Vessel3D
var _tap: WaterTap3D
var _burner: Burner3D
var _rack: SupportStand3D
var _ring: SupportStand3D

var _step: int = 0
var _step_ticks: int = 0
var _total_ticks: int = 0
var _phase: float = 0.0
var _swirl_center: Vector2 = Vector2.ZERO
var _seen: Dictionary = {}
var _value: float = 0.0
var _beaker_start_m3: float = 0.0


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
	_tap = _bench.get_node("Stands/WaterTap") as WaterTap3D
	_burner = _bench.get_node("Stands/Burner") as Burner3D
	_rack = _bench.get_node("Stands/TubeRack") as SupportStand3D
	_ring = _bench.get_node("Stands/CorkRing3") as SupportStand3D


func _screen_above(v: Vessel3D, up_m: float) -> Vector2:
	return _camera.unproject_position(v.global_transform * Vector3(0.0, v.get_lip_local_y() + up_m, 0.0))


## Feed the grabber a circling pointer, as a player drawing circles would.
func _circle_pointer(center: Vector2, radius_px: float) -> void:
	_phase += 0.32
	var p: Vector2 = center + Vector2(cos(_phase), sin(_phase)) * radius_px
	_grabber._note_motion(p - _grabber._pointer_screen)
	_grabber._pointer_screen = p


func _next() -> void:
	_step += 1
	_step_ticks = 0


## True once `condition` holds, or once `seconds` have passed (then the
## caller's checks report what went wrong).
func _until(condition: bool, seconds: float) -> bool:
	return condition or _step_ticks > int(seconds * TICKS_PER_S)


func _physics_process(_delta: float) -> bool:
	_total_ticks += 1
	_step_ticks += 1
	if _total_ticks < 60:
		return false
	match _step:
		0:  # Pour the moonwater into the beaker.
			_check(_moon.axis_lock_angular_x and _moon.axis_lock_angular_y and not _moon.axis_lock_angular_z, "loose vessels only tip sideways (2D)")
			_check(_beaker.mixture.get_liquid_volume_m3() < _beaker.capacity_m3 * 0.5, "the beaker has room to fill")
			_beaker_start_m3 = _beaker.mixture.get_liquid_volume_m3()
			_grabber.grab(_moon)
			_next()
		1:
			_grabber._pointer_screen = _screen_above(_beaker, 0.1)
			if _grabber.pour_target == _beaker:
				_seen["pour_target"] = true
			if _grabber.assist_hint().begins_with("Pouring"):
				_seen["pour_hint"] = true
			_value = maxf(_value, absf(_grabber.pour_roll_rad))
			if _until(_moon.mixture.get_liquid_volume_m3() < 1e-6, 12.0):
				var gained_ml: float = (_beaker.mixture.get_liquid_volume_m3() - _beaker_start_m3) * 1e6
				_check(_seen.has("pour_target"), "holding the flask over the beaker picks it as the pour target")
				_check(_value > 1.0, "the flask tips by itself (max %.2f rad)" % _value)
				_check(gained_ml > 5.0, "moonwater pours into the beaker (+%.1f mL, spilled %.1f g)" % [gained_ml, _moon.spilled_mass_kg * 1000.0])
				_check(_moon.spilled_mass_kg < 0.002, "nothing spills on the way (%.1f g)" % (_moon.spilled_mass_kg * 1000.0))
				_check(_seen.has("pour_hint"), "the hint says it is pouring")
				_grabber._pointer_screen = _camera.unproject_position(_beaker.global_position + Vector3(-0.42, 0.15, 0.0))
				_next()
		2:  # Move away: the pour ends and the flask comes upright.
			if _until(_grabber.pour_target == null and absf(_grabber.pour_roll_rad) < 0.02, 4.0):
				_check(_grabber.pour_target == null, "moving away stops the pour")
				_check(absf(_grabber.pour_roll_rad) < 0.05, "the flask comes back upright (roll %.2f)" % _grabber.pour_roll_rad)
				_check(not _moon.is_pouring, "nothing pours once upright")
				_grabber.release()
				_grabber.grab(_rod)
				_value = 0.0
				_next()
		3:  # Stir the beaker by circling the pointer.
			if _step_ticks > 10:
				_circle_pointer(_screen_above(_beaker, 0.12), 26.0)
			if _grabber.stir_target == _beaker:
				_seen["stir"] = true
			_value = maxf(_value, absf(_beaker.mixture.swirl_rad_s))
			if _until(_value > 2.0, 8.0):
				_check(_seen.has("stir"), "holding the rod over the beaker starts stirring")
				_check(_value > 2.0, "circling the pointer spins the beaker's liquid (%.1f rad/s)" % _value)
				_grabber.release()
				_grabber.grab(_spirits)
				_swirl_center = _camera.unproject_position(_spirits.global_position + Vector3(0.0, 0.25, 0.0))
				_value = 0.0
				_next()
		4:  # Swirl the flask by hand.
			if _step_ticks > 10:
				_circle_pointer(_swirl_center, 30.0)
			if _grabber.swirling:
				_seen["swirl"] = true
			_value = maxf(_value, absf(_spirits.mixture.swirl_rad_s))
			if _until(_value > 3.0 and _step_ticks > 60, 8.0):
				_check(_seen.has("swirl"), "circling the pointer with a flask held swirls it")
				_check(_value > 3.0, "the flask's liquid spins (%.1f rad/s)" % _value)
				_grabber.put_down()
				_next()
		5:  # Put down: it finishes by itself, upright.
			if _until(_grabber.held_body == null, 5.0):
				_check(_grabber.held_body == null, "putting a flask down finishes by itself")
				_next()
		6:
			if _until(_spirits.linear_velocity.length() < 0.01, 2.0):
				_check(_spirits.global_basis.y.y > 0.99, "it is set down upright")
				_check(_rack.seat_count() == 6, "the rack has six sockets")
				_check(not _rack.is_seat_free(0) and _rack.is_seat_free(4), "the vials fill the first sockets, the rest are free")
				_grabber.grab(_soda)
				_next()
		7:  # Carry a vial to a free socket.
			var seat_x: float = _rack.seat_floor_world(4).x
			_grabber._pointer_screen = _camera.unproject_position(Vector3(seat_x, 0.97, -0.1))
			if _until(int(_grabber.dock_seat.get("index", -1)) == 4 and absf(_soda.global_position.x - seat_x) < 0.02, 8.0):
				_check(int(_grabber.dock_seat.get("index", -1)) == 4, "over a free socket, the vial picks it as its seat (%s)" % str(_grabber.dock_seat.get("index", "none")))
				_check(_grabber.assist_hint().begins_with("Click to set it"), "the hint offers the rack ('%s')" % _grabber.assist_hint())
				_grabber.put_down()
				_next()
		8:
			if _until(_grabber.held_body == null and _soda.linear_velocity.length() < 0.01, 6.0):
				var seat_x2: float = _rack.seat_floor_world(4).x
				_check(_grabber.held_body == null, "the vial is let go once seated")
				_check(absf(_soda.global_position.x - seat_x2) < 0.006, "the vial stands in its socket (off by %.1f mm)" % (absf(_soda.global_position.x - seat_x2) * 1000.0))
				_check(_soda.global_basis.y.y > 0.99, "the seated vial is upright")
				_grabber.grab(_moon)
				_next()
		9:  # A round flask onto a free cork ring.
			var ring_x: float = _ring.seat_floor_world(0).x
			_grabber._pointer_screen = _camera.unproject_position(Vector3(ring_x, 1.05, -0.1))
			if _until(not _grabber.dock_seat.is_empty() and absf(_moon.global_position.x - ring_x) < 0.03, 8.0):
				_check(not _grabber.dock_seat.is_empty(), "over a free cork ring, the round flask picks it as its seat")
				_grabber.put_down()
				_next()
		10:
			if _until(_grabber.held_body == null and _moon.linear_velocity.length() < 0.01, 6.0):
				var ring_x2: float = _ring.seat_floor_world(0).x
				_check(_grabber.held_body == null, "the flask is let go once seated")
				_check(absf(_moon.global_position.x - ring_x2) < 0.01, "the round flask sits in its cork ring (off by %.1f mm)" % (absf(_moon.global_position.x - ring_x2) * 1000.0))
				_check(_moon.global_basis.y.y > 0.98, "the seated flask is upright")
				_grabber.grab(_beaker)
				_next()
		11:  # The beaker onto the tap's tray.
			_grabber._pointer_screen = _camera.unproject_position(_tap.global_position + Vector3(0.0, 0.16, 0.0))
			if _until(not _grabber.dock_seat.is_empty() and absf(_beaker.global_position.x - _tap.global_position.x) < 0.02, 8.0):
				_check(not _grabber.dock_seat.is_empty(), "over the tap's tray, the beaker picks it as its seat")
				_grabber.put_down()
				_next()
		12:
			if _until(_grabber.held_body == null and _tap.filling == null and _tap.vessel_under() != null, 25.0):
				var frac: float = _beaker.get_fill_fraction()
				_check(_grabber.held_body == null, "the beaker is set on the tray")
				_check(frac > 0.85 and frac < 0.95, "the tap fills it and stops when nearly full (%.0f%%)" % (frac * 100.0))
				_check(_beaker.spilled_mass_kg < 1e-4, "no spills so far (%.1f g)" % (_beaker.spilled_mass_kg * 1000.0))
				_tap.running_free = true
				_next()
		13:  # Left running, it overflows into a puddle.
			if _until(SpillPuddles3D.total_volume_m3() > 2e-6, 12.0):
				_check(_beaker.spilled_mass_kg > 0.002, "left running, the full beaker overflows (%.1f g)" % (_beaker.spilled_mass_kg * 1000.0))
				_check(SpillPuddles3D.total_volume_m3() > 2e-6, "the overflow makes a puddle on the bench (%.1f mL)" % (SpillPuddles3D.total_volume_m3() * 1e6))
				_tap.running_free = false
				var plate: HotPlate3D = _bench.get_node("HotPlate") as HotPlate3D
				plate.set_level(1)
				_check(absf(plate.plate_temperature_kelvin - 420.0) < 0.1 and plate.heating_enabled, "the stove knob's low setting is 420 K")
				plate.set_level(0)
				_check(not plate.heating_enabled, "the stove's off setting stops heating")
				plate.set_level(3)
				_grabber.grab(_beaker)
				_next()
		14:  # The beaker onto the burner; light it.
			_grabber._pointer_screen = _camera.unproject_position(_burner.global_position + Vector3(0.0, 0.3, 0.0))
			if _until(not _grabber.dock_seat.is_empty() and absf(_beaker.global_position.x - _burner.global_position.x) < 0.02, 10.0):
				_check(not _grabber.dock_seat.is_empty(), "over the burner, the beaker picks the gauze as its seat")
				_grabber.put_down()
				_burner.toggle()
				_check(_burner.lit, "clicking the burner lights it")
				_next()
		15:
			if _until(_grabber.held_body == null and _beaker.linear_velocity.length() < 0.01, 6.0):
				_value = _beaker.mixture.temperature_kelvin
				_next()
		16:
			if _step_ticks > 300:
				var warmed: float = _beaker.mixture.temperature_kelvin - _value
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
