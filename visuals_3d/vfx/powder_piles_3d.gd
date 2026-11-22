class_name PowderPiles3D
extends Node3D
## Little heaps of spilled powder on the bench (and on stands and machines).
##
## Powder that misses a vessel lands here: it joins the nearest heap on the
## same surface or starts a new one. A heap is a cone at the powder's angle
## of repose, so its radius grows with the cube root of the volume it holds
## (r = cbrt(3V / (pi tan(theta)))): a pinch is a dot, a scoop a proper mound.
## Unlike puddles, powder doesn't dry: heaps stay until the pool needs the
## slot (oldest first). Presentation only: the vessel has already counted the
## spilled mass. Pooled, so spilling never allocates.

const POOL: int = 24
const MAX_RADIUS_METERS: float = 0.09
const MERGE_MARGIN_METERS: float = 0.01
const SHADER: Shader = preload("res://visuals_3d/shaders/powder_pile.gdshader")

static var _instance: PowderPiles3D = null

var _meshes: Array[MeshInstance3D] = []
var _volume_m3: PackedFloat32Array = PackedFloat32Array()
var _tan_repose: PackedFloat32Array = PackedFloat32Array()
var _color: PackedColorArray = PackedColorArray()
var _age: PackedFloat32Array = PackedFloat32Array()
var _ground: PackedVector3Array = PackedVector3Array()
var _ray: PhysicsRayQueryParameters3D
var _sound_cooldown: float = 0.0


## Spill `volume_m3` of powder of this colour, falling from near `at`.
## `repose_deg` is the powder's angle of repose (the heap's slope).
static func spill(context: Node, at: Vector3, volume_m3: float, color: Color, repose_deg: float = 34.0) -> void:
	if volume_m3 <= 0.0 or context == null or not context.is_inside_tree():
		return
	var pool: PowderPiles3D = _get_pool(context)
	if pool != null:
		pool._spill(at, volume_m3, color, repose_deg)


## Total powder lying in heaps (for tests).
static func total_volume_m3() -> float:
	if _instance == null or not is_instance_valid(_instance):
		return 0.0
	var total: float = 0.0
	for v: float in _instance._volume_m3:
		total += v
	return total


static func _get_pool(context: Node) -> PowderPiles3D:
	if _instance != null and is_instance_valid(_instance) and _instance.is_inside_tree():
		return _instance
	var tree: SceneTree = context.get_tree()
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	_instance = PowderPiles3D.new()
	_instance.name = "PowderPiles"
	host.add_child(_instance)
	return _instance


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	# Unit cone: base radius 1 at y = 0, apex at y = 1.
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 24
	cone.rings = 3
	cone.cap_bottom = false
	for i: int in POOL:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visible = false
		mi.set_instance_shader_parameter(&"seed", float(i) * 5.3)
		add_child(mi)
		_meshes.append(mi)
	_volume_m3.resize(POOL)
	_tan_repose.resize(POOL)
	_color.resize(POOL)
	_age.resize(POOL)
	_ground.resize(POOL)
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = SimConstants.LAYER_STATIC_BENCH


func _spill(at: Vector3, volume_m3: float, color: Color, repose_deg: float) -> void:
	_ray.from = at + Vector3(0.0, 0.01, 0.0)
	_ray.to = at + Vector3(0.0, -1.2, 0.0)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return
	var ground: Vector3 = hit["position"]
	var best: int = -1
	var best_d: float = INF
	for i: int in POOL:
		if _volume_m3[i] <= 0.0:
			continue
		var p: Vector3 = _ground[i]
		if absf(p.y - ground.y) > 0.006:
			continue
		var d: float = Vector2(p.x - ground.x, p.z - ground.z).length()
		if d < _radius(i) + MERGE_MARGIN_METERS and d < best_d:
			best = i
			best_d = d
	if best < 0:
		best = _free_slot()
		_volume_m3[best] = 0.0
		_color[best] = color
		_age[best] = 0.0
		_tan_repose[best] = tan(deg_to_rad(clampf(repose_deg, 20.0, 60.0)))
		_ground[best] = ground
		_meshes[best].visible = true
	if _sound_cooldown <= 0.0:
		_sound_cooldown = 0.35
		AudioDirector.play(&"sand_pour", ground, lerpf(-22.0, -10.0, clampf(volume_m3 / 4e-6, 0.0, 1.0)), 1.2)
	var total: float = _volume_m3[best] + volume_m3
	_color[best] = _color[best].lerp(color, volume_m3 / total)
	_tan_repose[best] = lerpf(_tan_repose[best], tan(deg_to_rad(clampf(repose_deg, 20.0, 60.0))), volume_m3 / total)
	_volume_m3[best] = total
	_age[best] = 0.0
	_apply(best)


func _free_slot() -> int:
	var oldest: int = 0
	for i: int in POOL:
		if _volume_m3[i] <= 0.0:
			return i
		if _age[i] > _age[oldest]:
			oldest = i
	return oldest


## Cone base radius for the heap's volume at its angle of repose.
func _radius(i: int) -> float:
	return minf(pow(3.0 * _volume_m3[i] / (PI * maxf(_tan_repose[i], 0.2)), 1.0 / 3.0), MAX_RADIUS_METERS)


func _apply(i: int) -> void:
	var r: float = maxf(_radius(i), 0.002)
	# A heap wider than the cap flattens (it spreads instead of growing taller).
	var h: float = minf(r * _tan_repose[i], 3.0 * _volume_m3[i] / (PI * r * r))
	var mi: MeshInstance3D = _meshes[i]
	h = maxf(h, 0.0005)
	mi.scale = Vector3(r, h, r)
	# The cone mesh is centred on its origin: lift it by half its height.
	mi.global_position = _ground[i] + Vector3(0.0, h * 0.5 + 0.0003, 0.0)
	mi.set_instance_shader_parameter(&"powder_color", _color[i])
	mi.set_instance_shader_parameter(&"height_m", h)


func _process(delta: float) -> void:
	_sound_cooldown -= delta
	for i: int in POOL:
		if _volume_m3[i] > 0.0:
			_age[i] += delta
