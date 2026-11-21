class_name Berry3D
extends RigidBody3D
## A physical fantasy berry. Drop it into an open vessel and it bursts into
## its juice substance (mass-conserving: the berry's mass becomes juice moles).
## Glowing berries cast a faint light of their juice's aura colour.

@export var juice: SubstanceData
@export var berry_mass_kg: float = 0.003
@export var radius_meters: float = 0.009

var _burst: bool = false


func _ready() -> void:
	collision_layer = SimConstants.LAYER_SOLID_REAGENT
	collision_mask = SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_SOLID_REAGENT | SimConstants.LAYER_RIGID_VESSEL
	mass = berry_mass_kg
	angular_damp = 4.0
	linear_damp = 0.4
	var physics: PhysicsMaterial = PhysicsMaterial.new()
	physics.friction = 1.0
	physics.rough = true
	physics.bounce = 0.15
	physics_material_override = physics
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius_meters
	mesh.height = radius_meters * 1.9
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	var color: Color = juice.base_albedo_rgba if juice != null else Color(0.6, 0.1, 0.3)
	mat.albedo_color = Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, 1.0)
	mat.roughness = 0.25
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.8
	mat.subsurf_scatter_enabled = true
	mat.subsurf_scatter_strength = 0.5
	if juice != null and juice.emissive_aura_hdr.get_luminance() > 0.01:
		mat.emission_enabled = true
		mat.emission = juice.emissive_aura_hdr
		mat.emission_energy_multiplier = 0.8
	mesh.material = mat
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	add_child(visual)
	var leaf: MeshInstance3D = MeshInstance3D.new()
	var leaf_mesh: PrismMesh = PrismMesh.new()
	leaf_mesh.size = Vector3(0.006, 0.004, 0.002)
	var leaf_mat: StandardMaterial3D = StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.15, 0.4, 0.1)
	leaf_mesh.material = leaf_mat
	leaf.mesh = leaf_mesh
	leaf.position.y = radius_meters
	add_child(leaf)
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius_meters
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = sphere
	add_child(shape)


func _physics_process(_delta: float) -> void:
	if _burst or juice == null:
		return
	for vessel: Vessel3D in Vessel3D.all_vessels:
		if not vessel.open_top or vessel.mixture == null:
			continue
		var local: Vector3 = vessel.global_transform.affine_inverse() * global_position
		var r: float = Vector2(local.x, local.z).length()
		# Resting in (or on) the vessel's opening: it drops in and bursts.
		if r < vessel.get_lip_radius_meters() + radius_meters * 0.6 and local.y < vessel.get_lip_local_y() + radius_meters + 0.006 and local.y > vessel.get_cavity_bottom_local_y() - 0.01:
			var index: int = SubstanceRegistry.index_of(juice)
			if index >= 0:
				vessel.mixture.add_substance(index, berry_mass_kg / juice.molar_mass_kg_mol, SimConstants.AMBIENT_TEMP_KELVIN)
				vessel.add_agitation(0.4)
			_burst = true
			queue_free()
			return
