class_name ShelfDressing
extends Node3D
## Fills a wall shelf with decorative potion bottles, jars and books.
## Uses the Blender glassware meshes with the real liquid shader (static fill),
## coloured from the substance registry. Arcane substances glow. Deterministic seed.

const PROFILES: Array[String] = [
	"res://world_3d/vessels/profiles/apothecary_bottle.tres",
	"res://world_3d/vessels/profiles/round_flask.tres",
	"res://world_3d/vessels/profiles/erlenmeyer.tres",
	"res://world_3d/vessels/profiles/vial.tres",
	"res://world_3d/vessels/profiles/beaker.tres",
]
const LIQUID_MATERIAL: ShaderMaterial = preload("res://content/materials_3d/liquid_volume.tres")
const GLASS_PC_MATERIAL: Material = preload("res://content/materials_3d/glass_pc.tres")
const GLASS_MOBILE_MATERIAL: Material = preload("res://content/materials_3d/glass_mobile.tres")
const BOOK_COLORS: Array[Color] = [Color(0.35, 0.06, 0.05), Color(0.07, 0.2, 0.1), Color(0.06, 0.1, 0.28), Color(0.3, 0.2, 0.08), Color(0.2, 0.05, 0.22)]
const BOOK_LABELS: Array[Color] = [Color(0.04, 0.035, 0.03), Color(0.3, 0.04, 0.04), Color(0.05, 0.14, 0.08), Color(0.5, 0.4, 0.26)]

@export var plank_heights_meters: PackedFloat32Array = PackedFloat32Array([0.016, 0.436, 0.856])
@export var shelf_width_meters: float = 1.7
@export var shelf_depth_meters: float = 0.24
@export var seed_value: int = 7
@export var extra_palette: Array[Color] = [
	Color(0.85, 0.15, 0.35, 0.8), Color(0.2, 0.9, 0.45, 0.7), Color(0.95, 0.75, 0.1, 0.75),
	Color(0.55, 0.2, 0.95, 0.75), Color(0.1, 0.7, 0.9, 0.6), Color(0.9, 0.4, 0.1, 0.8),
]


func _ready() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var profiles: Array[VesselProfile] = []
	for path: String in PROFILES:
		profiles.append(load(path) as VesselProfile)
	var glass_material: Material = QualityTier.pick_material(GLASS_PC_MATERIAL, GLASS_MOBILE_MATERIAL)
	for plank_y: float in plank_heights_meters:
		var x: float = -shelf_width_meters * 0.5 + 0.04
		while x < shelf_width_meters * 0.5 - 0.05:
			if rng.randf() < 0.18:
				x += _place_books(rng, x, plank_y)
			else:
				x += _place_bottle(rng, profiles, glass_material, x, plank_y)
			x += rng.randf_range(0.005, 0.03)


func _place_bottle(rng: RandomNumberGenerator, profiles: Array[VesselProfile], glass_material: Material, x: float, plank_y: float) -> float:
	var prof: VesselProfile = profiles[rng.randi_range(0, profiles.size() - 1)]
	var scale_f: float = rng.randf_range(0.7, 1.15)
	if prof.vessel_name == "vial" or prof.vessel_name == "beaker":
		scale_f *= 0.8
	var radius: float = prof.outer_radius_meters * scale_f
	var z: float = shelf_depth_meters * 0.5 + rng.randf_range(-0.04, 0.04)
	var holder: Node3D = Node3D.new()
	holder.position = Vector3(x + radius, plank_y + prof.height_meters * scale_f * 0.5 + 0.001, z)
	holder.rotation.y = rng.randf_range(0.0, TAU)
	holder.scale = Vector3.ONE * scale_f
	add_child(holder)

	var glass: MeshInstance3D = MeshInstance3D.new()
	glass.mesh = prof.glass_mesh
	glass.material_override = glass_material
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(glass)

	var liquid: MeshInstance3D = MeshInstance3D.new()
	liquid.mesh = prof.liquid_mesh
	liquid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: ShaderMaterial = LIQUID_MATERIAL.duplicate() as ShaderMaterial
	var color: Color = _random_color(rng)
	var bottom_y: float = prof.inner_profile[0].y
	var top_y: float = prof.inner_profile[prof.inner_profile.size() - 2].y
	var fill_local: float = lerpf(bottom_y, top_y, rng.randf_range(0.3, 0.85))
	var inner_r: float = 0.0
	for p: Vector2 in prof.inner_profile:
		if p.y <= fill_local:
			inner_r = p.x
	holder.force_update_transform()
	mat.set_shader_parameter(&"fill_point_world", holder.global_transform * Vector3(0.0, fill_local, 0.0))
	mat.set_shader_parameter(&"vessel_axis_world", Vector3.UP)
	mat.set_shader_parameter(&"vessel_radius_meters", maxf(inner_r * scale_f, 0.003))
	mat.set_shader_parameter(&"liquid_color", color)
	mat.set_shader_parameter(&"surface_color", color.lerp(Color(1.0, 1.0, 1.0, 0.9), 0.3))
	mat.set_shader_parameter(&"turbidity", rng.randf_range(0.05, 0.6))
	if rng.randf() < 0.35:
		mat.set_shader_parameter(&"emission_hdr", Color(color.r, color.g, color.b) * rng.randf_range(0.8, 2.5))
	if rng.randf() < 0.2:
		mat.set_shader_parameter(&"effervescence", rng.randf_range(0.3, 1.0))
	liquid.material_override = mat
	holder.add_child(liquid)

	if prof.vessel_name != "beaker" and rng.randf() < 0.7:
		var cork_mesh: CylinderMesh = CylinderMesh.new()
		var lip_r: float = prof.inner_profile[prof.inner_profile.size() - 1].x
		cork_mesh.top_radius = lip_r * 1.15
		cork_mesh.bottom_radius = lip_r * 0.95
		cork_mesh.height = 0.018
		var cork_material: StandardMaterial3D = StandardMaterial3D.new()
		cork_material.albedo_color = Color(0.6, 0.43, 0.27)
		cork_material.roughness = 0.9
		cork_mesh.material = cork_material
		var cork: MeshInstance3D = MeshInstance3D.new()
		cork.mesh = cork_mesh
		cork.position.y = prof.height_meters * 0.5 + 0.004
		holder.add_child(cork)
	return radius * 2.0


func _place_books(rng: RandomNumberGenerator, x: float, plank_y: float) -> float:
	var count: int = rng.randi_range(2, 5)
	var used: float = 0.0
	for i: int in count:
		var thickness: float = rng.randf_range(0.025, 0.05)
		var height: float = rng.randf_range(0.17, 0.26)
		var depth: float = rng.randf_range(0.13, 0.18)
		var color: Color = BOOK_COLORS[rng.randi_range(0, BOOK_COLORS.size() - 1)] * rng.randf_range(0.7, 1.2)
		# Binding details come from their own generator, so the shelf layout
		# (drawn from `rng`) stays exactly as it was.
		var detail: RandomNumberGenerator = RandomNumberGenerator.new()
		detail.seed = hash(Vector3(x + used, plank_y, float(seed_value)))
		var label: Color = BOOK_LABELS[detail.randi_range(0, BOOK_LABELS.size() - 1)]
		var book: Node3D = Book3D.make(thickness, height, depth, color, label, detail)
		book.position = Vector3(x + used + thickness * 0.5, plank_y + height * 0.5, shelf_depth_meters * 0.5 - 0.02)
		book.rotation.z = rng.randf_range(-0.04, 0.04) if i < count - 1 else rng.randf_range(-0.25, 0.0)
		add_child(book)
		used += thickness + 0.002
	return used


func _random_color(rng: RandomNumberGenerator) -> Color:
	if rng.randf() < 0.45:
		return extra_palette[rng.randi_range(0, extra_palette.size() - 1)]
	var substance: SubstanceData = SubstanceRegistry.get_substance(rng.randi_range(0, SubstanceRegistry.count() - 1))
	var c: Color = substance.base_albedo_rgba
	c.a = maxf(c.a, 0.45)
	return c
