class_name TactileGrabber3D
extends Node3D
## 6DoF spring-damper manipulator shared by PC and Android.
##
## Held bodies are never teleported: a critically damped spring pulls the body's
## centre toward a point on a hover plane under the pointer, and a torque spring
## steers its orientation toward upright + the player's pour roll angle.
## Stiffness is fixed in N/m, so heavy objects have a lower natural frequency
## and visibly lag/sag while light glass feels crisp.
##
## PC:      click an item to pick it up (no need to hold the button), move
##          the mouse, click again to put it down. Press-and-drag also works.
##          Scroll wheel or right-drag = tilt/pour; Shift = slow, precise.
##          Items with a "click_use" action (the hammer) use it on the
##          second click when they have a target, instead of being dropped.
## Android: one finger = move, second finger twist = tilt/pour.
##
## Carry feel: the hand point under the cursor glides toward the pointer at a
## limited speed (it never jumps), so a quick mouse flick can't fling a light
## vial across the bench; objects let go with a capped speed so they settle
## instead of sliding away. Clicking near a small vial still picks it: if the
## exact ray misses, a small sphere around the cursor is tried.

const PICK_MASK: int = SimConstants.LAYER_RIGID_VESSEL | SimConstants.LAYER_SOLID_REAGENT | SimConstants.LAYER_TACTILE_TOOL
const PICK_DISTANCE_METERS: float = 12.0
const TOUCH_PICK_TARGET_DP: float = 48.0
const TOUCH_PICK_REFERENCE_DISTANCE_METERS: float = 1.2
const MAX_OMEGA_DT: float = 0.3

@export var camera: Camera3D
@export var hover_plane_y_meters: float = 0.98
@export var reach_radius_meters: float = 1.1

@export_group("Linear spring")
@export var stiffness_n_m: float = 420.0
@export var damping_ratio: float = 1.0
@export_range(0.0, 1.0) var gravity_compensation: float = 0.94
@export var max_force_n: float = 90.0

@export_group("Angular spring")
@export var angular_stiffness_rad_s2: float = 260.0
@export var angular_damping_ratio: float = 1.0
@export var max_angular_accel_rad_s2: float = 420.0

@export_group("Carry feel")
## Top speed the hand moves held items across the bench (m/s).
@export var carry_speed_m_s: float = 1.1
## Top speed with Shift held, for careful placement.
@export var precise_speed_m_s: float = 0.3
## How fast items lift to / lower from the carry height (m/s).
@export var lift_speed_m_s: float = 0.9
## Items are let go with at most this speed so they don't skid off (m/s).
@export var release_speed_m_s: float = 0.5
## Pick tolerance around the cursor for the mouse, in screen pixels.
@export var mouse_pick_radius_px: float = 14.0

@export_group("Tilt input")
@export var wheel_tilt_step_rad: float = 0.14
@export var mouse_tilt_rad_per_px: float = 0.008

## Set while another tool (e.g. chalk) owns pointer input.
static var input_captured: bool = false

var held_body: RigidBody3D = null
## Pour roll angle around the camera's horizontal forward axis, in [-PI, PI].
var pour_roll_rad: float = 0.0

var _pointer_screen: Vector2 = Vector2.ZERO
var _hold_yaw_rad: float = 0.0
var _pick_requested: bool = false
var _pick_is_touch: bool = false
var _mouse_tilting: bool = false
var _target_world: Vector3 = Vector3.ZERO
## Where the pointer says the hand should be; _target_world chases it.
var _pointer_target_world: Vector3 = Vector3.ZERO
var _tracked_body: RigidBody3D = null
## Mouse click-to-hold state.
var _press_pos: Vector2 = Vector2.ZERO
var _press_ms: int = 0
var _swallow_release: bool = false

const DRAG_PIXELS: float = 14.0
const DRAG_MS: int = 350
var _gravity_vector: Vector3 = Vector3.DOWN * SimConstants.GRAVITY_M_S2
var _pick_ray: RayCast3D
var _pick_cast: ShapeCast3D
var _pick_sphere: SphereShape3D
var _touch_primary_index: int = -1
var _touch_secondary_index: int = -1
var _touch_primary_pos: Vector2 = Vector2.ZERO
var _touch_secondary_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", SimConstants.GRAVITY_M_S2)
	var g_dir: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	_gravity_vector = g_dir * g

	_pick_ray = RayCast3D.new()
	_pick_ray.enabled = false
	_pick_ray.top_level = true
	_pick_ray.collision_mask = PICK_MASK
	add_child(_pick_ray)

	_pick_sphere = SphereShape3D.new()
	_pick_sphere.radius = 0.02
	_pick_cast = ShapeCast3D.new()
	_pick_cast.enabled = false
	_pick_cast.top_level = true
	_pick_cast.shape = _pick_sphere
	_pick_cast.max_results = 1
	_pick_cast.collision_mask = PICK_MASK
	add_child(_pick_cast)


# --- Input routing ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if input_captured and held_body == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_pointer_screen = mb.position
				if mb.pressed:
					_press_pos = mb.position
					_press_ms = Time.get_ticks_msec()
					if held_body == null:
						_request_pick(false)
					else:
						# Second click: use the item (hammer strike) or put it down.
						var used: bool = held_body.has_method(&"click_use") and bool(held_body.call(&"click_use"))
						if not used:
							release()
						_swallow_release = true
				else:
					if _swallow_release:
						_swallow_release = false
					elif mb.position.distance_to(_press_pos) > DRAG_PIXELS or Time.get_ticks_msec() - _press_ms > DRAG_MS:
						# It was a press-and-drag: let go like before.
						release()
					# A quick click keeps holding the item until the next click.
			MOUSE_BUTTON_RIGHT:
				_mouse_tilting = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed and held_body != null:
					_add_roll(wheel_tilt_step_rad)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and held_body != null:
					_add_roll(-wheel_tilt_step_rad)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_pointer_screen = mm.position
		if _mouse_tilting and held_body != null:
			_add_roll(-mm.relative.x * mouse_tilt_rad_per_px)
	elif event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)


func _handle_touch(st: InputEventScreenTouch) -> void:
	if st.device == InputEvent.DEVICE_ID_EMULATION:
		return  # Mouse already handled; ignore emulated touches.
	if st.pressed:
		if _touch_primary_index < 0:
			_touch_primary_index = st.index
			_touch_primary_pos = st.position
			_pointer_screen = st.position
			_request_pick(true)
		elif _touch_secondary_index < 0:
			_touch_secondary_index = st.index
			_touch_secondary_pos = st.position
	else:
		if st.index == _touch_primary_index:
			_touch_primary_index = -1
			_touch_secondary_index = -1
			release()
		elif st.index == _touch_secondary_index:
			_touch_secondary_index = -1


func _handle_drag(sd: InputEventScreenDrag) -> void:
	if sd.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if sd.index == _touch_primary_index:
		if _touch_secondary_index >= 0:
			_apply_twist(_touch_secondary_pos - _touch_primary_pos, _touch_secondary_pos - sd.position)
		_touch_primary_pos = sd.position
		_pointer_screen = sd.position
	elif sd.index == _touch_secondary_index:
		_apply_twist(_touch_secondary_pos - _touch_primary_pos, sd.position - _touch_primary_pos)
		_touch_secondary_pos = sd.position


func _apply_twist(before: Vector2, after: Vector2) -> void:
	if held_body == null or before.length_squared() < 1.0 or after.length_squared() < 1.0:
		return
	_add_roll(-before.angle_to(after))


func _add_roll(delta_rad: float) -> void:
	pour_roll_rad = clampf(pour_roll_rad + delta_rad, -PI, PI)


func _request_pick(is_touch: bool) -> void:
	_pick_requested = true
	_pick_is_touch = is_touch


## Put a body straight into the hand (Shift-click from the satchel). It then
## follows the pointer through the same spring-damper as a normal pick.
func grab(body: RigidBody3D) -> void:
	if body == null or body.freeze:
		return
	held_body = body
	held_body.sleeping = false
	_hold_yaw_rad = body.global_basis.get_euler().y
	pour_roll_rad = 0.0
	_target_world = body.global_position
	_pointer_target_world = _target_world


func release() -> void:
	if held_body != null and is_instance_valid(held_body):
		# Let go gently: cap the speed so the item settles where you dropped it.
		held_body.linear_velocity = held_body.linear_velocity.limit_length(release_speed_m_s)
		held_body.angular_velocity = held_body.angular_velocity.limit_length(4.0)
	held_body = null
	_mouse_tilting = false
	pour_roll_rad = 0.0


# --- Physics ---------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if camera == null:
		return
	if _pick_requested:
		_pick_requested = false
		_do_pick()
	if held_body == null:
		return
	if not is_instance_valid(held_body) or held_body.freeze:
		held_body = null
		return
	if held_body != _tracked_body:
		# Newly held (by pick, grab() or code): the hand starts where it is.
		_tracked_body = held_body
		_target_world = held_body.global_position
		_pointer_target_world = _target_world
	_update_target()
	_drive_linear()
	if not (held_body.has_method(&"wants_free_rotation") and held_body.call(&"wants_free_rotation")):
		_drive_angular()


func _do_pick() -> void:
	var origin: Vector3 = camera.project_ray_origin(_pointer_screen)
	var ray: Vector3 = camera.project_ray_normal(_pointer_screen) * PICK_DISTANCE_METERS
	_pick_ray.global_transform = Transform3D(Basis.IDENTITY, origin)
	_pick_ray.target_position = ray
	_pick_ray.force_raycast_update()
	var body: RigidBody3D = _pick_ray.get_collider() as RigidBody3D
	if body == null:
		# Inflate the pick hull so small stoppers/vials are easy to grab:
		# a 48 dp target for touch, a few pixels of slack for the mouse.
		_pick_sphere.radius = _touch_pick_radius_meters() if _pick_is_touch else _pixels_to_meters(mouse_pick_radius_px)
		_pick_cast.global_transform = Transform3D(Basis.IDENTITY, origin)
		_pick_cast.target_position = ray
		_pick_cast.force_shapecast_update()
		if _pick_cast.is_colliding():
			body = _pick_cast.get_collider(0) as RigidBody3D
	if body == null or body.freeze:
		return
	held_body = body
	held_body.sleeping = false
	_hold_yaw_rad = held_body.global_basis.get_euler().y
	pour_roll_rad = 0.0
	_target_world = held_body.global_position
	_pointer_target_world = _target_world


## Screen pixels -> metres at the typical working distance from the camera.
func _pixels_to_meters(px: float) -> float:
	var viewport_h: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var view_h_m: float = 2.0 * TOUCH_PICK_REFERENCE_DISTANCE_METERS * tan(deg_to_rad(camera.fov) * 0.5)
	return clampf(px * view_h_m / viewport_h, 0.003, 0.08)


func _touch_pick_radius_meters() -> float:
	var viewport_h: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var px_per_dp: float = maxf(DisplayServer.screen_get_dpi() / 160.0, 1.0)
	var radius_px: float = 0.5 * TOUCH_PICK_TARGET_DP * px_per_dp
	var view_h_m: float = 2.0 * TOUCH_PICK_REFERENCE_DISTANCE_METERS * tan(deg_to_rad(camera.fov) * 0.5)
	return clampf(radius_px * view_h_m / viewport_h, 0.005, 0.08)


func _update_target() -> void:
	var origin: Vector3 = camera.project_ray_origin(_pointer_screen)
	var dir: Vector3 = camera.project_ray_normal(_pointer_screen)
	if absf(dir.y) < 1e-4:
		return
	var plane_y: float = hover_plane_y_meters
	var overridden: bool = false
	if held_body.has_method(&"get_hover_offset_meters"):
		plane_y += held_body.call(&"get_hover_offset_meters") as float
	if held_body.has_method(&"get_hover_override_y"):
		var override_y: float = held_body.call(&"get_hover_override_y") as float
		if not is_nan(override_y):
			plane_y = override_y
			overridden = true
	var t: float = (plane_y - origin.y) / dir.y
	if t <= 0.0:
		return
	var hit: Vector3 = origin + dir * t
	var center: Vector3 = global_position
	var flat: Vector2 = Vector2(hit.x - center.x, hit.z - center.z).limit_length(reach_radius_meters)
	_pointer_target_world = Vector3(center.x + flat.x, plane_y, center.z + flat.y)
	# The hand glides toward the pointer at a capped speed (Shift = precise).
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var speed: float = precise_speed_m_s if Input.is_key_pressed(KEY_SHIFT) else carry_speed_m_s
	if held_body is MachineHandle3D:
		speed *= 3.0  # cranks and shaker handles need brisk strokes
	var cur_flat: Vector2 = Vector2(_target_world.x, _target_world.z)
	var want_flat: Vector2 = Vector2(_pointer_target_world.x, _pointer_target_world.z)
	cur_flat = cur_flat.move_toward(want_flat, speed * dt)
	# Machines that drive the height themselves (hammer slam) keep it instant.
	var y: float = plane_y if overridden else move_toward(_target_world.y, plane_y, lift_speed_m_s * dt)
	_target_world = Vector3(cur_flat.x, y, cur_flat.y)


func _drive_linear() -> void:
	var m: float = held_body.mass
	# Keep omega * dt small so the explicit spring stays stable even for very
	# light bodies (an emptied glass vial); heavy bodies keep the full stiffness.
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var k: float = minf(stiffness_n_m, m * pow(MAX_OMEGA_DT / dt, 2.0))
	var damping_n_s_m: float = 2.0 * damping_ratio * sqrt(k * m)
	var force: Vector3 = k * (_target_world - held_body.global_position) - damping_n_s_m * held_body.linear_velocity
	force -= _gravity_vector * m * held_body.gravity_scale * gravity_compensation
	held_body.apply_central_force(force.limit_length(max_force_n))


func _drive_angular() -> void:
	var cam_forward: Vector3 = -camera.global_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized() if cam_forward.length_squared() > 1e-6 else Vector3.FORWARD
	var desired: Basis = Basis(cam_forward, pour_roll_rad) * Basis(Vector3.UP, _hold_yaw_rad)
	var current: Basis = held_body.global_basis.orthonormalized()
	var q_err: Quaternion = (Quaternion(desired) * Quaternion(current).inverse()).normalized()
	if q_err.w < 0.0:
		q_err = -q_err
	var angle: float = q_err.get_angle()
	var axis: Vector3 = q_err.get_axis() if angle > 1e-5 else Vector3.ZERO
	var ang_damping: float = 2.0 * angular_damping_ratio * sqrt(angular_stiffness_rad_s2)
	var accel: Vector3 = axis * angle * angular_stiffness_rad_s2 - held_body.angular_velocity * ang_damping
	accel = accel.limit_length(max_angular_accel_rad_s2)
	held_body.apply_torque(accel * _approx_inertia_kg_m2(held_body))


func _approx_inertia_kg_m2(body: RigidBody3D) -> float:
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state != null:
		var inv: Vector3 = state.inverse_inertia
		var inv_sum: float = inv.x + inv.y + inv.z
		if inv_sum > 0.0:
			return 3.0 / inv_sum
	return body.mass * 0.002
