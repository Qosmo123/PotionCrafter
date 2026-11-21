class_name SupportStand3D
extends StaticBody3D
## Supports for vessels that can't stand on their own:
##   CORK_RING:  a cork torus; collision is a ring of spheres that cradles a round bottom.
##   TUBE_RACK:  a wooden block with square sockets that hold test tubes upright.

enum Kind { CORK_RING, TUBE_RACK }

@export var kind: Kind = Kind.CORK_RING
@export var ring_radius_meters: float = 0.032
@export var ring_tube_radius_meters: float = 0.012
@export var socket_count: int = 3
@export var socket_size_meters: float = 0.044
@export var rack_height_meters: float = 0.05


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	match kind:
		Kind.CORK_RING:
			_build_cork_ring()
		Kind.TUBE_RACK:
			_build_tube_rack()


func _build_cork_ring() -> void:
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = ring_radius_meters - ring_tube_radius_meters
	torus.outer_radius = ring_radius_meters + ring_tube_radius_meters
	torus.rings = 48
	torus.ring_segments = 16
	var cork: StandardMaterial3D = StandardMaterial3D.new()
	cork.albedo_color = Color(0.62, 0.45, 0.28)
	cork.roughness = 0.92
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = torus
	visual.material_override = cork
	visual.position.y = ring_tube_radius_meters
	add_child(visual)
	for i: int in 10:
		var angle: float = TAU * float(i) / 10.0
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = ring_tube_radius_meters
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.shape = sphere
		shape.position = Vector3(cos(angle) * ring_radius_meters, ring_tube_radius_meters, sin(angle) * ring_radius_meters)
		add_child(shape)


func _build_tube_rack() -> void:
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.28, 0.15)
	wood.roughness = 0.6
	var length_m: float = socket_size_meters * float(socket_count) + 0.02
	var wall_t: float = 0.006
	# Base plate.
	_add_box(Vector3(length_m, 0.01, socket_size_meters + 0.02), Vector3(0.0, 0.005, 0.0), wood)
	# Front and back rails.
	for z_sign: float in [-1.0, 1.0]:
		_add_box(Vector3(length_m, rack_height_meters, wall_t),
			Vector3(0.0, rack_height_meters * 0.5, z_sign * (socket_size_meters * 0.5 + wall_t * 0.5)), wood)
	# Dividers between sockets.
	for i: int in socket_count + 1:
		var x: float = -length_m * 0.5 + 0.01 + float(i) * socket_size_meters
		_add_box(Vector3(wall_t, rack_height_meters, socket_size_meters), Vector3(x, rack_height_meters * 0.5, 0.0), wood)


func _add_box(size: Vector3, center: Vector3, material: Material) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = center
	add_child(visual)
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	shape.position = center
	add_child(shape)
