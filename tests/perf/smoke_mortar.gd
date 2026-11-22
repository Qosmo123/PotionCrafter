extends SceneTree
## Smoke test for the mortar and pestle on the real bench:
##   Drop     a small rock let go over the mortar drops in and sits there.
##   Grind    the pestle held over the mortar and circled (the hand's assist)
##            wears the rock down: coarse chunk -> grit -> powder.
##   Finer    grinding on makes the powder finer (grain_surface rises).
##   Pound    a hard blow strikes sparks (an ignition source).
##   Tip out  the mortar held over the beaker and clicked tips the powder in.
## Usage: godot --path . --resolution 1280x720 --script res://tests/perf/smoke_mortar.gd

const TICKS_PER_S: float = 60.0

var _bench: Node3D
var _grabber: TactileGrabber3D
var _camera: Camera3D
var _mortar: MortarBowl3D
var _pestle: Pestle3D
var _beaker: Vessel3D
var _rock: Rock3D
var _failures: int = 0
var _step: int = 0
var _t: int = 0
var _phase: float = 0.0
var _seen: Dictionary = {}
var _powder_kg: float = 0.0


func _initialize() -> void:
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_bench)
	_grabber = _bench.get_node("Grabber") as TactileGrabber3D
	_camera = _bench.get_node("Camera3D") as Camera3D
	_mortar = _bench.get_node("Furniture/Mortar") as MortarBowl3D
	_pestle = _bench.get_node("Furniture/Pestle") as Pestle3D
	_beaker = _bench.get_node("Vessels/Beaker") as Vessel3D


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _next() -> void:
	_step += 1
	_t = 0


func _over(v: Vessel3D, up_m: float) -> Vector2:
	return _camera.unproject_position(v.global_transform * Vector3(0.0, v.get_lip_local_y() + up_m, 0.0))


func _circle(center: Vector2, radius_px: float) -> void:
	_phase += 0.32
	var p: Vector2 = center + Vector2(cos(_phase), sin(_phase)) * radius_px
	_grabber._note_motion(p - _grabber._pointer_screen)
	_grabber._pointer_screen = p


func _click() -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _grabber._pointer_screen
	_grabber._unhandled_input(press)
	var up: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	up.pressed = false
	_grabber._unhandled_input(up)


func _physics_process(_d: float) -> bool:
	_t += 1
	match _step:
		0:
			if _t == 40:
				_check(_mortar != null and _pestle != null, "the mortar and pestle are on the bench")
				_check(_mortar.capacity_m3 > 2e-5, "the mortar is a vessel (%.0f mL bowl)" % (_mortar.capacity_m3 * 1e6))
				_mortar.mixture.clear()
				var m: MineralData = Rock3D.get_mineral("soda_lake_crust")
				_rock = Rock3D.spawn(_bench, m, _mortar.global_position + Vector3(0.0, 0.15, 0.0), 0.04)
			if _t == 120:
				_check(_mortar.rocks.has(_rock), "a rock let go over the mortar drops into the bowl")
				_check(_mortar.grind_stage() == "coarse chunk", "it starts as a coarse chunk")
				_grabber.grab(_pestle)
				_next()
		1:
			_circle(_over(_mortar, 0.06), 40.0)
			var stage: String = _mortar.grind_stage()
			if stage != "":
				_seen[stage] = true
			if _grabber.assist_hint().begins_with("Grinding"):
				_seen["hint"] = true
			if (_mortar.rocks.is_empty() and _mortar.mixture.get_solid_mass_kg() > 0.0) or _t > int(40.0 * TICKS_PER_S):
				_powder_kg = _mortar.mixture.get_solid_mass_kg()
				_check(_seen.has("hint"), "holding the pestle over the mortar grinds (the hint says so)")
				_check(_mortar.rocks.is_empty(), "the rock is ground away (%.1f s)" % (_t / TICKS_PER_S))
				_check(_seen.has("grit"), "it goes through grit on the way")
				_check(_powder_kg > 0.03, "and turns into powder in the bowl (%.1f g of 40 g)" % (_powder_kg * 1000.0))
				_check(_mortar.granular, "which lies there as a powder")
				_next()
		2:
			_circle(_over(_mortar, 0.06), 40.0)
			if _mortar.mixture.grain_surface > 2.5 or _t > int(30.0 * TICKS_PER_S):
				_check(_mortar.mixture.grain_surface > 2.5, "grinding on makes it finer (%s, x%.2f surface, %.1f s)" % [_mortar.grind_stage(), _mortar.mixture.grain_surface, _t / TICKS_PER_S])
				_check(_mortar.mixture.temperature_kelvin > 293.0, "grinding warms the powder a little (%.2f K)" % _mortar.mixture.temperature_kelvin)
				_mortar.ignition_source = false
				_mortar.grind(0.01, 60.0, 1.2)
				_check(_mortar.ignition_source, "a hard blow with the pestle strikes sparks")
				_grabber.release()
				_pestle.global_position = _mortar.global_position + Vector3(0.2, 0.05, 0.1)
				_beaker.mixture.clear()
				_next()
		3:
			if _t == 20:
				_grabber.grab(_mortar)
			if _t > 20:
				_grabber._pointer_screen = _over(_beaker, 0.1)
				if _grabber.pour_candidate == _beaker and _grabber.pour_target == null and not _seen.has("clicked"):
					_seen["clicked"] = true
					_click()
			var in_beaker: float = _beaker.mixture.get_solid_mass_kg()
			if in_beaker > _powder_kg * 0.8 or _t > int(20.0 * TICKS_PER_S):
				_check(_seen.has("clicked"), "holding the mortar over the beaker offers to tip it")
				_check(in_beaker > _powder_kg * 0.8, "the powder is tipped into the beaker (%.1f g of %.1f g)" % [in_beaker * 1000.0, _powder_kg * 1000.0])
				_check(_beaker.mixture.grain_surface > 2.0, "and keeps its fine grind (x%.2f)" % _beaker.mixture.grain_surface)
				print("SMOKE %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
				quit(1 if _failures > 0 else 0)
	return false
