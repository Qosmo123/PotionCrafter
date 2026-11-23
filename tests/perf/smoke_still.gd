extends SceneTree
## Smoke test for the still head on the real bench:
##   Fit      the head held over a flask on the burner and clicked fits it.
##   Distil   with the burner on full, what boils off drips from the arm into
##            the beaker set under it: spirit comes over before water.
##   Conserve flask + arm + beaker + losses = what was in the flask.
##   Lift     clicking the fitted head lifts it off into the hand.
## Usage: godot --path . --resolution 1280x720 --script res://tests/perf/smoke_still.gd

const TICKS_PER_S: float = 60.0

var _bench: Node3D
var _grabber: TactileGrabber3D
var _camera: Camera3D
var _head: StillHead3D
var _flask: Vessel3D
var _beaker: Vessel3D
var _burner: Burner3D
var _failures: int = 0
var _step: int = 0
var _t: int = 0
var _seen: Dictionary = {}
var _start_kg: float = 0.0
var _eth: int = 0
var _water: int = 0


func _initialize() -> void:
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_bench)
	_grabber = _bench.get_node("Grabber") as TactileGrabber3D
	_camera = _bench.get_node("Camera3D") as Camera3D
	_head = _bench.get_node("Furniture/StillHead") as StillHead3D
	_flask = _bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
	_beaker = _bench.get_node("Vessels/Beaker") as Vessel3D
	_burner = _bench.get_node("Stands/Burner") as Burner3D
	_eth = SubstanceRegistry.index_of_id(&"ethanol")
	_water = SubstanceRegistry.index_of_id(&"water")


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _next() -> void:
	_step += 1
	_t = 0


func _click() -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _grabber._pointer_screen
	_grabber._unhandled_input(press)
	var up: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	up.pressed = false
	_grabber._unhandled_input(up)


func _total_kg() -> float:
	return _flask.mixture.get_total_mass_kg() + _head.condenser.get_total_mass_kg() + _beaker.mixture.get_total_mass_kg() \
		+ _head.vented_kg + _head.spilled_kg + _flask.vented_mass_kg + _flask.spilled_mass_kg + _beaker.vented_mass_kg + _beaker.spilled_mass_kg


func _physics_process(_d: float) -> bool:
	_t += 1
	match _step:
		0:
			if _t == 40:
				_check(_head != null and _head.flask == null, "the still head lies loose on the bench")
				_flask.mixture.clear()
				_flask.mixture.add_substance(_water, 1.5, 340.0)
				_flask.mixture.add_substance(_eth, 0.25, 340.0)
				_grabber.grab(_flask)
			if _t > 40 and _grabber.held_body == _flask:
				# Carry the flask over the burner and click: it settles on the gauze.
				_grabber._pointer_screen = _camera.unproject_position(_burner.global_position + Vector3(0.0, 0.3, 0.0))
				if not _grabber.dock_seat.is_empty() and absf(_flask.global_position.x - _burner.global_position.x) < 0.02 and not _grabber.placing and not _seen.has("seat"):
					_seen["seat"] = true
					_click()
			if _seen.has("seat") and _grabber.held_body == null and _t > 100 and not _seen.has("on"):
				_seen["on"] = true
				_check(absf(_flask.global_position.x - _burner.global_position.x) < 0.02 and _flask.global_basis.y.y > 0.95, "the flask sits on the burner")
				_grabber.grab(_head)
				_next()
			if _t > int(15.0 * TICKS_PER_S):
				_check(false, "the flask goes onto the burner")
				quit(1)
		1:
			_grabber._pointer_screen = _camera.unproject_position(_flask.global_transform * Vector3(0.0, _flask.get_lip_local_y() + 0.09, 0.0))
			if _grabber.fit_target == _flask and _grabber.assist_hint().begins_with("Click to fit"):
				_seen["hint"] = true
			if _seen.has("hint") and not _seen.has("clicked") and _t > 30:
				_seen["clicked"] = true
				_click()
			if _t == 200:
				_check(_seen.has("hint"), "holding the head over the flask offers to fit it")
				_check(_head.flask == _flask and _flask.still_head == _head, "a click fits it on the flask")
				_check(not _flask.can_pour_contents(), "a capped flask can't be poured")
				# Set the beaker under the arm's tip, then light the burner.
				var tip: Vector3 = _head.arm_tip_world()
				_beaker.mixture.clear()
				_beaker.global_position = Vector3(tip.x, _beaker.global_position.y, 0.12)
				_beaker.linear_velocity = Vector3.ZERO
				_start_kg = _total_kg()
				_burner.set_level(3)
				_next()
		2:
			if _head.receiver == _beaker:
				_seen["into"] = true
			var got_kg: float = _beaker.mixture.get_total_mass_kg()
			if got_kg > 0.006 or _t > int(60.0 * TICKS_PER_S):
				var eth_kg: float = _beaker.mixture.moles[_eth] * 0.04607
				_check(got_kg > 0.006, "distillate drips into the beaker (%.1f g in %.1f s, flask %.1f K)" % [got_kg * 1000.0, _t / TICKS_PER_S, _flask.mixture.temperature_kelvin])
				_check(_seen.has("into"), "the arm drips into the beaker under it")
				_check(eth_kg > got_kg * 0.6, "spirit comes over first (%.0f%% spirit)" % (100.0 * eth_kg / maxf(got_kg, 1e-9)))
				_check(_beaker.mixture.temperature_kelvin < 320.0, "the distillate arrives cool (%.1f K)" % _beaker.mixture.temperature_kelvin)
				_check(absf(_total_kg() - _start_kg) < 1e-6, "nothing is made or lost (%s kg off)" % str(_total_kg() - _start_kg))
				_check(_head.global_position.distance_to(_flask.global_transform * Vector3(0.0, _flask.get_lip_local_y(), 0.0)) < 0.03, "the head stays on the flask")
				_burner.set_level(0)
				_grabber.release()
				_next()
		3:
			if _t == 20:
				_grabber._pointer_screen = _camera.unproject_position(_head.global_transform * Vector3(0.0, 0.06, 0.0))
				_click()
			if _t == 60:
				_check(_grabber.held_body == _head and _head.flask == null and _flask.still_head == null, "clicking the fitted head lifts it off into the hand")
				_check(_flask.can_pour_contents(), "and the flask pours again")
				print("SMOKE %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
				quit(1 if _failures > 0 else 0)
	return false
