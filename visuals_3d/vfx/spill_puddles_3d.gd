class_name SpillPuddles3D
extends Node3D
## Puddles of spilled liquid on the bench (and on machines and stands).
##
## Liquid that misses a vessel, runs over a full rim or is poured onto the
## bench lands here: it joins the nearest puddle on the same surface or starts
## a new one, the puddle spreads with the volume it holds (a thin film about
## 1.5 mm deep, so 10 mL covers a palm-sized patch), takes the liquid's colour
## and slowly dries. Presentation only: the vessel has already counted the
## spilled mass. Puddles are pooled and reused (oldest first), so spilling
## never allocates.

const POOL: int = 24
const FILM_METERS: float = 0.0015
const MAX_RADIUS_METERS: float = 0.16
const MERGE_MARGIN_METERS: float = 0.02
## Water-like liquids dry in about a minute and a half; syrups linger.
const DRY_SECONDS: float = 90.0
const SHADER: Shader = preload("res://visuals_3d/shaders/spill_puddle.gdshader")

static var _instance: SpillPuddles3D = null

var _meshes: Array[MeshInstance3D] = []
var _volume_m3: PackedFloat32Array = PackedFloat32Array()
var _color: PackedColorArray = PackedColorArray()
var _fresh: PackedFloat32Array = PackedFloat32Array()
var _dry_rate: PackedFloat32Array = PackedFloat32Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _ray: PhysicsRayQueryParameters3D
var _splash_cooldown: float = 0.0


## Spill `volume_m3` of liquid of this colour, falling from near `at`.
## `viscosity_pas` slows drying (and how far it spreads).
static func spill(context: Node, at: Vector3, volume_m3: float, color: Color, viscosity_pas: float = 0.001) -> void:
	if volume_m3 <= 0.0 or context == null or not context.is_inside_tree():
		return
	var pool: SpillPuddles3D = _get_pool(context)
	if pool != null:
		pool._spill(at, volume_m3, color, viscosity_pas)


## Total liquid currently lying in puddles (for tests and the HUD).
static func total_volume_m3() -> float:
	if _instance == null or not is_instance_valid(_instance):
		return 0.0
	var total: float = 0.0
	for v: float in _instance._volume_m3:
		total += v
	return total


static func _get_pool(context: Node) -> SpillPuddles3D:
	if _instance != null and is_instance_valid(_instance) and _instance.is_inside_tree():
		return _instance
	var tree: SceneTree = context.get_tree()
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	_instance = SpillPuddles3D.new()
	_instance.name = "SpillPuddles"
	host.add_child(_instance)
	return _instance


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0)
	for i: int in POOL:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.set_instance_shader_parameter(&"seed", float(i) * 3.7)
		add_child(mi)
		_meshes.append(mi)
	_volume_m3.resize(POOL)
	_color.resize(POOL)
	_fresh.resize(POOL)
	_dry_rate.resize(POOL)
	_age.resize(POOL)
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = SimConstants.LAYER_STATIC_BENCH


func _spill(at: Vector3, volume_m3: float, color: Color, viscosity_pas: float) -> void:
	# Where it lands: the solid surface under the point.
	_ray.from = at + Vector3(0.0, 0.01, 0.0)
	_ray.to = at + Vector3(0.0, -1.2, 0.0)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return
	var ground: Vector3 = hit["position"]
	# Join a puddle on the same surface that this one would touch.
	var best: int = -1
	var best_d: float = INF
	for i: int in POOL:
		if _volume_m3[i] <= 0.0:
			continue
		var p: Vector3 = _meshes[i].global_position
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
		_meshes[best].global_position = ground + Vector3(0.0, 0.0008 + 0.0001 * float(best % 5), 0.0)
		_meshes[best].visible = true
		if _splash_cooldown <= 0.0:
			_splash_cooldown = 0.25
			AudioDirector.play(&"splash", ground, lerpf(-16.0, -6.0, clampf(volume_m3 / 5e-6, 0.0, 1.0)))
	# Mix colours by volume; drift the centre a little toward the new liquid.
	var old_v: float = _volume_m3[best]
	var total: float = old_v + volume_m3
	_color[best] = _color[best].lerp(color, volume_m3 / total)
	_volume_m3[best] = total
	_fresh[best] = 1.0
	_dry_rate[best] = 1.0 / (DRY_SECONDS * (1.0 + clampf(viscosity_pas, 0.0, 20.0) * 3.0))
	var mi: MeshInstance3D = _meshes[best]
	var drift: Vector3 = (ground - mi.global_position) * (volume_m3 / total) * 0.5
	mi.global_position += Vector3(drift.x, 0.0, drift.z)
	_apply(best)


func _free_slot() -> int:
	var oldest: int = 0
	for i: int in POOL:
		if _volume_m3[i] <= 0.0:
			return i
		if _age[i] > _age[oldest]:
			oldest = i
	return oldest


func _radius(i: int) -> float:
	return minf(sqrt(_volume_m3[i] / (PI * FILM_METERS)), MAX_RADIUS_METERS)


func _apply(i: int) -> void:
	var r: float = maxf(_radius(i), 0.004)
	var mi: MeshInstance3D = _meshes[i]
	mi.scale = Vector3(r, 1.0, r)
	var c: Color = _color[i]
	mi.set_instance_shader_parameter(&"liquid_color", Color(c.r, c.g, c.b, clampf(c.a + 0.25, 0.35, 0.85)))
	mi.set_instance_shader_parameter(&"fresh", _fresh[i])


func _process(delta: float) -> void:
	_splash_cooldown -= delta
	for i: int in POOL:
		if _volume_m3[i] <= 0.0:
			continue
		_age[i] += delta
		# Evaporation shrinks the film; the last of it goes quickly.
		_volume_m3[i] -= maxf(_volume_m3[i] * _dry_rate[i], 2e-8) * delta
		_fresh[i] = maxf(_fresh[i] - delta * 0.8, 0.0)
		if _volume_m3[i] <= 1e-8:
			_volume_m3[i] = 0.0
			_meshes[i].visible = false
			continue
		_meshes[i].set_instance_shader_parameter(&"dry", clampf(1.0 - _volume_m3[i] / 2e-6, 0.0, 1.0) * 0.6)
		_apply(i)
