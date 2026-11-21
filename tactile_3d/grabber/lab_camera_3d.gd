class_name LabCamera3D
extends Camera3D
## Table-level camera with smooth zoom and panning.
## PC: scroll wheel zooms when nothing is held (while holding, the wheel tilts/pours);
## right-drag with empty hands slides the view around (pressing the station's
## number key again centres it).
## Android: two-finger pinch zooms when nothing is held.
## Zoom dollies along the view direction, so perspective stays natural.

@export var grabber: TactileGrabber3D
@export var min_zoom_meters: float = -0.35
@export var max_zoom_meters: float = 0.6
@export var wheel_step_meters: float = 0.06
@export var zoom_smoothing_per_s: float = 10.0
@export var pinch_meters_per_px: float = 0.0015

## Work stations the camera glides between (offsets from the base view).
@export var station_names: PackedStringArray = ["Potion Bench", "Mineral Lab", "Science Bench"]
@export var station_offsets: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(3.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0)])
@export var inventory_store: Node3D

static var instance: LabCamera3D = null

var station: int = 0
var _station_offset: Vector3 = Vector3.ZERO
var _store_base: Vector3 = Vector3.ZERO
var _base_transform: Transform3D
var _zoom_target: float = 0.0
var _zoom_current: float = 0.0
var _touches: Dictionary = {}
var _last_pinch_px: float = -1.0
## Orthographic (2.5D side view) size at zoom 0, read from the scene.
var _base_ortho_size: float = 0.7
## Screen-shake "trauma" 0..1 (decays). Offset scales with trauma² so small
## taps barely nudge and big breaks really thump.
var _trauma: float = 0.0
## Right-drag pan, in metres along the view's right and up directions.
var _pan: Vector2 = Vector2.ZERO
var _pan_target: Vector2 = Vector2.ZERO
var _panning: bool = false
var _shake_time: float = 0.0

const SHAKE_MAX_METERS: float = 0.012
const SHAKE_MAX_ROLL_RAD: float = 0.012
const SHAKE_DECAY_PER_S: float = 2.2
## How far the view may slide from the station's centre (metres).
const PAN_LIMIT_METERS: Vector2 = Vector2(0.45, 0.25)
const PAN_SMOOTHING_PER_S: float = 18.0


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	_base_transform = transform
	_base_ortho_size = size
	if inventory_store != null:
		_store_base = inventory_store.global_position


## Glide to a work station; the grabber reach and satchel drop point follow.
func go_to_station(index: int) -> void:
	if index < 0 or index >= station_offsets.size():
		return
	_pan_target = Vector2.ZERO
	if index == station:
		return
	station = index
	AudioDirector.play_ui(&"whoosh", -12.0, 1.0)
	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "_station_offset", station_offsets[index], 0.9)
	if grabber != null:
		grabber.release()
		grabber.global_position = station_offsets[index]
	if inventory_store != null:
		inventory_store.global_position = _store_base + station_offsets[index]


func _unhandled_input(event: InputEvent) -> void:
	var holding: bool = grabber != null and grabber.held_body != null
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_9:
		go_to_station(key.keycode - KEY_1)
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		# Right-drag pans with empty hands (holding something, it tilts it).
		_panning = (event as InputEventMouseButton).pressed and not holding
		return
	if event is InputEventMouseMotion and _panning:
		if holding:
			_panning = false
			return
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		var meters_per_px: float = _view_height_meters() / maxf(get_viewport().get_visible_rect().size.y, 1.0)
		# The bench follows the mouse, like dragging a sheet of paper.
		_pan_target += Vector2(-rel.x, rel.y) * meters_per_px
		_pan_target = _pan_target.clamp(-PAN_LIMIT_METERS, PAN_LIMIT_METERS)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed or holding:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target + wheel_step_meters * mb.factor, min_zoom_meters, max_zoom_meters)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target - wheel_step_meters * mb.factor, min_zoom_meters, max_zoom_meters)
	elif event is InputEventMagnifyGesture and not holding:
		var mg: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		_zoom_target = clampf(_zoom_target + (mg.factor - 1.0) * 0.5, min_zoom_meters, max_zoom_meters)
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_last_pinch_px = -1.0
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if sd.device == InputEvent.DEVICE_ID_EMULATION or not _touches.has(sd.index):
			return
		_touches[sd.index] = sd.position
		if _touches.size() == 2 and not holding:
			var pts: Array = _touches.values()
			var dist: float = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			if _last_pinch_px > 0.0:
				_zoom_target = clampf(_zoom_target + (dist - _last_pinch_px) * pinch_meters_per_px, min_zoom_meters, max_zoom_meters)
			_last_pinch_px = dist


## Add impact shake (0..1). Ignored when the player asked for reduced motion.
func shake(amount: float) -> void:
	if CosmicTheme.reduced_motion:
		return
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Height of the visible bench at the focus distance, for converting pixels.
func _view_height_meters() -> float:
	if projection == PROJECTION_ORTHOGONAL:
		return size
	return 2.0 * tan(deg_to_rad(fov) * 0.5) * 1.5


func _process(delta: float) -> void:
	_zoom_current = lerpf(_zoom_current, _zoom_target, 1.0 - exp(-zoom_smoothing_per_s * delta))
	_pan = _pan.lerp(_pan_target, 1.0 - exp(-PAN_SMOOTHING_PER_S * delta))
	var forward: Vector3 = -_base_transform.basis.z
	var basis: Basis = _base_transform.basis
	var jitter: Vector3 = (basis.x * _pan.x + basis.y * _pan.y)
	if _trauma > 0.0:
		_shake_time += delta * 38.0
		var k: float = _trauma * _trauma
		jitter += (basis.x * sin(_shake_time * 1.13) + basis.y * sin(_shake_time * 0.91 + 1.7)) * SHAKE_MAX_METERS * k
		basis = basis.rotated(basis.z.normalized(), sin(_shake_time * 0.77 + 3.1) * SHAKE_MAX_ROLL_RAD * k)
		_trauma = maxf(_trauma - SHAKE_DECAY_PER_S * delta, 0.0)
	if projection == PROJECTION_ORTHOGONAL:
		# Side view: zoom by changing how much of the bench fits on screen.
		size = clampf(_base_ortho_size * exp(-_zoom_current * 1.4), 0.25, 1.4)
		transform = Transform3D(basis, _base_transform.origin + _station_offset + jitter)
	else:
		transform = Transform3D(basis, _base_transform.origin + _station_offset + forward * _zoom_current + jitter)
