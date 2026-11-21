class_name ChalkDrawing3D
extends Node3D
## Freehand chalk on the workbench. Press C to pick up the chalk, then drag on
## the bench to draw. On release the stroke goes to SigilRecognizer; a
## recognised sigil glows in its field colour and spawns a SpellField3D.
## Press X to wipe every sigil. Android: tap the chalk button (TODO: HUD
## button), then draw with one finger.

const STROKE_WIDTH_METERS: float = 0.006
const MIN_POINT_SPACING_METERS: float = 0.004

@export var camera: Camera3D
@export var bench_top_y_meters: float = 0.8

static var active: bool = false
static var last_result_text: String = ""

var _drawing: bool = false
var _points: PackedVector2Array = PackedVector2Array()
var _current_mesh: MeshInstance3D
var _current_imesh: ImmediateMesh
var _chalk_material: StandardMaterial3D


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
	_chalk_material = StandardMaterial3D.new()
	_chalk_material.albedo_color = Color(0.93, 0.92, 0.88, 0.85)
	_chalk_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_chalk_material.roughness = 1.0
	_chalk_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_C:
			active = not active
			TactileGrabber3D.input_captured = active
			last_result_text = "Chalk in hand: draw a closed shape on the bench" if active else ""
		elif key.keycode == KEY_X:
			_wipe()
		return
	if not active:
		return
	var press: InputEventMouseButton = event as InputEventMouseButton
	if press != null and press.button_index == MOUSE_BUTTON_LEFT:
		if press.pressed:
			_begin(press.position)
		else:
			_finish()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _drawing:
		_extend(motion.position)
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.device != InputEvent.DEVICE_ID_EMULATION and touch.index == 0:
		if touch.pressed:
			_begin(touch.position)
		else:
			_finish()
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and drag.device != InputEvent.DEVICE_ID_EMULATION and drag.index == 0 and _drawing:
		_extend(drag.position)


## Draw a complete stroke from bench-plane points (x, z). Used by tests, demos
## and future input methods. Returns the recogniser result.
func draw_world_stroke(points: PackedVector2Array) -> SigilRecognizer.Result:
	_drawing = true
	_points = points
	_current_imesh = ImmediateMesh.new()
	_current_mesh = MeshInstance3D.new()
	_current_mesh.mesh = _current_imesh
	_current_mesh.material_override = _chalk_material.duplicate() as StandardMaterial3D
	_current_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_current_mesh)
	_rebuild_stroke()
	var result: SigilRecognizer.Result = SigilRecognizer.analyze(_points)
	_finish()
	return result


static func polygon_points(center: Vector2, radius: float, sides: int, per_side: int = 14) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for s: int in sides:
		var a0: float = TAU * float(s) / float(sides) + 0.2
		var a1: float = TAU * float(s + 1) / float(sides) + 0.2
		for k: int in per_side:
			pts.append(center + Vector2(cos(a0), sin(a0)).lerp(Vector2(cos(a1), sin(a1)), float(k) / float(per_side)) * radius)
	pts.append(pts[0])
	return pts


func _bench_point(screen: Vector2) -> Variant:
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	if dir.y > -1e-4:
		return null
	var t: float = (bench_top_y_meters - origin.y) / dir.y
	var hit: Vector3 = origin + dir * t
	return Vector2(hit.x, hit.z)


func _begin(screen: Vector2) -> void:
	var p: Variant = _bench_point(screen)
	if p == null:
		return
	_drawing = true
	_points = PackedVector2Array([p as Vector2])
	_current_imesh = ImmediateMesh.new()
	_current_mesh = MeshInstance3D.new()
	_current_mesh.mesh = _current_imesh
	_current_mesh.material_override = _chalk_material.duplicate() as StandardMaterial3D
	_current_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_current_mesh)


func _extend(screen: Vector2) -> void:
	var p: Variant = _bench_point(screen)
	if p == null:
		return
	if (p as Vector2).distance_to(_points[_points.size() - 1]) < MIN_POINT_SPACING_METERS:
		return
	_points.append(p as Vector2)
	# Chalk rasps while it moves; the loop fades as soon as the hand stops.
	AudioDirector.loop(&"chalk", &"chalk_loop", Vector3((p as Vector2).x, bench_top_y_meters, (p as Vector2).y), 0.8, 1.0, -8.0)
	_rebuild_stroke()


func _rebuild_stroke() -> void:
	_current_imesh.clear_surfaces()
	if _points.size() < 2:
		return
	_current_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var y: float = bench_top_y_meters + 0.0008
	for i: int in _points.size():
		var a: Vector2 = _points[maxi(i - 1, 0)]
		var b: Vector2 = _points[mini(i + 1, _points.size() - 1)]
		var side: Vector2 = (b - a).orthogonal().normalized() * STROKE_WIDTH_METERS * 0.5
		var p: Vector2 = _points[i]
		_current_imesh.surface_set_normal(Vector3.UP)
		_current_imesh.surface_add_vertex(Vector3(p.x + side.x, y, p.y + side.y))
		_current_imesh.surface_set_normal(Vector3.UP)
		_current_imesh.surface_add_vertex(Vector3(p.x - side.x, y, p.y - side.y))
	_current_imesh.surface_end()


func _finish() -> void:
	if not _drawing:
		return
	_drawing = false
	var result: SigilRecognizer.Result = SigilRecognizer.analyze(_points)
	last_result_text = result.describe()
	if result.kind == SigilRecognizer.Kind.NONE:
		var faded: StandardMaterial3D = _current_mesh.material_override as StandardMaterial3D
		faded.albedo_color.a = 0.35
		return
	var field: SpellField3D = SpellField3D.new()
	field.setup(result, bench_top_y_meters)
	add_child(field)
	var last: Vector2 = _points[_points.size() - 1]
	AudioDirector.play(&"spell_cast", Vector3(last.x, bench_top_y_meters, last.y), lerpf(-10.0, -3.0, clampf(result.power, 0.0, 1.0)), lerpf(0.9, 1.15, clampf(result.power, 0.0, 1.0)))
	var glow: StandardMaterial3D = _current_mesh.material_override as StandardMaterial3D
	glow.albedo_color = field.get_color()
	glow.emission_enabled = true
	glow.emission = field.get_color()
	glow.emission_energy_multiplier = 1.0 + result.power * 3.0


func _wipe() -> void:
	for child: Node in get_children():
		child.queue_free()
	last_result_text = "Sigils wiped"
