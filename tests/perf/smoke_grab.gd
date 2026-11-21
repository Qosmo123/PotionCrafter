extends SceneTree
## Headless check of the carry feel: picking a flask near (not exactly on) the
## cursor, moving it at a capped speed even when the pointer jumps across the
## bench, and letting it go gently.
## Usage: godot --headless --path . --script res://tests/perf/smoke_grab.gd

var _bench: Node3D
var _grabber: TactileGrabber3D
var _vial: Vessel3D
var _camera: Camera3D
var _tick: int = 0
var _max_speed: float = 0.0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_bench)
	_grabber = _bench.get_node("Grabber") as TactileGrabber3D
	_vial = _bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
	_camera = _bench.get_node("Camera3D") as Camera3D


func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick == 60:
		# Click a few pixels beside the vial: the inflated pick should still get it.
		var center: Vector2 = _camera.unproject_position(_vial.global_position + Vector3(0.0, 0.02, 0.0))
		var screen: Vector2 = center
		# Walk outward from the vessel's centre to just past its silhouette edge.
		for step: int in range(1, 200):
			var probe: Vector2 = center + Vector2(float(step), 0.0)
			if _ray_hits_nothing(probe):
				screen = probe + Vector2(4.0, 0.0)  # 4 px outside the edge
				break
		_grabber._pointer_screen = screen
		_grabber._request_pick(false)
	if _tick == 62:
		_check(_grabber.held_body == _vial, "clicking just outside the flask's edge still picks it up")
		_grabber.held_body = _vial
		# Flick the pointer to the far side of the bench in one frame.
		_grabber._pointer_screen = root.get_visible_rect().size * Vector2(0.1, 0.55)
	if _tick > 62 and _tick < 150:
		_max_speed = maxf(_max_speed, Vector2(_vial.linear_velocity.x, _vial.linear_velocity.z).length())
	if _tick == 150:
		_check(_max_speed <= _grabber.carry_speed_m_s * 1.35, "a pointer flick moves the vial at a calm speed (max %.2f m/s)" % _max_speed)
		_check(_max_speed > 0.3, "the vial still follows the pointer (max %.2f m/s)" % _max_speed)
		_vial.linear_velocity = Vector3(3.0, 0.0, 0.0)
		_grabber.release()
		_check(_vial.linear_velocity.length() <= _grabber.release_speed_m_s + 1e-4, "letting go caps the speed (%.2f m/s)" % _vial.linear_velocity.length())
		if _failures.is_empty():
			print("GRAB SMOKE PASS")
		else:
			for f: String in _failures:
				printerr("FAIL: " + f)
			print("GRAB SMOKE FAIL")
		quit(0 if _failures.is_empty() else 1)
	return false


## True when the exact pointer ray at `screen` touches no pickable body.
func _ray_hits_nothing(screen: Vector2) -> bool:
	var origin: Vector3 = _camera.project_ray_origin(screen)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + _camera.project_ray_normal(screen) * 12.0, TactileGrabber3D.PICK_MASK)
	return _bench.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
