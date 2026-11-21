class_name PourStream3D
extends MeshInstance3D
## One continuous liquid stream, laid along its falling arc by
## pour_stream.gdshader. Owners call show_arc() every tick while liquid
## flows and hide_stream() when it stops; the mesh is built once and only
## shader parameters change, so pouring never allocates.

const SEGMENTS: int = 48
const SHADER: Shader = preload("res://visuals_3d/shaders/pour_stream.gdshader")

static var _strip: ArrayMesh = null
static var _material: ShaderMaterial = null

var _width_smoothed: float = 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _strip_mesh()
	material_override = _shared_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Vertices are placed in the shader: never cull it.
	custom_aabb = AABB(Vector3(-50.0, -50.0, -50.0), Vector3(100.0, 100.0, 100.0))
	visible = false


## Show the stream leaving `from` with `velocity` and falling to height
## `land_y`. `width_m` is its width at the lip.
func show_arc(from: Vector3, velocity: Vector3, land_y: float, width_m: float, color: Color, viscosity_pas: float, glow: float = 0.0) -> void:
	var g: float = SimConstants.GRAVITY_M_S2
	var drop: float = maxf(from.y - land_y, 0.0)
	var vy: float = -velocity.y  # downward speed
	var t: float = (-vy + sqrt(vy * vy + 2.0 * g * drop)) / g if drop > 0.0 else 0.0
	# Width eases instead of flickering with every slosh of the flow.
	_width_smoothed = width_m if _width_smoothed <= 0.0 else lerpf(_width_smoothed, width_m, 0.25)
	set_instance_shader_parameter(&"start_point", from)
	set_instance_shader_parameter(&"start_velocity", velocity)
	set_instance_shader_parameter(&"duration", maxf(t, 0.005))
	set_instance_shader_parameter(&"start_width", _width_smoothed)
	set_instance_shader_parameter(&"liquid_color", color)
	set_instance_shader_parameter(&"viscosity", clampf(viscosity_pas, 0.0, 5.0))
	set_instance_shader_parameter(&"glow", glow)
	visible = true


func hide_stream() -> void:
	visible = false
	_width_smoothed = 0.0


## Where a stream leaving `from` with `velocity` crosses height `y`.
static func point_at_height(from: Vector3, velocity: Vector3, y: float) -> Vector3:
	var g: float = SimConstants.GRAVITY_M_S2
	var drop: float = maxf(from.y - y, 0.0)
	var vy: float = -velocity.y
	var t: float = (-vy + sqrt(vy * vy + 2.0 * g * drop)) / g if drop > 0.0 else 0.0
	return Vector3(from.x + velocity.x * t, y, from.z + velocity.z * t)


static func _strip_mesh() -> ArrayMesh:
	if _strip != null:
		return _strip
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	for i: int in SEGMENTS + 1:
		var t: float = float(i) / float(SEGMENTS)
		for s: int in 2:
			verts.append(Vector3(float(s), -t, 0.0))
			uvs.append(Vector2(float(s), t))
	for i: int in SEGMENTS:
		var a: int = i * 2
		idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_strip = ArrayMesh.new()
	_strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _strip


static func _shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter(&"gravity", SimConstants.GRAVITY_M_S2)
	return _material
