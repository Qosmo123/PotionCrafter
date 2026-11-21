class_name HotPlate3D
extends StaticBody3D
## Iron hot plate. Vessels resting on it gain heat through a contact
## conductance: Q = G * (T_plate - T_contents). The plate is hotter than the
## contents, so they warm up, and they can never pass the plate's temperature.
## Click the knob in front to step through Off, Low, Medium and High; a
## caption shows the setting. Vessels glide onto the plate when put down near
## it (a seat).

const MAX_VESSELS: int = 8

@export var plate_radius_meters: float = 0.09
@export var plate_height_meters: float = 0.02
@export var plate_temperature_kelvin: float = 720.0
@export var contact_conductance_w_k: float = 2.5
@export var heating_enabled: bool = true

## Plate temperature for each knob setting (Off, Low, Medium, High).
const LEVEL_KELVIN: PackedFloat32Array = [293.0, 420.0, 560.0, 720.0]
const LEVEL_NAMES: PackedStringArray = ["off", "low", "medium", "high"]

var level: int = 3
var _vessels: Array[Vessel3D] = []
var _plate_material: StandardMaterial3D
var _knob: StaticBody3D
var _knob_visual: Node3D
var _caption: Label3D


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	_vessels.resize(MAX_VESSELS)

	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = plate_radius_meters
	mesh.bottom_radius = plate_radius_meters * 1.08
	mesh.height = plate_height_meters
	mesh.radial_segments = 40
	var iron: StandardMaterial3D = StandardMaterial3D.new()
	iron.albedo_color = Color(0.09, 0.085, 0.085)
	iron.metallic = 0.9
	iron.roughness = 0.5
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = iron
	add_child(visual)
	# Glowing spiral element: concentric coil rings on the plate surface.
	_plate_material = StandardMaterial3D.new()
	_plate_material.albedo_color = Color(0.2, 0.06, 0.03)
	_plate_material.roughness = 0.6
	_plate_material.emission_enabled = true
	_plate_material.emission = Color(1.0, 0.3, 0.06)
	for i: int in 3:
		var coil: TorusMesh = TorusMesh.new()
		var r: float = plate_radius_meters * (0.3 + 0.22 * float(i))
		coil.inner_radius = r - 0.004
		coil.outer_radius = r + 0.004
		coil.rings = 48
		coil.ring_segments = 8
		var ring: MeshInstance3D = MeshInstance3D.new()
		ring.mesh = coil
		ring.material_override = _plate_material
		ring.position.y = plate_height_meters * 0.5
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)

	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = plate_radius_meters
	shape.height = plate_height_meters
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	var sensor_shape: CylinderShape3D = CylinderShape3D.new()
	sensor_shape.radius = plate_radius_meters
	sensor_shape.height = 0.03
	var sensor_collision: CollisionShape3D = CollisionShape3D.new()
	sensor_collision.shape = sensor_shape
	var sensor: Area3D = Area3D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = SimConstants.LAYER_RIGID_VESSEL
	sensor.monitorable = false
	sensor.position = Vector3(0.0, 0.5 * plate_height_meters + 0.015, 0.0)
	sensor.add_child(sensor_collision)
	sensor.body_entered.connect(_on_body_entered)
	sensor.body_exited.connect(_on_body_exited)
	add_child(sensor)
	_build_controls()
	var seat: SupportStand3D = SupportStand3D.new()
	seat.kind = SupportStand3D.Kind.PAD
	seat.pad_radius_meters = plate_radius_meters * 0.7
	seat.position.y = plate_height_meters * 0.5 + 0.001
	add_child(seat)
	level = 3 if heating_enabled else 0
	_update_glow()


## Control block in front of the plate with a big brass knob.
func _build_controls() -> void:
	var front_z: float = plate_radius_meters * 1.08 + 0.016
	var block: BoxMesh = BoxMesh.new()
	block.size = Vector3(0.06, 0.03, 0.03)
	block.material = PropMaterials.textured("iron", Color(0.16, 0.16, 0.17), 0.12, 0.6)
	var block_mi: MeshInstance3D = MeshInstance3D.new()
	block_mi.mesh = block
	block_mi.position = Vector3(0.0, -plate_height_meters * 0.5 + 0.005, front_z)
	add_child(block_mi)
	_knob_visual = Node3D.new()
	_knob_visual.position = Vector3(0.0, -plate_height_meters * 0.5 + 0.006, front_z + 0.02)
	add_child(_knob_visual)
	var knob: CylinderMesh = CylinderMesh.new()
	knob.top_radius = 0.011
	knob.bottom_radius = 0.013
	knob.height = 0.012
	knob.radial_segments = 24
	knob.material = PropMaterials.textured("metal", Color(0.9, 0.68, 0.32), 0.08, 0.9)
	var knob_mi: MeshInstance3D = MeshInstance3D.new()
	knob_mi.mesh = knob
	knob_mi.rotation.x = PI * 0.5
	_knob_visual.add_child(knob_mi)
	var mark: BoxMesh = BoxMesh.new()
	mark.size = Vector3(0.0025, 0.009, 0.002)
	var mark_mat: StandardMaterial3D = StandardMaterial3D.new()
	mark_mat.albedo_color = Color(0.1, 0.05, 0.03)
	mark.material = mark_mat
	var mark_mi: MeshInstance3D = MeshInstance3D.new()
	mark_mi.mesh = mark
	mark_mi.position = Vector3(0.0, 0.005, 0.0065)
	_knob_visual.add_child(mark_mi)
	_knob = ClickSwitch.make_button(self, Vector3(0.07, 0.04, 0.05), Vector3(0.0, -plate_height_meters * 0.5 + 0.006, front_z + 0.01))
	_caption = ClickSwitch.make_caption(self, Vector3(0.0, 0.004, front_z + 0.045))


func _unhandled_input(event: InputEvent) -> void:
	if _knob != null and ClickSwitch.clicked(self, event, [_knob]) != null:
		set_level((level + 1) % LEVEL_KELVIN.size())
		get_viewport().set_input_as_handled()


func set_level(value: int) -> void:
	value = clampi(value, 0, LEVEL_KELVIN.size() - 1)
	if value != level and is_inside_tree():
		AudioDirector.play(&"click", global_position, -6.0, 0.9 + 0.08 * float(value))
	level = value
	heating_enabled = level > 0
	plate_temperature_kelvin = LEVEL_KELVIN[level]
	_update_glow()


func set_heating(enabled: bool) -> void:
	set_level(LEVEL_KELVIN.size() - 1 if enabled else 0)


func _physics_process(_delta: float) -> void:
	if not heating_enabled:
		return
	AudioDirector.loop(&"hotplate", &"hotplate_loop", global_position, 0.5, 1.0, -22.0)
	for i: int in MAX_VESSELS:
		var vessel: Vessel3D = _vessels[i]
		if vessel == null:
			continue
		if not is_instance_valid(vessel):
			_vessels[i] = null
			continue
		if vessel.mixture == null:
			continue
		vessel.external_heat_watts += contact_conductance_w_k * (plate_temperature_kelvin - vessel.mixture.temperature_kelvin)
		# A glowing element above ~600 K lights flammable vapour.
		if plate_temperature_kelvin > 600.0:
			vessel.ignition_source = true


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


func _update_glow() -> void:
	if _plate_material != null:
		_plate_material.emission_energy_multiplier = [0.0, 0.5, 1.0, 1.6][level] if heating_enabled else 0.0
	if _knob_visual != null:
		_knob_visual.rotation.z = -float(level) * 0.9
	if _caption != null:
		_caption.text = "Stove · %s  (click knob)" % LEVEL_NAMES[level]
