class_name MagnifyingLens3D
extends RigidBody3D
## A brass magnifying glass. Hold it over a vessel and the HUD shows the
## Alchemist's Lens: quick bars for temperature, acidity, thickness and
## arcane aura, so there's no need to walk to the Science Bench for a rough
## reading. (The Science Bench still gives exact numbers.)

const RING_RADIUS_METERS: float = 0.026

## The vessel under the lens right now (null if none), read by the HUD.
var target: Vessel3D = null


func _ready() -> void:
	collision_layer = SimConstants.LAYER_TACTILE_TOOL
	collision_mask = SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_TACTILE_TOOL
	mass = 0.08
	Flat2D.lock(self)
	var brass: StandardMaterial3D = PropMaterials.textured("metal", Color(0.9, 0.68, 0.32), 0.1, 0.9)
	var wood: StandardMaterial3D = PropMaterials.textured("wood", Color(0.3, 0.17, 0.08), 0.3)
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = RING_RADIUS_METERS - 0.003
	ring.outer_radius = RING_RADIUS_METERS + 0.002
	ring.rings = 40
	ring.ring_segments = 10
	ring.material = brass
	var ring_mi: MeshInstance3D = MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.rotation.x = PI * 0.5
	add_child(ring_mi)
	var glass: CylinderMesh = CylinderMesh.new()
	glass.top_radius = RING_RADIUS_METERS - 0.002
	glass.bottom_radius = RING_RADIUS_METERS - 0.002
	glass.height = 0.003
	glass.material = QualityTier.pick_material(PropMaterials.GLASS_PC_MATERIAL, PropMaterials.GLASS_MOBILE_MATERIAL)
	var glass_mi: MeshInstance3D = MeshInstance3D.new()
	glass_mi.mesh = glass
	glass_mi.rotation.x = PI * 0.5
	glass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass_mi)
	var handle: CylinderMesh = CylinderMesh.new()
	handle.top_radius = 0.006
	handle.bottom_radius = 0.0075
	handle.height = 0.075
	handle.material = wood
	var handle_mi: MeshInstance3D = MeshInstance3D.new()
	handle_mi.mesh = handle
	handle_mi.position = Vector3(0.0, -RING_RADIUS_METERS - 0.04, 0.0)
	add_child(handle_mi)
	var ferrule: CylinderMesh = CylinderMesh.new()
	ferrule.top_radius = 0.0065
	ferrule.bottom_radius = 0.0065
	ferrule.height = 0.008
	ferrule.material = brass
	var ferrule_mi: MeshInstance3D = MeshInstance3D.new()
	ferrule_mi.mesh = ferrule
	ferrule_mi.position = Vector3(0.0, -RING_RADIUS_METERS - 0.004, 0.0)
	add_child(ferrule_mi)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(RING_RADIUS_METERS * 2.2, RING_RADIUS_METERS * 2.0 + 0.08, 0.012)
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -0.03
	add_child(cs)
	# Lies flat on the bench until picked up.
	rotation = Vector3(0.0, 0.0, PI * 0.5)


func _physics_process(_delta: float) -> void:
	target = null
	if TactileGrabber3D.current_held != self:
		return
	var best_d: float = INF
	for v: Vessel3D in Vessel3D.all_vessels:
		if not v.is_inside_tree() or v.mixture == null:
			continue
		var top: Vector3 = v.global_transform * Vector3(0.0, v.get_lip_local_y(), 0.0)
		var dx: float = absf(top.x - global_position.x)
		if dx < v.get_lip_radius_meters() + 0.05 and global_position.y > v.global_position.y - 0.02 and dx < best_d:
			best_d = dx
			target = v


## Short hover text.
func hover_info() -> String:
	return "[b]Magnifying lens[/b]  [color=#B3ADD6]pick it up and hold it over a vessel for a quick reading[/color]"
