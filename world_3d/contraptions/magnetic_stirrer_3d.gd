class_name MagneticStirrer3D
extends StaticBody3D
## Scientific magnetic stirrer. A spinning magnet under the plate drives a
## stir bar in any vessel resting on it toward `target_swirl_rad_s`. Thick
## liquids spin up slowly: the coupling falls off with viscosity.
## Press M (PC) to cycle speed: off -> slow -> fast.

const MAX_VESSELS: int = 4
const SPEEDS_RAD_S: PackedFloat32Array = [0.0, 8.0, 20.0]

@export var model: PackedScene
@export var plate_top_local_y: float = 0.066
@export var spin_up_rate_per_s: float = 1.5

var target_swirl_rad_s: float = 8.0
var _speed_index: int = 1
var _vessels: Array[Vessel3D] = []


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	_vessels.resize(MAX_VESSELS)
	if model != null:
		var visual: Node3D = model.instantiate() as Node3D
		add_child(visual)
		PropMaterials.apply(visual)
	var housing: BoxShape3D = BoxShape3D.new()
	housing.size = Vector3(0.17, plate_top_local_y, 0.2)
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = housing
	collider.position.y = plate_top_local_y * 0.5
	add_child(collider)
	var sensor_shape: BoxShape3D = BoxShape3D.new()
	sensor_shape.size = Vector3(0.15, 0.03, 0.15)
	var sensor_collider: CollisionShape3D = CollisionShape3D.new()
	sensor_collider.shape = sensor_shape
	var sensor: Area3D = Area3D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = SimConstants.LAYER_RIGID_VESSEL
	sensor.monitorable = false
	sensor.position.y = plate_top_local_y + 0.015
	sensor.add_child(sensor_collider)
	sensor.body_entered.connect(_on_body_entered)
	sensor.body_exited.connect(_on_body_exited)
	add_child(sensor)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_M:
		_speed_index = (_speed_index + 1) % SPEEDS_RAD_S.size()
		target_swirl_rad_s = SPEEDS_RAD_S[_speed_index]


func _physics_process(delta: float) -> void:
	for i: int in MAX_VESSELS:
		var vessel: Vessel3D = _vessels[i]
		if vessel == null:
			continue
		if not is_instance_valid(vessel):
			_vessels[i] = null
			continue
		if vessel.mixture == null or vessel.mixture.get_liquid_volume_m3() <= 1e-8:
			continue
		var viscosity_pas: float = vessel.mixture.get_liquid_viscosity_pas()
		var blend: float = 1.0 - exp(-delta * spin_up_rate_per_s / (1.0 + viscosity_pas * 3.0))
		# Iron sands lock onto the magnet and drag the whole liquid round (black sand tornado).
		var boost: float = 1.0 + 2.0 * vessel.mixture.get_magnetic()
		vessel.mixture.swirl_rad_s = lerpf(vessel.mixture.swirl_rad_s, target_swirl_rad_s * boost, blend)


func _on_body_entered(body: Node3D) -> void:
	var vessel: Vessel3D = body as Vessel3D
	if vessel == null or _vessels.has(vessel):
		return
	var slot: int = _vessels.find(null)
	if slot >= 0:
		_vessels[slot] = vessel


func _on_body_exited(body: Node3D) -> void:
	var slot: int = _vessels.find(body as Vessel3D)
	if slot >= 0:
		_vessels[slot] = null
