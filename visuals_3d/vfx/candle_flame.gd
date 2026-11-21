class_name CandleFlame
extends Node3D
## Living candle: the flame mesh sways and the light flickers with layered
## noise, and any open vessel whose rim is held close to the flame gets an
## ignition source (hold a flask of spirit over the candle to light it).

@export var flame: Node3D
@export var light: OmniLight3D
@export var base_energy: float = 1.3
@export var ignite_radius_meters: float = 0.07

var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0
var _base_flame_scale: Vector3 = Vector3.ONE
var _halo: MeshInstance3D


func _ready() -> void:
	_noise.seed = 4242
	_noise.frequency = 2.2
	if flame != null:
		_base_flame_scale = flame.scale
		_add_halo()


func _process(delta: float) -> void:
	_time += delta
	var n1: float = _noise.get_noise_1d(_time * 3.0)
	var n2: float = _noise.get_noise_1d(_time * 11.0 + 100.0)
	if light != null:
		light.light_energy = base_energy * (1.0 + n1 * 0.25 + n2 * 0.08)
	if _halo != null:
		_halo.set_instance_shader_parameter(&"strength", 1.0 + n1 * 0.3 + n2 * 0.1)
	if flame != null:
		flame.scale = _base_flame_scale * Vector3(1.0 - n2 * 0.1, 1.0 + n1 * 0.25, 1.0 - n2 * 0.1)
		flame.rotation.z = n2 * 0.12


func _physics_process(_delta: float) -> void:
	var tip: Vector3 = flame.global_position if flame != null else global_position
	AudioDirector.loop(&"candle", &"candle_loop", tip, 0.6, 1.0, -16.0)
	for vessel: Vessel3D in Vessel3D.all_vessels:
		var lip: Vector3 = vessel.global_transform * Vector3(0.0, vessel.get_lip_local_y(), 0.0)
		if lip.distance_to(tip) < ignite_radius_meters:
			vessel.ignition_source = true


## Warm glow disc around the flame (additive billboard, flickers with it).
func _add_halo() -> void:
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = preload("res://visuals_3d/shaders/candle_halo.gdshader")
	quad.material = mat
	_halo.mesh = quad
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.extra_cull_margin = 0.1
	_halo.layers = flame.layers if flame is VisualInstance3D else 1  # kept out of the reflection probe
	flame.get_parent().add_child.call_deferred(_halo)
	_halo.position = flame.position + Vector3(0.0, 0.01, 0.0)
