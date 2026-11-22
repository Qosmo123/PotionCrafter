extends SceneTree
## Smoke test for powders (Vessel3D granular mode) on the real bench:
##   Mode     a vial of salt of soda and a beaker of calcite powder are
##            powders, with an angle of repose from their data.
##   Heap     tilted 20 degrees the heap turns with the glass (a liquid would
##            stay level) and nothing pours; tilted 70 degrees it has slipped
##            back to its angle of repose.
##   Hand     the vial held over the round flask (bigger) and clicked tips
##            its powder in through the hand's pour assist.
##   Spill    the beaker tipped right over the bench trickles a steady
##            stream (about the same rate full and nearly empty) into a heap.
## Usage: godot --path . --resolution 1280x720 --script res://tests/perf/smoke_powder.gd

const TICKS_PER_S: float = 60.0

var _bench: Node3D
var _grabber: TactileGrabber3D
var _camera: Camera3D
var _vial: Vessel3D
var _flask: Vessel3D
var _beaker: Vessel3D
var _failures: int = 0
var _step: int = 0
var _t: int = 0
var _vial_start_kg: float = 0.0
var _flask_start_kg: float = 0.0
var _seen: Dictionary = {}
var _rates_early: Array[float] = []
var _rates_late: Array[float] = []
var _beaker_start_m3: float = 0.0


func _initialize() -> void:
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_bench)
	_grabber = _bench.get_node("Grabber") as TactileGrabber3D
	_camera = _bench.get_node("Camera3D") as Camera3D
	_vial = _bench.get_node("Vessels/VialSoda") as Vessel3D
	_flask = _bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
	_beaker = _bench.get_node("Vessels/Beaker") as Vessel3D


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _next() -> void:
	_step += 1
	_t = 0


func _tilt(v: Vessel3D, degrees: float) -> void:
	var p: Vector3 = v.global_position
	v.global_transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(-degrees)), p)
	v.linear_velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO


func _physics_process(_d: float) -> bool:
	_t += 1
	match _step:
		0:
			if _t == 30:
				_flask.mixture.clear()
				_beaker.mixture.clear()
				_beaker.mixture.add_substance(SubstanceRegistry.index_of_id(&"calcite_powder"), 0.6, 293.15)
				_beaker.freeze = true
				_beaker.global_position = _beaker.global_position + Vector3(0.0, 0.25, 0.0)
			if _t == 40:
				_check(_vial.granular and _vial.mixture.get_solid_volume_m3() > 1e-6, "the salt of soda vial holds a powder (%.1f mL)" % (_vial.mixture.get_solid_volume_m3() * 1e6))
				_check(_beaker.granular, "calcite powder in the beaker is a powder")
				_check(_beaker.repose_deg > 25.0 and _beaker.repose_deg < 58.0, "angle of repose from the data: %.1f deg" % _beaker.repose_deg)
				_tilt(_beaker, 20.0)
				_next()
		1:
			if _t == 30:
				var a: float = rad_to_deg(_beaker.get_heap_normal_world().angle_to(Vector3.UP))
				_check(a > 15.0, "tilted 20 deg the heap turns with the glass (surface at %.1f deg; a liquid stays level)" % a)
				_check(not _beaker.is_pouring, "and nothing pours")
				_tilt(_beaker, 70.0)
			if _t == 60:
				var a2: float = rad_to_deg(_beaker.get_heap_normal_world().angle_to(Vector3.UP))
				_check(a2 <= _beaker.repose_deg + Vessel3D.AVALANCHE_OVERSHOOT_DEG + 0.5 and a2 > _beaker.repose_deg - 6.0, "tilted 70 deg it slips back to its angle of repose (%.1f deg)" % a2)
				_tilt(_beaker, 0.0)
				_vial_start_kg = _vial.mixture.get_solid_mass_kg()
				_flask_start_kg = _flask.mixture.get_total_mass_kg()
				_grabber.grab(_vial)
				_next()
		2:
			_grabber._pointer_screen = _camera.unproject_position(_flask.global_transform * Vector3(0.0, _flask.get_lip_local_y() + 0.1, 0.0))
			if _grabber.pour_candidate == _flask and _grabber.pour_target == null and not _seen.has("clicked"):
				_seen["clicked"] = true
				_check(_grabber.assist_hint().begins_with("Click to tip the powder"), "the hint offers to tip the powder in (\"%s\")" % _grabber.assist_hint())
				var press: InputEventMouseButton = InputEventMouseButton.new()
				press.button_index = MOUSE_BUTTON_LEFT
				press.pressed = true
				press.position = _grabber._pointer_screen
				_grabber._unhandled_input(press)
				var up: InputEventMouseButton = press.duplicate() as InputEventMouseButton
				up.pressed = false
				_grabber._unhandled_input(up)
			if _vial.is_pouring:
				_seen["poured"] = true
			if _vial.mixture.get_solid_mass_kg() < _vial_start_kg * 0.05 or _t > int(20.0 * TICKS_PER_S):
				var gained_g: float = (_flask.mixture.get_total_mass_kg() - _flask_start_kg) * 1000.0
				_check(_seen.has("clicked"), "holding the vial over the round flask offers a pour")
				_check(_seen.has("poured"), "the vial tips until the powder flows")
				_check(gained_g > _vial_start_kg * 1000.0 * 0.8, "the powder goes into the bigger flask (+%.1f g of %.1f g, spilled %.2f g, %.1f s)" % [gained_g, _vial_start_kg * 1000.0, _vial.spilled_mass_kg * 1000.0, _t / TICKS_PER_S])
				_check(_flask.granular, "and lies there as a powder")
				_grabber.release()
				_beaker_start_m3 = _beaker.mixture.get_solid_volume_m3()
				_tilt(_beaker, 125.0)
				_next()
		3:
			var left: float = _beaker.mixture.get_solid_volume_m3() / maxf(_beaker_start_m3, 1e-12)
			if _beaker.is_pouring:
				if left > 0.75:
					_rates_early.append(_beaker.pour_rate_m3_s)
				elif left < 0.4 and left > 0.1:
					_rates_late.append(_beaker.pour_rate_m3_s)
			if left < 0.08 or _t > int(40.0 * TICKS_PER_S):
				var early: float = _mean(_rates_early)
				var late: float = _mean(_rates_late)
				_check(early > 0.0 and late > 0.0 and late / early > 0.33 and late / early < 3.0, "the trickle is steady: %.1f mL/s full, %.1f mL/s nearly empty" % [early * 1e6, late * 1e6])
				_check(PowderPiles3D.total_volume_m3() > _beaker_start_m3 * 0.5, "spilled powder heaps up on the bench (%.1f mL)" % (PowderPiles3D.total_volume_m3() * 1e6))
				_check(SpillPuddles3D.total_volume_m3() < 1e-7, "and makes no puddle")
				print("SMOKE %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
				quit(1 if _failures > 0 else 0)
	return false


func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s: float = 0.0
	for x: float in a:
		s += x
	return s / float(a.size())
