class_name Burner3D
extends StaticBody3D
## Spirit burner under an iron tripod with a wire gauze. Click the lamp to
## light it or put it out. A vessel set on the gauze is heated by the flame
## (contact conductance toward the flame temperature, faster than the hot
## plate), and flammable contents held near the flame catch fire.
## Vessels glide onto the gauze when put down nearby (a seat).

const MAX_VESSELS: int = 4

@export var lit: bool = false
@export var flame_temperature_kelvin: float = 1050.0
@export var contact_conductance_w_k: float = 3.6
@export var gauze_height_meters: float = 0.12
@export var tripod_radius_meters: float = 0.055

var _vessels: Array[Vessel3D] = []
var _flame: Node3D
var _flame_light: OmniLight3D
var _lamp: StaticBody3D
var _caption: Label3D
var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	_vessels.resize(MAX_VESSELS)
	_noise.seed = 77
	_noise.frequency = 2.4
	var iron: StandardMaterial3D = PropMaterials.textured("iron", Color(0.24, 0.24, 0.26), 0.12, 0.7)
	var brass: StandardMaterial3D = PropMaterials.textured("metal", Color(0.9, 0.68, 0.32), 0.1, 0.9)
	# Spirit lamp: squat glass bowl of blue spirit, brass collar, wick.
	var bowl: MeshInstance3D = MeshInstance3D.new()
	bowl.mesh = MeshUtil.lathe(PackedVector2Array([Vector2(0.0, 0.046), Vector2(0.012, 0.046), Vector2(0.03, 0.036), Vector2(0.036, 0.02), Vector2(0.034, 0.006), Vector2(0.028, 0.0), Vector2(0.0, 0.0)]), 32)
	bowl.material_override = QualityTier.pick_material(PropMaterials.GLASS_PC_MATERIAL, PropMaterials.GLASS_MOBILE_MATERIAL)
	bowl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bowl)
	var spirit: MeshInstance3D = MeshInstance3D.new()
	spirit.mesh = MeshUtil.lathe(PackedVector2Array([Vector2(0.0, 0.022), Vector2(0.032, 0.022), Vector2(0.031, 0.007), Vector2(0.026, 0.002), Vector2(0.0, 0.002)]), 32)
	var spirit_mat: StandardMaterial3D = StandardMaterial3D.new()
	spirit_mat.albedo_color = Color(0.35, 0.55, 0.95, 0.6)
	spirit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spirit_mat.roughness = 0.1
	spirit.material_override = spirit_mat
	add_child(spirit)
	var collar: CylinderMesh = CylinderMesh.new()
	collar.top_radius = 0.008
	collar.bottom_radius = 0.012
	collar.height = 0.012
	collar.material = brass
	var collar_mi: MeshInstance3D = MeshInstance3D.new()
	collar_mi.mesh = collar
	collar_mi.position.y = 0.052
	add_child(collar_mi)
	# Tripod: ring, three splayed legs, wire gauze square on top.
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = tripod_radius_meters - 0.003
	ring.outer_radius = tripod_radius_meters + 0.003
	ring.rings = 40
	ring.ring_segments = 8
	ring.material = iron
	var ring_mi: MeshInstance3D = MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.position.y = gauze_height_meters - 0.004
	add_child(ring_mi)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0 + PI * 0.5
		var top: Vector3 = Vector3(cos(a) * tripod_radius_meters, gauze_height_meters - 0.004, sin(a) * tripod_radius_meters)
		var foot: Vector3 = Vector3(cos(a) * (tripod_radius_meters + 0.02), 0.0, sin(a) * (tripod_radius_meters + 0.02))
		var leg: CylinderMesh = CylinderMesh.new()
		leg.top_radius = 0.003
		leg.bottom_radius = 0.003
		leg.height = top.distance_to(foot)
		leg.material = iron
		var leg_mi: MeshInstance3D = MeshInstance3D.new()
		leg_mi.mesh = leg
		var axis: Vector3 = (top - foot).normalized()
		var x: Vector3 = axis.cross(Vector3.FORWARD).normalized()
		leg_mi.transform = Transform3D(Basis(x, axis, x.cross(axis)), (top + foot) * 0.5)
		add_child(leg_mi)
	var gauze: BoxMesh = BoxMesh.new()
	gauze.size = Vector3(tripod_radius_meters * 2.3, 0.002, tripod_radius_meters * 2.3)
	var gauze_mat: StandardMaterial3D = StandardMaterial3D.new()
	gauze_mat.albedo_color = Color(0.32, 0.31, 0.3)
	gauze_mat.metallic = 0.6
	gauze_mat.roughness = 0.6
	gauze.material = gauze_mat
	var gauze_mi: MeshInstance3D = MeshInstance3D.new()
	gauze_mi.mesh = gauze
	gauze_mi.position.y = gauze_height_meters
	add_child(gauze_mi)
	var centre_mat: StandardMaterial3D = StandardMaterial3D.new()
	centre_mat.albedo_color = Color(0.85, 0.85, 0.82)
	centre_mat.roughness = 0.9
	var centre: CylinderMesh = CylinderMesh.new()
	centre.top_radius = tripod_radius_meters * 0.55
	centre.bottom_radius = tripod_radius_meters * 0.55
	centre.height = 0.0024
	centre.material = centre_mat
	var centre_mi: MeshInstance3D = MeshInstance3D.new()
	centre_mi.mesh = centre
	centre_mi.position.y = gauze_height_meters + 0.0004
	add_child(centre_mi)
	# Physical gauze top (vessels stand on it) and the clickable lamp.
	var top_shape: BoxShape3D = BoxShape3D.new()
	top_shape.size = Vector3(tripod_radius_meters * 2.3, 0.006, tripod_radius_meters * 2.3)
	var top_cs: CollisionShape3D = CollisionShape3D.new()
	top_cs.shape = top_shape
	top_cs.position.y = gauze_height_meters - 0.002
	add_child(top_cs)
	_lamp = ClickSwitch.make_button(self, Vector3(0.08, 0.07, 0.08), Vector3(0.0, 0.035, 0.0))
	_build_flame()
	# Heat sensor just above the gauze.
	var sensor_shape: BoxShape3D = BoxShape3D.new()
	sensor_shape.size = Vector3(tripod_radius_meters * 2.0, 0.03, tripod_radius_meters * 2.0)
	var sensor_cs: CollisionShape3D = CollisionShape3D.new()
	sensor_cs.shape = sensor_shape
	var sensor: Area3D = Area3D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = SimConstants.LAYER_RIGID_VESSEL
	sensor.monitorable = false
	sensor.position.y = gauze_height_meters + 0.016
	sensor.add_child(sensor_cs)
	sensor.body_entered.connect(_on_body_entered)
	sensor.body_exited.connect(_on_body_exited)
	add_child(sensor)
	# A seat on the gauze.
	var seat: SupportStand3D = SupportStand3D.new()
	seat.kind = SupportStand3D.Kind.PAD
	seat.pad_radius_meters = tripod_radius_meters
	seat.accept_round = true
	seat.position.y = gauze_height_meters + 0.001
	add_child(seat)
	_caption = ClickSwitch.make_caption(self, Vector3(0.0, 0.012, 0.09))
	_apply()


func _build_flame() -> void:
	_flame = Node3D.new()
	_flame.position.y = 0.062
	add_child(_flame)
	for layer: Array in [[Vector2(0.011, 0.04), Color(1.0, 0.55, 0.18), 0.7], [Vector2(0.006, 0.022), Color(0.35, 0.55, 1.0), 0.9]]:
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = (layer[0] as Vector2).x
		sphere.height = (layer[0] as Vector2).y
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(layer[1] as Color, float(layer[2]))
		sphere.material = mat
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = sphere
		mi.position.y = (layer[0] as Vector2).y * 0.45
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame.add_child(mi)
	_flame_light = OmniLight3D.new()
	_flame_light.light_color = Color(1.0, 0.65, 0.3)
	_flame_light.light_energy = 0.6
	_flame_light.omni_range = 0.5
	_flame_light.light_specular = 0.1
	_flame_light.position.y = 0.03
	_flame.add_child(_flame_light)


func toggle() -> void:
	lit = not lit
	AudioDirector.play(&"ignite" if lit else &"switch", global_position + Vector3(0.0, 0.06, 0.0), -6.0 if lit else -10.0, 1.0 if lit else 0.8)
	_apply()


func _apply() -> void:
	_flame.visible = lit
	_caption.text = "Burner · lit" if lit else "Burner · click to light"
	set_process(lit)


func _unhandled_input(event: InputEvent) -> void:
	if ClickSwitch.clicked(self, event, [_lamp]) != null:
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_time += delta
	var n1: float = _noise.get_noise_1d(_time * 3.0)
	var n2: float = _noise.get_noise_1d(_time * 13.0 + 40.0)
	_flame.scale = Vector3(1.0 - n2 * 0.1, 1.0 + n1 * 0.25, 1.0 - n2 * 0.1)
	_flame.rotation.z = n2 * 0.1
	_flame_light.light_energy = 0.6 * (1.0 + n1 * 0.25)


func _physics_process(_delta: float) -> void:
	if not lit:
		return
	var tip: Vector3 = _flame.global_position + Vector3(0.0, 0.03, 0.0)
	AudioDirector.loop(&"burner", &"fire_loop", tip, 0.45, 1.25, -16.0)
	for i: int in MAX_VESSELS:
		var vessel: Vessel3D = _vessels[i]
		if vessel == null:
			continue
		if not is_instance_valid(vessel):
			_vessels[i] = null
			continue
		if vessel.mixture != null:
			vessel.external_heat_watts += contact_conductance_w_k * (flame_temperature_kelvin - vessel.mixture.temperature_kelvin)
	# Open flame lights flammable vapour from rims held close.
	for vessel: Vessel3D in Vessel3D.all_vessels:
		var lip: Vector3 = vessel.global_transform * Vector3(0.0, vessel.get_lip_local_y(), 0.0)
		if lip.distance_to(tip) < 0.06:
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
