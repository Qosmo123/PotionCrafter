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
##          Scroll wheel = tilt/pour; Shift = slow, precise. (Right-drag moves
##          the view, see LabCamera3D.)
##          Items with a "click_use" action (the hammer) use it on the
##          second click when they have a target, instead of being dropped.
## Android: one finger = move, second finger twist = tilt/pour.
##
## Side view (2.5D, orthographic camera): the cursor moves held items left/
## right and up/down only. Depth is automatic: a column of downward probes at
## the cursor finds the surface under it in the 2D view (anvil, machine,
## another vessel's rim, the bench) and the item slides to that depth and
## hovers just above it, so pouring and placing never need depth control.
## Cranks (machine handles) keep the classic horizontal-plane drag.
##
## Easy handling (side view):
##   Pour   hold a vessel over another one: after a moment it tips by itself,
##          its lip lined up over the other mouth, and pours until you move
##          away, click, or the other vessel is nearly full.
##   Stir   hold a stirring tool over a vessel: it dips into the liquid; wiggle
##          or circle the mouse (or hold S) to stir. Circling sets the direction.
##   Swirl  holding a vessel anywhere else, circle the mouse (or hold S): the
##          glass is swished round in little circles and the liquid spins.
##
##   Seats  vials and round flasks glide into the nearest free rack socket or
##          cork ring when let go near one (glowing markers show where).
##   Set down  anything let go elsewhere is straightened first, then lowered.
##   Hover  whatever a click would pick up glows softly and the cursor
##          becomes a hand.
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
@export var carry_speed_m_s: float = 0.55
## Top speed with Shift held, for careful placement.
@export var precise_speed_m_s: float = 0.18
## How fast items lift to / lower from the carry height (m/s).
@export var lift_speed_m_s: float = 0.5
## Items are let go with at most this speed so they don't skid off (m/s).
@export var release_speed_m_s: float = 0.5
## Pick tolerance around the cursor for the mouse, in screen pixels.
@export var mouse_pick_radius_px: float = 14.0

@export_group("Side view")
## Depth range the auto-depth probes search (world z), front to back.
@export var probe_front_z: float = 0.5
@export var probe_back_z: float = -0.4
@export var probe_step_z: float = 0.06
## Lowest the hand may go (just above the bench top).
@export var floor_y_meters: float = 0.81

@export_group("Tilt input")
@export var wheel_tilt_step_rad: float = 0.14
@export var mouse_tilt_rad_per_px: float = 0.008

## Set while another tool (e.g. chalk) owns pointer input.
static var input_captured: bool = false
## What the hands hold right now (machines read it to leave held items alone).
static var current_held: RigidBody3D = null

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
var _probe: RayCast3D
## Height from the held item's centre to its underside (measured at pick-up).
var _half_height: float = 0.03
var _probe_tick: int = 0
var _surface_y: float = 0.8
var _surface_z: float = 0.15
## Mouse click-to-hold state.
var _press_pos: Vector2 = Vector2.ZERO
var _press_ms: int = 0
var _swallow_release: bool = false

const DRAG_PIXELS: float = 14.0
const DRAG_MS: int = 350
## Pour assist: how close (beyond the target's mouth radius) the cursor must
## come to start, how far it may wander before it stops, and the wait.
const POUR_ENTER_METERS: float = 0.05
const POUR_EXIT_METERS: float = 0.11
const ASSIST_DWELL_S: float = 0.18
const POUR_FULL_FRACTION: float = 0.93
const POUR_MAX_ROLL_RAD: float = 2.1
## A comfortable assisted pour: ~25 mL/s, scaled by the wheel (0.25x..3x).
const POUR_TARGET_RATE_M3_S: float = 2.5e-5
## Stir and swirl strength.
const STIR_RAD_PER_PX: float = 0.02
const MAX_STIR_RAD_S: float = 12.0
const KEY_STIR_RAD_S: float = 8.0
const SWIRL_TURN_THRESHOLD_RAD_S: float = 2.5
const ARM_TRAVEL_METERS: float = 0.07
const ARM_HOLD_SECONDS: float = 1.2
## How close (left/right) the item must be to a free seat to glide into it.
const SEAT_CATCH_METERS: float = 0.045
const PLACE_TIMEOUT_S: float = 2.6
var _gravity_vector: Vector3 = Vector3.DOWN * SimConstants.GRAVITY_M_S2
var _pick_ray: RayCast3D
var _pick_cast: ShapeCast3D
var _pick_sphere: SphereShape3D
## Assists: the vessel being poured into / stirred, and whether the held
## vessel is being swirled by hand.
var pour_target: Vessel3D = null
## The vessel a pour would go into: it glows and the hint says "click to
## pour"; nothing pours until the player clicks (pour_target is then set).
var pour_candidate: Vessel3D = null
## The machine hopper a carried rock would drop into on the next click.
var intake_target: MachineIntake = null
var _marked: Node3D = null
static var _target_mat: ShaderMaterial = null
## The tap the held vessel is being filled at (held under its spout).
var tap_target: WaterTap3D = null
var stir_target: Vessel3D = null
var swirling: bool = false
var _assist_candidate: Vessel3D = null
var _assist_dwell_s: float = 0.0
## A vessel the player clicked to stop pouring/stirring: ignored until the
## cursor moves off it.
var _assist_suppressed: Vessel3D = null
var _assist_note: String = ""
var _pour_side: float = 1.0
## Wheel while pouring: faster or slower (1 = normal).
var _pour_speed: float = 1.0
var _assist_rolled: bool = false
var _wobble_roll_rad: float = 0.0
## Pointer gestures, measured from raw motion: how fast it moves (px/s) and
## how fast it turns (rad/s, + = clockwise on screen).
var _motion_px: float = 0.0
var _turn_rad: float = 0.0
var _last_rel: Vector2 = Vector2.ZERO
var wiggle_px_s: float = 0.0
var turn_rad_s: float = 0.0
var _stir_phase: float = 0.0
var _stir_speed_rad_s: float = 0.0
var _stir_dir: float = 1.0
var _swirl_phase: float = 0.0
var _swirl_offset_x: float = 0.0
var _path_cast: ShapeCast3D = null
var _path_box: BoxShape3D = null
## Assists arm only once the item has been carried a little way, so picking
## a vial out of a row doesn't pour it straight into its neighbour.
var _hold_start_x: float = 0.0
var _assist_armed: bool = false
var _hold_time_s: float = 0.0
## Seat the held vessel would glide into if let go now ({} = none).
var dock_seat: Dictionary = {}
## Placing: the hands finish putting the item down (into a seat, or upright
## onto the surface) before letting go.
var placing: bool = false
var _place_seat: Dictionary = {}
var _place_time_s: float = 0.0
var _place_drop_m: float = 0.0
var _place_x: float = 0.0
var _place_z: float = 0.0
var _hovered: RigidBody3D = null
var _hover_tick: int = 0
const HOVER_SHADER: Shader = preload("res://visuals_3d/shaders/hover_rim.gdshader")
static var _hover_mat: ShaderMaterial = null
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

	_probe = RayCast3D.new()
	_probe.enabled = false
	_probe.top_level = true
	_probe.collision_mask = SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_RIGID_VESSEL | SimConstants.LAYER_SOLID_REAGENT
	_probe.hit_back_faces = false
	add_child(_probe)


# --- Input routing ----------------------------------------------------------------

## While something is in the hand, follow the mouse even over the HUD or
## the satchel (those panels eat the motion before _unhandled_input), so an
## item taken out of the satchel stays under the cursor.
func _input(event: InputEvent) -> void:
	if held_body != null and event is InputEventMouseMotion and not input_captured:
		_pointer_screen = (event as InputEventMouseMotion).position


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
						# Second click: stop pouring/stirring, use the item (hammer
						# strike), or put it down.
						if pour_target == null and pour_candidate != null and held_body is Vessel3D:
							_start_pour(pour_candidate)
						elif pour_target != null or stir_target != null:
							_assist_suppressed = pour_target if pour_target != null else stir_target
							_end_assist()
						elif not placing:
							var used: bool = held_body.has_method(&"click_use") and bool(held_body.call(&"click_use"))
							if not used:
								put_down()
						_swallow_release = true
				else:
					if _swallow_release:
						_swallow_release = false
					elif held_body != null and not placing and (mb.position.distance_to(_press_pos) > DRAG_PIXELS or Time.get_ticks_msec() - _press_ms > DRAG_MS):
						# It was a press-and-drag: put it down where it is.
						put_down()
					# A quick click keeps holding the item until the next click.
			MOUSE_BUTTON_RIGHT:
				pass  # right-drag pans the view (LabCamera3D), even while carrying
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed and held_body != null:
					if pour_target != null:
						_pour_speed = clampf(_pour_speed * 1.25, 0.25, 3.0)
					else:
						_add_roll(wheel_tilt_step_rad)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and held_body != null:
					if pour_target != null:
						_pour_speed = clampf(_pour_speed / 1.25, 0.25, 3.0)
					else:
						_add_roll(-wheel_tilt_step_rad)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_pointer_screen = mm.position
		_note_motion(mm.relative)
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
		_note_motion(sd.relative)
	elif sd.index == _touch_secondary_index:
		_apply_twist(_touch_secondary_pos - _touch_primary_pos, sd.position - _touch_primary_pos)
		_touch_secondary_pos = sd.position


func _apply_twist(before: Vector2, after: Vector2) -> void:
	if held_body == null or before.length_squared() < 1.0 or after.length_squared() < 1.0:
		return
	_add_roll(-before.angle_to(after))


## Raw pointer motion feeds the gesture meters (speed and turning).
func _note_motion(rel: Vector2) -> void:
	_motion_px += rel.length()
	if rel.length_squared() > 1.0 and _last_rel.length_squared() > 1.0:
		var turn: float = _last_rel.angle_to(rel)
		# Back-and-forth reversals are ~180 degrees with a random sign: skip them.
		if absf(turn) < 2.5:
			_turn_rad += turn
	if rel.length_squared() > 1.0:
		_last_rel = rel


func _update_gestures(dt: float) -> void:
	wiggle_px_s = lerpf(wiggle_px_s, _motion_px / dt, 1.0 - exp(-6.0 * dt))
	turn_rad_s = lerpf(turn_rad_s, _turn_rad / dt, 1.0 - exp(-4.0 * dt))
	_motion_px = 0.0
	_turn_rad = 0.0


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


## Let the hands finish putting the item down: into the seat it is over, or
## straightened and lowered onto whatever is under it. Items that aren't
## vessels or tools (rocks, the hammer, cranks) are simply let go.
func put_down() -> void:
	if held_body == null:
		return
	var vessel: Vessel3D = held_body as Vessel3D
	if vessel == null and not (held_body is StirTool3D):
		var body: RigidBody3D = held_body
		var intake: MachineIntake = MachineIntake.under(body, body.global_position.x)
		release()
		if intake != null:
			# Into the hopper (or the cabinet): the machine takes it from here.
			AudioDirector.impact(&"stone", 0.5, body.global_position, 0.9)
			intake.receive(body)
		return
	_end_assist()
	swirling = false
	placing = true
	_place_seat = dock_seat.duplicate()
	_place_time_s = 0.0
	_place_drop_m = 0.0
	if _place_seat.is_empty():
		var spot: Vector2 = _clear_drop_spot(held_body.global_position, _held_radius())
		_place_x = spot.x
		_place_z = spot.y


## Rough horizontal radius of the held item (for finding room to set it down).
func _held_radius() -> float:
	var vessel: Vessel3D = held_body as Vessel3D
	if vessel != null:
		return vessel.profile.outer_radius_meters if vessel.profile != null else vessel.inner_radius_meters + vessel.wall_thickness_meters
	return 0.012


## The nearest spot to `at` (x, z) where the item can stand on flat, solid
## ground (bench, machine top) rather than on another loose object. Tries its
## own row first, then the bench's other rows; stays put if nowhere is free.
func _clear_drop_spot(at: Vector3, radius: float) -> Vector2:
	var rows: Array[float] = [at.z, -0.1, 0.12, 0.3]
	for k: int in 41:
		var offset: float = 0.02 * float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)
		for z: float in rows:
			if _spot_is_clear(Vector3(at.x + offset, at.y, z), radius):
				return Vector2(at.x + offset, z)
	return Vector2(at.x, at.z)


func _spot_is_clear(at: Vector3, radius: float) -> bool:
	var lo_y: float = INF
	var hi_y: float = -INF
	for side: Vector2 in [Vector2(-1.3, 0.0), Vector2(-0.65, 0.0), Vector2.ZERO, Vector2(0.65, 0.0), Vector2(1.3, 0.0), Vector2(0.0, -1.1), Vector2(0.0, 1.1)]:
		_probe.global_transform = Transform3D(Basis.IDENTITY, Vector3(at.x + side.x * radius, at.y + 0.002, at.z + side.y * radius))
		_probe.target_position = Vector3(0.0, -0.6, 0.0)
		_probe.force_raycast_update()
		if not _probe.is_colliding() or _probe.get_collider() is RigidBody3D:
			return false
		var hy: float = _probe.get_collision_point().y
		lo_y = minf(lo_y, hy)
		hi_y = maxf(hi_y, hy)
	# Flat ground only (not the edge of a ring, rack or machine).
	return hi_y - lo_y <= 0.006


func release() -> void:
	if held_body != null and is_instance_valid(held_body):
		# Let go gently: cap the speed so the item settles where you dropped it.
		held_body.linear_velocity = held_body.linear_velocity.limit_length(release_speed_m_s)
		held_body.angular_velocity = held_body.angular_velocity.limit_length(4.0)
	_end_assist()
	swirling = false
	placing = false
	dock_seat = {}
	_wobble_roll_rad = 0.0
	held_body = null
	_mouse_tilting = false
	pour_roll_rad = 0.0
	_assist_rolled = false


# --- Physics ---------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if camera == null:
		return
	_update_gestures(1.0 / float(Engine.physics_ticks_per_second))
	current_held = held_body
	if _pick_requested:
		_pick_requested = false
		_do_pick()
	if held_body != _tracked_body and _tracked_body != null:
		# Let go (by click, code or a test): back into the 2D lane.
		Flat2D.relock_depth(_tracked_body)
		_tracked_body = null
		_end_assist()
		swirling = false
		_wobble_roll_rad = 0.0
	if held_body == null:
		_assist_note = ""
		placing = false
		dock_seat = {}
		pour_candidate = null
		intake_target = null
		_mark_target(null)
		SupportStand3D.update_hints(null, {}, 1.0 / float(Engine.physics_ticks_per_second))
		MachineIntake.update_markers(null, null)
		_update_hover()
		return
	_set_hovered(null)
	if not is_instance_valid(held_body) or held_body.freeze:
		held_body = null
		return
	if held_body != _tracked_body:
		# Newly held (by pick, grab() or code): the hand starts where it is.
		_tracked_body = held_body
		Flat2D.free_depth(held_body)
		_hold_start_x = held_body.global_position.x
		_assist_armed = held_body is StirTool3D  # stirring by accident is harmless
		_hold_time_s = 0.0
		placing = false
		_target_world = held_body.global_position
		_pointer_target_world = _target_world
		_on_new_hold()
	if placing:
		_update_placing()
	else:
		_update_target()
	if held_body == null:
		return
	_update_machine_hints()
	_mark_target(pour_target if pour_target != null else pour_candidate)
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


## True when the camera is orthographic: the game plays as a 2.5D side view.
func is_side_view() -> bool:
	return camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL


func _on_new_hold() -> void:
	AudioDirector.play(&"grab", held_body.global_position, -14.0)
	_probe.clear_exceptions()
	_probe.add_exception(held_body)
	# Measure how far the item's underside sits below its centre.
	var p: Vector3 = held_body.global_position
	var hit_y: float = _cast_down(p + Vector3(0.0, 0.002, 0.0), p.y - 0.4)
	_half_height = clampf(p.y - hit_y, 0.008, 0.2) if not is_nan(hit_y) else 0.03
	_surface_z = p.z
	_probe_tick = 0


## Downward ray (excluding the held item); returns the hit height or NAN.
func _cast_down(from: Vector3, to_y: float) -> float:
	_probe.global_transform = Transform3D(Basis.IDENTITY, from)
	_probe.target_position = Vector3(0.0, to_y - from.y, 0.0)
	_probe.force_raycast_update()
	return _probe.get_collision_point().y if _probe.is_colliding() else NAN


## Point on the vertical work plane z = `plane_z` under the screen position.
func cursor_on_plane(screen: Vector2, plane_z: float) -> Vector3:
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	if absf(dir.z) < 1e-4:
		return origin
	return origin + dir * ((plane_z - origin.z) / dir.z)


## The surface under the cursor in the 2D view: probes every depth and keeps
## the highest surface below the cursor (a machine, rim or rock beats the
## plain bench); ties keep the current depth. Returns Vector2(y, z).
func surface_under(x: float, from_y: float, current_z: float) -> Vector2:
	var best_y: float = -INF
	var best_z: float = current_z
	var current_y: float = -INF
	var z: float = probe_front_z
	while z >= probe_back_z - 1e-4:
		var y: float = _cast_down(Vector3(x, from_y, z), from_y - 0.6)
		if not is_nan(y):
			if y > best_y + 0.01:
				best_y = y
				best_z = z
			if absf(z - current_z) < probe_step_z * 0.5:
				current_y = y
		z -= probe_step_z
	if current_y >= best_y - 0.01:
		best_z = current_z
		best_y = maxf(current_y, best_y)
	return Vector2(best_y if best_y > -INF else floor_y_meters - 0.01, best_z)


## Where a satchel item dropped at `screen` would land (side view).
func side_drop_point(screen: Vector2) -> Dictionary:
	var p: Vector3 = cursor_on_plane(screen, 0.15)
	_probe.clear_exceptions()
	if held_body != null:
		_probe.add_exception(held_body)
	var s: Vector2 = surface_under(p.x, p.y, 0.15)
	var flat_x: float = p.x - global_position.x
	if absf(flat_x) > reach_radius_meters:
		return {"valid": false, "position": Vector3(p.x, s.x, s.y), "reason": "Out of reach: drop it closer, or switch station"}
	if p.y < s.x - 0.01:
		return {"valid": false, "position": Vector3(p.x, s.x, s.y), "reason": "Drop it above the bench"}
	return {"valid": true, "position": Vector3(p.x, s.x, s.y), "reason": ""}


func _update_target_side() -> void:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var cur: Vector3 = cursor_on_plane(_pointer_screen, _target_world.z)
	var override_y: float = NAN
	if held_body.has_method(&"get_hover_override_y"):
		override_y = held_body.call(&"get_hover_override_y") as float
	# Probe the depth column every other tick (16 short rays, allocation-free).
	_probe_tick += 1
	if _probe_tick % 2 == 1:
		var s: Vector2 = surface_under(cur.x, maxf(cur.y, floor_y_meters) + 0.01, _surface_z)
		_surface_y = s.x
		_surface_z = s.y
	var want_y: float = maxf(maxf(cur.y, _surface_y + _half_height + 0.006), floor_y_meters)
	if not is_nan(override_y):
		want_y = override_y
	var center: Vector3 = global_position
	var want_x: float = center.x + clampf(cur.x - center.x, -reach_radius_meters, reach_radius_meters)
	_swirl_offset_x = 0.0
	var assisted: Variant = _update_assists(cur, dt)
	if assisted != null:
		var a: Vector3 = assisted as Vector3
		want_x = a.x
		want_y = a.y
		_surface_z = a.z
		override_y = NAN
	want_x += _swirl_offset_x
	# Carry over things, not through them: lift above the tallest thing
	# between here and there before moving across.
	var hold_x: bool = false
	if is_nan(override_y) and absf(want_x - _target_world.x) > 0.012 and not (held_body is StirTool3D and stir_target != null):
		var top: float = _obstacle_top_between(_target_world.x, want_x)
		if top > -INF:
			var clear_y: float = top + _half_height + 0.018
			want_y = maxf(want_y, clear_y)
			hold_x = _target_world.y < clear_y - 0.012 and held_body.global_position.y < clear_y - 0.012
	_pointer_target_world = Vector3(want_x, want_y, _surface_z)
	var speed: float = precise_speed_m_s if Input.is_key_pressed(KEY_SHIFT) else carry_speed_m_s
	var cur_xy: Vector2 = Vector2(_target_world.x, _target_world.y)
	var want_xy: Vector2 = Vector2(_target_world.x if hold_x else want_x, want_y)
	cur_xy = cur_xy.move_toward(want_xy, speed * dt)
	if not is_nan(override_y):
		cur_xy.y = override_y  # hammer slams stay instant
	# Change depth only once the item has risen to the carry height, so it
	# lifts straight out of a rack or ring instead of jamming against it.
	var z: float = _target_world.z
	if held_body.global_position.y > cur_xy.y - 0.02 or not is_nan(override_y):
		z = move_toward(_target_world.z, _surface_z, lift_speed_m_s * dt)
	_target_world = Vector3(cur_xy.x, cur_xy.y, z)


## Highest top of anything (other than the held item) along the straight
## line from `a` to `b` (both x and depth); -INF if the way is clear.
func _obstacle_top_along(a: Vector3, b: Vector3) -> float:
	if _path_cast == null:
		_obstacle_top_between(a.x, a.x + 0.01)  # builds the shared cast
	var flat: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length: float = flat.length()
	var radius: float = _held_radius()
	if length < radius + 0.004:
		return -INF
	var dir: Vector3 = flat / length
	# Start past the item's own footprint so it doesn't see itself.
	var start: Vector3 = a + dir * radius
	length -= radius
	_path_box.size = Vector3(radius * 2.0, 0.004, length)
	var top_y: float = maxf(_target_world.y, held_body.global_position.y) + 0.35
	var mid: Vector3 = start + dir * (length * 0.5)
	_path_cast.clear_exceptions()
	_path_cast.add_exception(held_body)
	_path_cast.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(mid.x, top_y, mid.z))
	_path_cast.target_position = _path_cast.global_transform.basis.inverse() * Vector3(0.0, floor_y_meters - 0.03 - top_y, 0.0)
	_path_cast.force_shapecast_update()
	var best: float = -INF
	for i: int in _path_cast.get_collision_count():
		var hit: Object = _path_cast.get_collider(i)
		if hit is MachineHandle3D or hit is StaticBody3D and (hit as StaticBody3D).collision_layer & SimConstants.LAYER_STATIC_BENCH != 0 and _path_cast.get_collision_point(i).y < floor_y_meters + 0.02:
			continue
		best = maxf(best, _path_cast.get_collision_point(i).y)
	return best


## Highest top of anything (other than the held item) in the strip between
## two x positions, across all depths; -INF if nothing is there.
func _obstacle_top_between(x0: float, x1: float) -> float:
	if _path_cast == null:
		_path_box = BoxShape3D.new()
		_path_cast = ShapeCast3D.new()
		_path_cast.enabled = false
		_path_cast.top_level = true
		_path_cast.shape = _path_box
		_path_cast.max_results = 12
		_path_cast.collision_mask = SimConstants.LAYER_RIGID_VESSEL | SimConstants.LAYER_SOLID_REAGENT | SimConstants.LAYER_STATIC_BENCH
		add_child(_path_cast)
	var radius: float = _held_radius()
	var lo: float = minf(x0, x1)
	var hi: float = maxf(x0, x1)
	# Skip the item's own footprint at the start so it doesn't see itself.
	if x1 > x0:
		lo += radius
	else:
		hi -= radius
	if hi - lo < 0.004:
		return -INF
	_path_box.size = Vector3(hi - lo + radius * 2.0, 0.004, probe_front_z - probe_back_z)
	var top_y: float = maxf(_target_world.y, held_body.global_position.y) + 0.35
	_path_cast.clear_exceptions()
	_path_cast.add_exception(held_body)
	_path_cast.global_transform = Transform3D(Basis.IDENTITY, Vector3((lo + hi) * 0.5, top_y, (probe_front_z + probe_back_z) * 0.5))
	_path_cast.target_position = Vector3(0.0, floor_y_meters - 0.03 - top_y, 0.0)
	_path_cast.force_shapecast_update()
	var best: float = -INF
	for i: int in _path_cast.get_collision_count():
		if _path_cast.get_collider(i) is MachineHandle3D:
			continue
		best = maxf(best, _path_cast.get_collision_point(i).y)
	return best


# --- Assists: pour, stir, swirl ---------------------------------------------------

## Decide what the held item is doing this tick and, when an assist is
## steering it, return where its centre should go (else null).
func _update_assists(cursor: Vector3, dt: float) -> Variant:
	var vessel: Vessel3D = held_body as Vessel3D
	var tool: StirTool3D = held_body as StirTool3D
	var result: Variant = null
	var key_stir: bool = Input.is_key_pressed(KEY_S)
	_hold_time_s += dt
	if not _assist_armed and (absf(cursor.x - _hold_start_x) > ARM_TRAVEL_METERS or _hold_time_s > ARM_HOLD_SECONDS):
		_assist_armed = true
	# A free seat right under the cursor wins over pouring into a neighbour.
	dock_seat = {}
	if vessel != null and pour_target == null and _assist_armed:
		dock_seat = SupportStand3D.best_seat(vessel, cursor.x, SEAT_CATCH_METERS)
	SupportStand3D.update_hints(vessel, dock_seat, dt)
	if _assist_suppressed != null and (not is_instance_valid(_assist_suppressed) or absf(_rim(_assist_suppressed).x - cursor.x) > _assist_suppressed.get_lip_radius_meters() + POUR_EXIT_METERS):
		_assist_suppressed = null
	# Circling the pointer means "swirl", so it never starts a new pour.
	var circling: bool = absf(turn_rad_s) > SWIRL_TURN_THRESHOLD_RAD_S and wiggle_px_s > 60.0
	# Tap: an open vessel held near a tap's spout is brought under it to fill.
	tap_target = null
	if vessel != null and vessel.open_top and not vessel.sealed and _assist_armed:
		for tap: WaterTap3D in WaterTap3D.all_taps:
			var spout: Vector3 = tap.spout_world()
			if absf(spout.x - cursor.x) < 0.07 and cursor.y > tap.global_position.y + 0.06:
				tap_target = tap
				_end_pour()
				var center_y: float = maxf(spout.y - 0.035 - vessel.get_lip_local_y(), tap.global_position.y + 0.015 + _half_height + 0.006)
				result = Vector3(spout.x, center_y, spout.z)
				break
	# Pour: a vessel with liquid or powder, held over another open vessel.
	if tap_target == null and vessel != null and vessel.can_pour_contents():
		var target: Vessel3D = _pick_assist_target(cursor.x, pour_target if pour_target != null else pour_candidate, false) if _assist_armed and dock_seat.is_empty() else null
		if target != null and target == pour_target:
			result = _pour_into(vessel, target, dt)
		elif target != null and not circling and pour_target == null:
			pour_candidate = target
		else:
			_end_pour()
			pour_candidate = null
	else:
		if pour_target != null:
			_end_pour()
		pour_candidate = null
	# Stir: a stirring tool held over a vessel with liquid in it.
	if tool != null:
		var stir: Vessel3D = _pick_assist_target(cursor.x, stir_target, true) if _assist_armed else null
		if stir != null and (stir == stir_target or _dwell(stir, dt)):
			stir_target = stir
			result = _stir_in(tool, stir, dt, key_stir)
		else:
			stir_target = null
	else:
		stir_target = null
	if pour_target == null and stir_target == null and _assist_candidate == null:
		_assist_dwell_s = 0.0
	# Swirl by hand: circle the pointer (or hold S) with a vessel held.
	swirling = false
	if vessel != null and pour_target == null and vessel.mixture != null and not vessel.granular and vessel.mixture.get_liquid_volume_m3() > 1e-6:
		if circling or key_stir:
			swirling = true
			result = _swirl(vessel, cursor, result, dt, circling)
	if not swirling:
		_wobble_roll_rad = move_toward(_wobble_roll_rad, 0.0, 2.0 * dt)
	# Ease the tilt back upright once a pour has ended.
	if pour_target == null and _assist_rolled:
		pour_roll_rad = move_toward(pour_roll_rad, 0.0, 1.8 * dt)
		if absf(pour_roll_rad) < 1e-3:
			pour_roll_rad = 0.0
			_assist_rolled = false
	_assist_note = _describe_assist(vessel, tool)
	return result


## The vessel under the cursor (left/right only: depth doesn't matter in the
## side view) that the held item could pour into or stir. Keeps `current`
## with a wider margin so small hand movements don't break off.
func _pick_assist_target(cursor_x: float, current: Vessel3D, for_stir: bool) -> Vessel3D:
	var best: Vessel3D = null
	var best_d: float = INF
	for v: Vessel3D in Vessel3D.all_vessels:
		if v == held_body or v.mixture == null or not v.is_inside_tree() or v.freeze and v.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC:
			continue
		if not v.open_top or v.sealed or v.global_basis.y.y < 0.8 or v == _assist_suppressed:
			continue
		if for_stir and v.mixture.get_liquid_volume_m3() <= 1e-6 and not (v is MortarBowl3D and held_body is Pestle3D):
			continue
		if for_stir and v is MortarBowl3D and not held_body is Pestle3D and v.mixture.get_liquid_volume_m3() <= 1e-6:
			continue
		var reach: float = (v.get_surface_radius_meters() if for_stir else v.get_lip_radius_meters())
		reach += POUR_EXIT_METERS if v == current else POUR_ENTER_METERS
		var d: float = absf(_rim(v).x - cursor_x)
		if d < reach and d < best_d:
			best = v
			best_d = d
	return best


## True once the cursor has rested over `target` for a moment.
func _dwell(target: Vessel3D, dt: float) -> bool:
	if target != _assist_candidate:
		_assist_candidate = target
		_assist_dwell_s = 0.0
	_assist_dwell_s += dt
	return _assist_dwell_s >= ASSIST_DWELL_S


func _rim(v: Vessel3D) -> Vector3:
	return v.global_transform * Vector3(0.0, v.get_lip_local_y(), 0.0)


## Tip the held vessel toward the target and keep its pouring lip over the
## target's mouth. Returns where the held vessel's centre should be.
func _pour_into(vessel: Vessel3D, target: Vessel3D, dt: float) -> Variant:
	if target.get_fill_fraction() >= POUR_FULL_FRACTION:
		_assist_suppressed = target
		_end_pour()
		_assist_note = "That one is full"
		return null
	_assist_rolled = true
	var mouth: Vector3 = _rim(target)
	# Only tip once the lip is really over the mouth (the hand glides there
	# first), so nothing spills on the way.
	var lip: Vector3 = vessel.get_pour_lip_world()
	var over: bool = absf(lip.x - mouth.x) < target.get_lip_radius_meters() * 0.8 and absf(lip.z - mouth.z) < target.get_lip_radius_meters() * 0.8
	if over:
		# Ease over, tip until it starts to pour, then hold a steady flow:
		# tip on gently as it empties, ease back if it gushes.
		var magnitude: float = absf(pour_roll_rad)
		var rate: float = 0.22 if vessel.is_pouring else lerpf(0.45, 1.0, smoothstep(0.0, 0.6, magnitude))
		if vessel.is_pouring and vessel.pour_rate_m3_s > POUR_TARGET_RATE_M3_S * _pour_speed:
			rate = -0.25
		pour_roll_rad = _pour_side * clampf(magnitude + rate * dt, 0.0, POUR_MAX_ROLL_RAD)
	elif not vessel.is_pouring:
		pour_roll_rad = _pour_side * minf(absf(pour_roll_rad), 0.45)
	var outer_r: float = vessel.profile.outer_radius_meters if vessel.profile != null else vessel.inner_radius_meters + vessel.wall_thickness_meters
	var clearance: float = 0.022 + outer_r * 0.6
	# Aim where the stream lands (a little ahead of the lip) at the mouth.
	var lip_offset: Vector3 = vessel.get_pour_lip_world() - vessel.global_position + vessel.stream_offset_world
	var want: Vector3 = Vector3(mouth.x, mouth.y + clearance, mouth.z) - lip_offset
	# Keep the whole glass above the other rim at its current tilt, so it
	# never rests on it (and can't tip if it does).
	var tilt: float = acos(clampf(vessel.global_basis.y.normalized().y, -1.0, 1.0))
	var lowest_below_center: float = _half_height * absf(cos(tilt)) + outer_r * absf(sin(tilt))
	want.y = maxf(want.y, mouth.y + lowest_below_center + 0.012)
	return want


func _end_pour() -> void:
	if pour_target != null or (_assist_candidate != null and held_body is Vessel3D):
		_assist_candidate = null
	pour_target = null


func _end_assist() -> void:
	pour_target = null
	pour_candidate = null
	stir_target = null
	_assist_candidate = null
	_assist_dwell_s = 0.0


## Dip the tool into the liquid and run its tip round in a small circle; the
## stirring speed follows how much the pointer moves (or S is held).
func _stir_in(tool: StirTool3D, vessel: Vessel3D, dt: float, key_stir: bool) -> Variant:
	if absf(turn_rad_s) > 2.0:
		_stir_dir = signf(turn_rad_s)
	var want: float = clampf(wiggle_px_s * STIR_RAD_PER_PX, 0.0, MAX_STIR_RAD_S)
	if key_stir:
		want = maxf(want, KEY_STIR_RAD_S)
	_stir_speed_rad_s = lerpf(_stir_speed_rad_s, want, 1.0 - exp(-5.0 * dt))
	_stir_phase = wrapf(_stir_phase + _stir_dir * _stir_speed_rad_s * dt, 0.0, TAU)
	var bottom_y: float = vessel.get_cavity_bottom_local_y()
	var fill_y: float = vessel.get_fill_local_y()
	var tip_y: float = lerpf(bottom_y + 0.004, fill_y, 0.35)
	var r: float = vessel.get_surface_radius_meters() * 0.45 * clampf(_stir_speed_rad_s / 3.0, 0.25, 1.0)
	if vessel is MortarBowl3D:
		# Grind round the floor of the bowl, over the rock or the powder.
		tip_y = bottom_y + 0.009
		r = MortarBowl3D.CAVITY_RADIUS_METERS * 0.42 * clampf(_stir_speed_rad_s / 3.0, 0.35, 1.0)
	var axis_point: Vector3 = vessel.global_transform * Vector3(0.0, tip_y, 0.0)
	var tip_target: Vector3 = axis_point + Vector3(cos(_stir_phase), 0.0, sin(_stir_phase)) * r
	return tip_target - tool.global_basis * tool.get_tip_local()


## Swish the held glass round in small circles, spinning its contents.
func _swirl(vessel: Vessel3D, cursor: Vector3, steer: Variant, dt: float, circling: bool) -> Variant:
	var dir: float = signf(turn_rad_s) if circling else 1.0
	var omega: float = clampf(absf(turn_rad_s) * 1.4, 5.0, 16.0) if circling else KEY_STIR_RAD_S
	var m: MixtureContainer = vessel.mixture
	var viscosity_pas: float = m.get_liquid_viscosity_pas()
	var blend: float = 1.0 - exp(-dt * 3.0 / (1.0 + viscosity_pas * 2.0))
	m.swirl_rad_s = clampf(lerpf(m.swirl_rad_s, -dir * omega, blend), -40.0, 40.0)
	vessel.add_agitation(omega * 0.004)
	_swirl_phase = wrapf(_swirl_phase + dir * omega * 0.6 * dt, 0.0, TAU)
	# The hands move the glass in a little circle: side to side in this view,
	# with a gentle rocking tilt.
	_wobble_roll_rad = sin(_swirl_phase) * 0.12
	AudioDirector.loop(&"swirl", &"swirl_loop", vessel.global_position, clampf(omega / 12.0, 0.3, 1.0), clampf(1.0 - viscosity_pas * 0.15, 0.6, 1.0), -10.0)
	# Circling the mouse already carries the glass round in circles; with S
	# held the hands add a small circle of their own.
	_swirl_offset_x = 0.0 if circling else cos(_swirl_phase) * 0.008
	return steer


func _describe_assist(vessel: Vessel3D, tool: StirTool3D) -> String:
	if placing:
		return "Putting it down"
	if tap_target != null:
		return "Full  ·  move away" if tap_target.filling == null else "Filling with water  ·  move away to stop"
	if pour_target != null:
		return "Pouring into the %s  ·  wheel: faster/slower  ·  click or move away to stop" % _vessel_label(pour_target)
	if pour_candidate != null:
		var held_vessel: Vessel3D = held_body as Vessel3D
		var what: String = "tip the powder" if held_vessel != null and held_vessel.granular else "pour"
		return "Click to %s into the %s (%.0f mL in it)" % [what, _vessel_label(pour_candidate), (pour_candidate.mixture.get_liquid_volume_m3() + pour_candidate.mixture.get_solid_volume_m3()) * 1e6 if pour_candidate.mixture != null else 0.0]
	if not dock_seat.is_empty():
		return "Click to set it %s" % (dock_seat["stand"] as SupportStand3D).seat_phrase()
	if stir_target != null and stir_target is MortarBowl3D and tool is Pestle3D:
		var stage: String = (stir_target as MortarBowl3D).grind_stage()
		return "Grinding%s  ·  circle the mouse or hold S" % ((" · " + stage) if stage != "" else "")
	if stir_target != null:
		return "Stirring  ·  wiggle or circle the mouse, or hold S"
	if swirling:
		return "Swirling"
	if _assist_note == "That one is full" and _assist_suppressed != null:
		return _assist_note
	if vessel != null and vessel.granular and vessel.can_pour_contents():
		return "Hold it over another vessel, then click to tip the powder in"
	if vessel != null and vessel.mixture != null and vessel.mixture.get_liquid_volume_m3() > 1e-6:
		return "Hold it over another vessel, then click to pour  ·  circle the mouse or hold S to swirl"
	if tool is Pestle3D:
		return "Hold it over the mortar to grind"
	if tool != null:
		return "Hold it over a vessel to stir"
	return ""


static func _vessel_label(v: Vessel3D) -> String:
	if v.profile != null and v.profile.vessel_name != "":
		return v.profile.vessel_name.replace("_", " ")
	return "vessel"


## The hands finish a put-down: glide over the seat (clearing its rim), lower
## into it, or simply come upright over the surface; then let go gently.
func _update_placing() -> void:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	_place_time_s += dt
	_assist_note = "Putting it down"
	pour_roll_rad = move_toward(pour_roll_rad, 0.0, 2.2 * dt)
	_wobble_roll_rad = move_toward(_wobble_roll_rad, 0.0, 4.0 * dt)
	var body: RigidBody3D = held_body
	var p: Vector3 = body.global_position
	var upright: float = body.global_basis.y.normalized().dot(Vector3.UP)
	var want: Vector3 = _target_world
	var done: bool = false
	if not _place_seat.is_empty():
		var stand: SupportStand3D = _place_seat["stand"] as SupportStand3D
		var floor_p: Vector3 = stand.seat_floor_world(int(_place_seat["index"]))
		var rest_y: float = floor_p.y + _half_height + 0.006
		var safe_y: float = maxf(rest_y, stand.clear_top_y() + _half_height + 0.012)
		var horizontal: float = Vector2(p.x - floor_p.x, p.z - floor_p.z).length()
		if horizontal > 0.004:
			# Clear anything standing on the way to the seat (other rows too),
			# and don't move across until the glass is up there.
			var top: float = _obstacle_top_along(p, floor_p)
			if top > -INF:
				safe_y = maxf(safe_y, top + _half_height + 0.015)
				if p.y < safe_y - 0.01:
					floor_p = Vector3(p.x, floor_p.y, p.z)
		# Over the seat at a safe height first, then straight down into it.
		want = Vector3(floor_p.x, safe_y if horizontal > 0.004 else rest_y, floor_p.z)
		if horizontal > 0.004 and want.y < _target_world.y:
			want.y = _target_world.y
		done = horizontal < 0.004 and absf(p.y - rest_y) < 0.006 and upright > 0.995
	else:
		# Slide over a clear spot, come upright, then lower onto the surface.
		var over: bool = absf(p.x - _place_x) < 0.006 and absf(p.z - _place_z) < 0.01
		var surface: float = _cast_down(Vector3(_place_x, p.y + 0.002, _place_z), p.y - 0.5)
		var rest: float = (surface + _half_height + 0.004) if not is_nan(surface) else p.y
		want = Vector3(_place_x, rest if upright > 0.97 and over else _target_world.y, _place_z)
		done = over and upright > 0.995 and absf(p.y - rest) < 0.008
	var step: float = 0.35 * dt
	_target_world = _target_world.move_toward(want, step)
	# Settled: the hand has reached the spot and the glass has stopped moving
	# (it may be resting a touch high on something), so let go.
	var settled: bool = _target_world.distance_to(want) < 0.002 and body.global_position.distance_to(_target_world) < 0.012 and body.linear_velocity.length() < 0.02 and upright > 0.98 and _place_time_s > 0.25
	if (done and body.linear_velocity.length() < 0.15) or settled or _place_time_s > PLACE_TIMEOUT_S:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		if not _place_seat.is_empty():
			AudioDirector.impact(&"glass", 0.6, p, 1.1)
		release()


## Hover feedback when empty-handed: the pickable item under the pointer gets
## a soft rim glow and the cursor turns into a hand.
func _update_hover() -> void:
	_hover_tick += 1
	if _hover_tick % 3 != 0:
		return
	var body: RigidBody3D = null
	if not input_captured and camera != null:
		var origin: Vector3 = camera.project_ray_origin(_pointer_screen)
		_pick_ray.global_transform = Transform3D(Basis.IDENTITY, origin)
		_pick_ray.target_position = camera.project_ray_normal(_pointer_screen) * PICK_DISTANCE_METERS
		_pick_ray.force_raycast_update()
		body = _pick_ray.get_collider() as RigidBody3D
		if body == null:
			_pick_sphere.radius = _pixels_to_meters(mouse_pick_radius_px)
			_pick_cast.global_transform = Transform3D(Basis.IDENTITY, origin)
			_pick_cast.target_position = _pick_ray.target_position
			_pick_cast.force_shapecast_update()
			if _pick_cast.is_colliding():
				body = _pick_cast.get_collider(0) as RigidBody3D
		if body != null and body.freeze:
			body = null
	_set_hovered(body)


func _set_hovered(body: RigidBody3D) -> void:
	if body == _hovered:
		return
	if _hovered != null and is_instance_valid(_hovered):
		for n: Node in _hovered.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).material_overlay = null
	_hovered = body
	if _hover_mat == null:
		_hover_mat = ShaderMaterial.new()
		_hover_mat.shader = HOVER_SHADER
	if body != null:
		for n: Node in body.find_children("*", "MeshInstance3D", true, false):
			(n as GeometryInstance3D).material_overlay = _hover_mat
	if DisplayServer.get_name() != "headless":
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if body != null else Input.CURSOR_ARROW)


## One-line hint for the HUD about what the hands are doing.
func assist_hint() -> String:
	return _assist_note if held_body != null else ""


func _update_target() -> void:
	if is_side_view() and not (held_body is MachineHandle3D):
		_update_target_side()
		return
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
	var desired: Basis = Basis(cam_forward, pour_roll_rad + _wobble_roll_rad) * Basis(Vector3.UP, _hold_yaw_rad)
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



## Start pouring into `target` (the player confirmed with a click).
func _start_pour(target: Vessel3D) -> void:
	var vessel: Vessel3D = held_body as Vessel3D
	if vessel == null or target == null:
		return
	pour_target = target
	pour_candidate = null
	_assist_suppressed = null
	_pour_speed = 1.0
	_pour_side = 1.0 if _rim(target).x >= vessel.global_position.x else -1.0
	AudioDirector.play_ui(&"click", -14.0, 1.2)


## Hints and drop markers for things that aren't glassware: rocks over a
## machine hopper, machine handles, the hammer.
func _update_machine_hints() -> void:
	intake_target = null
	if held_body is Rock3D:
		intake_target = MachineIntake.under(held_body, held_body.global_position.x)
		var rock: Rock3D = held_body as Rock3D
		if intake_target != null:
			_assist_note = intake_target.drop_note if intake_target.drop_note != "" else ("Click to put it away in the %s" if intake_target.on_catch.is_valid() else "Click to drop it into the %s") % intake_target.machine_name
		elif InventoryStore.is_find(rock):
			_assist_note = "Put it away over the storage cabinet's tray (or press E), or set it on the trader's scale to sell it"
		elif rock.mineral != null and rock.mineral.kind == MineralData.Kind.SAND:
			_assist_note = "Carry it over the sand sifter (the glow) and click to drop it in"
		else:
			_assist_note = "Carry it over the rock crusher (the glow) and click  ·  or crack it on the anvil with the hammer"
	elif held_body is MachineHandle3D:
		_assist_note = (held_body as MachineHandle3D).hint
	elif held_body is Hammer3D:
		_assist_note = "Hold it over a rock and click (or hold Space for a big swing)"
	if intake_target == null and pour_target == null and dock_seat.is_empty():
		var refusing: MachineIntake = MachineIntake.refusing(held_body, held_body.global_position.x)
		if refusing != null and held_body.global_position.y > refusing.global_position.y - 0.25:
			_assist_note = "The %s only takes %s" % [refusing.machine_name, refusing.wants]
	MachineIntake.update_markers(held_body, intake_target)


## Glow on the vessel a pour would go into (or is going into).
func _mark_target(v: Node3D) -> void:
	if v == _marked:
		return
	if _marked != null and is_instance_valid(_marked):
		for n: Node in _marked.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).material_overlay = null
	_marked = v
	if v == null:
		return
	if _target_mat == null:
		_target_mat = ShaderMaterial.new()
		_target_mat.shader = HOVER_SHADER
		_target_mat.set_shader_parameter(&"rim_color", Color(0.45, 0.9, 1.0))
		_target_mat.set_shader_parameter(&"strength", 0.9)
	for n: Node in v.find_children("*", "MeshInstance3D", true, false):
		(n as GeometryInstance3D).material_overlay = _target_mat
