extends SceneTree
## Smoke test: right-drag pans the view, empty-handed and while carrying a
## flask (which keeps following the pointer and stays upright); panning
## stops at its limit; the station key re-centres.
## Usage: godot --path . --resolution 1280x720 --script res://tests/perf/smoke_pan.gd

var _bench: Node3D
var _camera: LabCamera3D
var _grabber: TactileGrabber3D
var _tick: int = 0
var _start: Vector3
var _failures: int = 0


func _initialize() -> void:
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_bench)
	_camera = _bench.get_node("Camera3D") as LabCamera3D
	_grabber = _bench.get_node("Grabber") as TactileGrabber3D


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _right(pressed: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = pressed
	_camera._unhandled_input(e)
	_grabber._unhandled_input(e)


func _drag(rel: Vector2) -> void:
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.relative = rel
	_camera._unhandled_input(m)
	_grabber._unhandled_input(m)


func _process(_d: float) -> bool:
	_tick += 1
	match _tick:
		30:
			_start = _camera.global_position
			_right(true)
			for i: int in 10:
				_drag(Vector2(-20.0, 0.0))  # drag the bench left: view moves right
			_right(false)
		70:
			var moved: Vector3 = _camera.global_position - _start
			_check(moved.x > 0.1, "right-drag with empty hands moves the view (%.0f mm)" % (moved.x * 1000.0))
			_right(true)
			for i: int in 200:
				_drag(Vector2(-40.0, 0.0))
			_right(false)
		110:
			var moved: Vector3 = _camera.global_position - _start
			_check(moved.x <= LabCamera3D.PAN_LIMIT_METERS.x + 0.01, "panning stops at its limit (%.0f mm)" % (moved.x * 1000.0))
			_camera.go_to_station(0)  # same station key: re-centre
		160:
			_check(_camera.global_position.distance_to(_start) < 0.01, "pressing the station key re-centres the view")
			_grabber.grab(_bench.get_node("Vessels/FlaskMoonwater") as RigidBody3D)
		170:
			_start = _camera.global_position
			_right(true)
			for i: int in 10:
				_drag(Vector2(-20.0, 0.0))
			_right(false)
		200:
			_check(_camera.global_position.x - _start.x > 0.1, "carrying a flask, right-drag moves the view (%.0f mm)" % ((_camera.global_position.x - _start.x) * 1000.0))
			_check(_grabber.held_body != null, "the flask stays in the hand while panning")
			_check(absf(_grabber.pour_roll_rad) < 0.01, "panning doesn't tilt the flask")
			print("PAN SMOKE %s" % ("PASS" if _failures == 0 else "FAIL"))
			quit(0 if _failures == 0 else 1)
	return false
