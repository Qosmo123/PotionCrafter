class_name Vessel3D
extends RigidBody3D
## Glass vessel: owns a MixtureContainer, renders it with the analytical
## liquid shader, sloshes physically, and pours from its lowest rim point.
##
## Shape comes from a VesselProfile (Blender-built glassware). Without one, a
## plain cylinder is generated from the exported dimensions. Either way the
## cavity is a revolved profile, and volume->fill-height uses an exact
## stacked-frustum table.
##
## Slosh: the free surface's slope is the first sloshing mode of a vertical
## cylinder, a damped oscillator with
##   w^2 = g * k * tanh(k * h),  k = 1.8412 / R
## driven toward the quasi-static slope a/g by the liquid's horizontal
## acceleration. Damping comes from the Stokes boundary layer,
## zeta ~ sqrt(nu / (sqrt(g) * R^1.5)), so water rings and honey barely moves.
##
## Per-tick work allocates nothing (RayCast3D nodes, interned StringNames,
## preallocated tables).

const LIQUID_MATERIAL: ShaderMaterial = preload("res://content/materials_3d/liquid_volume.tres")
const LIQUID_MATERIAL_PC: ShaderMaterial = preload("res://content/materials_3d/liquid_volume_pc.tres")
const GLASS_PC_MATERIAL: Material = preload("res://content/materials_3d/glass_pc.tres")
const GLASS_MOBILE_MATERIAL: Material = preload("res://content/materials_3d/glass_mobile.tres")
const POUR_RAY_LENGTH_METERS: float = 2.0
const MIN_LIQUID_M3: float = 1e-9
const SLOSH_MODE_ROOT: float = 1.8412  # first zero of J1', cylinder sloshing mode
const SLOSH_SUBSTEPS: int = 2
const MAX_SURFACE_SLOPE: float = 1.2
const STREAM_REFERENCE_WIDTH_METERS: float = 0.01
const BUBBLE_SHADER: Shader = preload("res://visuals_3d/shaders/bubble_film.gdshader")

## Every live vessel (lets tools and fields find vessels without per-tick allocation).
static var all_vessels: Array[Vessel3D] = []

@export var profile: VesselProfile

@export_group("Cylinder fallback geometry")
@export var inner_radius_meters: float = 0.03
@export var body_height_meters: float = 0.14
@export var wall_thickness_meters: float = 0.003
@export var glass_mass_kg: float = 0.12

@export_group("Contents")
@export var open_top: bool = true
## SubstanceData resources (typed as Resource for clean .tscn serialisation).
@export var initial_substances: Array[Resource] = []
@export var initial_moles: Array[float] = []
@export var initial_temp_kelvin: float = 293.15

@export_group("Thermal")
@export var ambient_conductance_w_k: float = 0.6

@export_group("Pouring")
@export var pour_discharge_coefficient: float = 0.62
@export_range(0.05, 1.0) var lip_width_fraction: float = 0.5

var mixture: MixtureContainer
## Heat from external sources (burners, hot plates) accumulated this tick, in watts.
var external_heat_watts: float = 0.0
var is_pouring: bool = false
var is_boiling: bool = false
var pour_rate_m3_s: float = 0.0
var spilled_mass_kg: float = 0.0
var vented_mass_kg: float = 0.0
var capacity_m3: float = 0.0
## 0..1 surface agitation (slosh energy, stream impacts); drives ripples.
var agitation: float = 0.0
## Current free-surface slope (tan of tilt) from the slosh oscillator.
var surface_slope: Vector2 = Vector2.ZERO
## Foam head above the liquid (surfactants + agitation + reaction gas), metres.
var foam_height_meters: float = 0.0
## Per-tick multipliers written by spell fields (reset after each tick).
var field_insulation: float = 1.0
var field_catalysis: float = 1.0
## Set by flames, hot plates, sigils and burning neighbours this tick.
var ignition_source: bool = false
## 0 = separated layers, 1 = fully emulsified (milky). Rises with shaking,
## held by surfactants, decays as droplets coalesce.
var emulsion_level: float = 0.0
## Fresh precipitate still suspended (cloudy) before it settles as sediment.
var suspension_level: float = 0.0
var foam_overflow_rate_m_s: float = 0.0
## Corked and labelled (bottled). Sealed vessels neither pour nor vent.
var sealed: bool = false

const HISTORY_SAMPLES: int = 64
const HISTORY_INTERVAL_S: float = 0.5
var _history_kelvin: PackedFloat32Array = PackedFloat32Array()
var _history_index: int = 0
var _history_count: int = 0
var _history_timer: float = 0.0
var _cork: MeshInstance3D
var _label: Label3D
var _label_card: MeshInstance3D
## Hand-written contents tag on any vessel holding something (the full name +
## grade label replaces it when the vessel is corked).
@export var show_contents_tag: bool = true
var _tag_timer: float = 0.0
static var _parchment_tex: ImageTexture = null

var _profile_r: PackedFloat64Array = PackedFloat64Array()
var _profile_y: PackedFloat64Array = PackedFloat64Array()
var _profile_cum_m3: PackedFloat64Array = PackedFloat64Array()
var _cavity_top_index: int = 0
var _lip_radius_meters: float = 0.03
var _lip_local_y: float = 0.07
var _glass_mass_kg: float = 0.12

var _liquid_material: ShaderMaterial
var _liquid_mesh: MeshInstance3D
var _pour_ray: RayCast3D
var _stream: GPUParticles3D
var _stream_process: ParticleProcessMaterial
var _splash: GPUParticles3D
var _splash_process: ParticleProcessMaterial
var _gravity_m_s2: float = SimConstants.GRAVITY_M_S2
var _slope_velocity: Vector2 = Vector2.ZERO
var _prev_surface_velocity: Vector3 = Vector3.ZERO
var _fill_local_y: float = 0.0
var _surface_radius_meters: float = 0.03
var _bubbles: GPUParticles3D
var _bubble_process: ParticleProcessMaterial
var _flash_light: OmniLight3D
var _effects: VesselEffects


func _ready() -> void:
	collision_layer = SimConstants.LAYER_RIGID_VESSEL
	# Tools pass through glass (stirring rods must reach inside); everything else collides.
	collision_mask = (SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_RIGID_VESSEL
		| SimConstants.LAYER_SOLID_REAGENT)
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_gravity_m_s2 = ProjectSettings.get_setting("physics/3d/default_gravity", SimConstants.GRAVITY_M_S2)
	if profile != null and profile.inner_profile.size() >= 3:
		_build_from_profile()
	else:
		_build_cylinder()
	_build_volume_table()
	_build_pour_rig()
	var foot_r: float = profile.outer_radius_meters if profile != null else inner_radius_meters + wall_thickness_meters
	ContactShadow3D.attach(self, foot_r, _profile_y[0] if _profile_y.size() > 0 else 0.0)

	mixture = MixtureContainer.new()
	for i: int in mini(initial_substances.size(), initial_moles.size()):
		var substance: SubstanceData = initial_substances[i] as SubstanceData
		var index: int = SubstanceRegistry.index_of(substance)
		if index < 0:
			push_warning("%s: substance %d is not in content/substances/" % [name, i])
			continue
		mixture.add_substance(index, initial_moles[i], initial_temp_kelvin)
	add_to_group(&"vessels")
	all_vessels.append(self)
	_update_fill_state()
	_update_mass_properties()
	_update_liquid_visual()


func _physics_process(delta: float) -> void:
	if external_heat_watts != 0.0:
		mixture.add_heat(external_heat_watts * delta)
		external_heat_watts = 0.0
	mixture.shear_rate = agitation * 2.0 + absf(mixture.swirl_rad_s) * 0.1
	mixture.step_reactions(delta, (agitation + absf(mixture.swirl_rad_s) * 0.05) * field_catalysis, open_top, ignition_source)
	ignition_source = false
	if mixture.burning:
		_spread_fire()
	mixture.step_thermal(delta, SimConstants.AMBIENT_TEMP_KELVIN, ambient_conductance_w_k * field_insulation)
	field_insulation = 1.0
	field_catalysis = 1.0
	is_boiling = false
	if open_top:
		var vented_kg: float = mixture.vent_gas(1.0)
		vented_mass_kg += vented_kg
		is_boiling = vented_kg > 0.0
	_spill_overflow()
	_update_fill_state()
	_update_slosh(delta)
	_update_foam_and_bubbles(delta)
	_update_pouring(delta)
	_update_mass_properties()
	_update_layers_state(delta)
	_effects.update_effects(self, global_transform * Vector3(0.0, _lip_local_y, 0.0), get_surface_point_world(),
		_surface_radius_meters, foam_overflow_rate_m_s)


## Visual-only work (layer bands, shader params) runs at render rate, keeping
## the physics tick allocation-free.
func _process(delta: float) -> void:
	if mixture == null:
		return
	_update_liquid_visual()
	_tag_timer -= delta
	if _tag_timer <= 0.0:
		_tag_timer = 0.6
		_update_contents_tag()
	_history_timer -= delta
	if _history_timer <= 0.0:
		_history_timer = HISTORY_INTERVAL_S
		if _history_kelvin.size() != HISTORY_SAMPLES:
			_history_kelvin.resize(HISTORY_SAMPLES)
		_history_kelvin[_history_index] = mixture.temperature_kelvin
		_history_index = (_history_index + 1) % HISTORY_SAMPLES
		_history_count = mini(_history_count + 1, HISTORY_SAMPLES)


## Temperature samples (°C), oldest first, one every HISTORY_INTERVAL_S.
func get_temperature_history_celsius() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var start: int = (_history_index - _history_count + HISTORY_SAMPLES) % HISTORY_SAMPLES
	for i: int in _history_count:
		out.append(_history_kelvin[(start + i) % HISTORY_SAMPLES] - 273.15)
	return out


## Contents tag: the main ingredient's name (or the potion's name for a real
## mixture), refreshed a couple of times a second while the vessel is open.
func _update_contents_tag() -> void:
	if sealed:
		return
	var has: bool = show_contents_tag and mixture.get_liquid_volume_m3() + mixture.get_solid_volume_m3() > 2e-6
	if profile != null and profile.vessel_name.contains("tray"):
		has = false
	if not has:
		if _label_card != null:
			_label_card.visible = false
			_label.visible = false
		return
	if _cork == null:
		_build_cork_and_label()
		_cork.visible = false
	var text: String = contents_tag_text(mixture, foam_height_meters)
	if _label.text != text:
		_label.text = text
	_label_card.visible = true
	_label.visible = true


## Short tag text: the dominant species when it makes up most of the mass,
## otherwise the potion's name (without the grade).
static func contents_tag_text(m: MixtureContainer, foam_m: float) -> String:
	var total: float = maxf(m.get_total_mass_kg(), 1e-12)
	var water: int = SubstanceRegistry.index_of_id(&"water")
	var best: int = -1
	var best_mass: float = 0.0
	var water_mass: float = 0.0
	for k: int in m.active_count():
		var i: int = m.active_index(k)
		var mass: float = m.moles[i] * SubstanceRegistry.get_substance(i).molar_mass_kg_mol
		if i == water:
			water_mass = mass
		elif mass > best_mass:
			best_mass = mass
			best = i
	if best < 0 or best_mass / total < 0.02:
		return SubstanceRegistry.get_substance(water).display_name if water >= 0 and water_mass > 0.0 else "Empty"
	# Water is the solvent: name what's dissolved in it (diluted if mostly water).
	if best_mass / maxf(total - water_mass, 1e-12) > 0.7:
		var label: String = SubstanceRegistry.get_substance(best).display_name
		return label + (" (diluted)" if water_mass / total > 0.6 and not label.to_lower().contains("water") else "")
	return PotionNamer.name_for(m, foam_m).get_slice(" [", 0)


## Aged parchment: warm fibres, a few blotches and darker, singed edges.
static func parchment_texture() -> ImageTexture:
	if _parchment_tex != null:
		return _parchment_tex
	var w: int = 128
	var h: int = 64
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.06
	for y: int in h:
		for x: int in w:
			var u: float = float(x) / float(w - 1)
			var v: float = float(y) / float(h - 1)
			var fibre: float = noise.get_noise_2d(float(x) * 0.6, float(y) * 3.0) * 0.06
			var blotch: float = maxf(noise.get_noise_2d(float(x) + 300.0, float(y) + 120.0), 0.0) * 0.12
			var edge: float = minf(minf(u, 1.0 - u) * 2.0, minf(v, 1.0 - v) * 4.0)
			var singe: float = 1.0 - smoothstep(0.0, 0.18, edge + noise.get_noise_2d(float(x) * 2.0, float(y) * 2.0) * 0.05)
			var c: Color = Color(0.93, 0.85, 0.66) * (1.0 + fibre - blotch)
			c = c.lerp(Color(0.55, 0.36, 0.18), singe * 0.7)
			c.a = 1.0
			img.set_pixel(x, y, c)
	_parchment_tex = ImageTexture.create_from_image(img)
	return _parchment_tex


## Cork the vessel and stick a parchment label on it (name + grade). Returns
## true if it is now sealed. Calling again uncorks it.
func toggle_seal() -> bool:
	if sealed:
		sealed = false
		open_top = true
		_cork.visible = false
		_label.visible = false
		_label_card.visible = false
		return false
	if mixture == null or mixture.get_liquid_volume_m3() < 1e-7:
		return false
	sealed = true
	_tag_timer = 0.0
	open_top = false
	if _cork == null:
		_build_cork_and_label()
	_cork.visible = true
	_label.visible = true
	_label_card.visible = true
	_label.text = "%s\n%s" % [PotionNamer.name_for(mixture, foam_height_meters), PotionNamer.formula_for(mixture, 2)]
	return true


func _build_cork_and_label() -> void:
	var cork_mesh: CylinderMesh = CylinderMesh.new()
	cork_mesh.top_radius = _lip_radius_meters * 1.18
	cork_mesh.bottom_radius = _lip_radius_meters * 0.92
	cork_mesh.height = 0.02
	cork_mesh.radial_segments = 20
	var cork_mat: StandardMaterial3D = StandardMaterial3D.new()
	cork_mat.albedo_color = Color(0.6, 0.43, 0.26)
	cork_mat.roughness = 0.95
	cork_mesh.material = cork_mat
	_cork = MeshInstance3D.new()
	_cork.mesh = cork_mesh
	_cork.position.y = _lip_local_y + 0.006
	add_child(_cork)
	var outer_r: float = profile.outer_radius_meters if profile != null else inner_radius_meters + wall_thickness_meters
	# Low on the body (the widest part of round flasks), not up on the neck.
	var mid_y: float = lerpf(_profile_y[0], _lip_local_y, 0.36)
	var card_mesh: QuadMesh = QuadMesh.new()
	# Card sized to the vessel: a slim tag on a vial, a broad label on a flask.
	card_mesh.size = Vector2(minf(outer_r * 1.5, 0.07), clampf(outer_r * 0.95, 0.014, 0.034))
	var card_mat: StandardMaterial3D = StandardMaterial3D.new()
	card_mat.albedo_color = Color(1.0, 0.96, 0.86)
	card_mat.albedo_texture = parchment_texture()
	card_mat.roughness = 0.9
	card_mesh.material = card_mat
	_label_card = MeshInstance3D.new()
	_label_card.mesh = card_mesh
	_label_card.position = Vector3(0.0, mid_y, outer_r + 0.0015)
	add_child(_label_card)
	_label = Label3D.new()
	_label.font_size = 44
	_label.font = CosmicTheme.display_font()
	_label.outline_size = 0
	_label.pixel_size = 0.00011 * clampf(card_mesh.size.x / 0.05, 0.4, 1.0)
	_label.modulate = Color(0.16, 0.08, 0.03)
	_label.width = card_mesh.size.x / _label.pixel_size * 0.92
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector3(0.0, mid_y, outer_r + 0.0022)
	_label.double_sided = false
	add_child(_label)


func _exit_tree() -> void:
	all_vessels.erase(self)


# --- Public API -------------------------------------------------------------------

## Local-space surface height and radius (for tools probing the liquid).
func get_fill_local_y() -> float:
	return _fill_local_y


func get_surface_radius_meters() -> float:
	return _surface_radius_meters


func get_cavity_bottom_local_y() -> float:
	return _profile_y[0]


func get_lip_local_y() -> float:
	return _lip_local_y


func get_lip_radius_meters() -> float:
	return _lip_radius_meters


func get_fill_fraction() -> float:
	if capacity_m3 <= 0.0:
		return 0.0
	return clampf(_condensed_volume_m3() / capacity_m3, 0.0, 1.0)


## World point on the vessel axis at the current liquid surface height.
func get_surface_point_world() -> Vector3:
	return global_transform * Vector3(0.0, _fill_local_y, 0.0)


## Disturb the surface (stream impacts, knocks, stirring). 1.0 = violent.
func add_agitation(amount: float) -> void:
	agitation = clampf(agitation + amount, 0.0, 1.0)


# --- Build ------------------------------------------------------------------------

func _build_from_profile() -> void:
	_glass_mass_kg = profile.glass_mass_kg
	var points: PackedVector2Array = profile.inner_profile
	_profile_r.resize(points.size())
	_profile_y.resize(points.size())
	for i: int in points.size():
		_profile_r[i] = points[i].x
		_profile_y[i] = points[i].y
	# The last point is the lip flare; the cavity ends one point below it.
	_cavity_top_index = points.size() - 2
	_lip_radius_meters = points[points.size() - 1].x
	_lip_local_y = points[points.size() - 1].y

	_add_glass_visual(profile.glass_mesh)
	_add_liquid_visual(profile.liquid_mesh, Vector3.ZERO)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = profile.glass_mesh.create_convex_shape(true, false)
	add_child(collision)


func _build_cylinder() -> void:
	_glass_mass_kg = glass_mass_kg
	var outer_radius: float = inner_radius_meters + wall_thickness_meters
	var bottom_y: float = -0.5 * body_height_meters + wall_thickness_meters
	var top_y: float = 0.5 * body_height_meters
	_profile_r = PackedFloat64Array([0.0, inner_radius_meters, inner_radius_meters, inner_radius_meters])
	_profile_y = PackedFloat64Array([bottom_y, bottom_y, top_y, top_y])
	_cavity_top_index = 2
	_lip_radius_meters = inner_radius_meters
	_lip_local_y = top_y

	var glass_mesh: CylinderMesh = CylinderMesh.new()
	glass_mesh.top_radius = outer_radius
	glass_mesh.bottom_radius = outer_radius
	glass_mesh.height = body_height_meters
	glass_mesh.cap_top = not open_top
	glass_mesh.radial_segments = 48
	_add_glass_visual(glass_mesh)

	var liquid_mesh: CylinderMesh = CylinderMesh.new()
	liquid_mesh.top_radius = inner_radius_meters * 0.985
	liquid_mesh.bottom_radius = inner_radius_meters * 0.985
	liquid_mesh.height = top_y - bottom_y
	liquid_mesh.radial_segments = 40
	liquid_mesh.rings = 4
	_add_liquid_visual(liquid_mesh, Vector3(0.0, 0.5 * (top_y + bottom_y), 0.0))

	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = outer_radius
	shape.height = body_height_meters
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)


func _add_glass_visual(mesh: Mesh) -> void:
	var glass: MeshInstance3D = MeshInstance3D.new()
	glass.name = &"Glass"
	glass.mesh = mesh
	glass.material_override = QualityTier.pick_material(GLASS_PC_MATERIAL, GLASS_MOBILE_MATERIAL)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)


func _add_liquid_visual(mesh: Mesh, offset: Vector3) -> void:
	_liquid_mesh = MeshInstance3D.new()
	_liquid_mesh.name = &"Liquid"
	_liquid_mesh.mesh = mesh
	_liquid_mesh.position = offset
	_liquid_material = (QualityTier.pick_material(LIQUID_MATERIAL_PC, LIQUID_MATERIAL) as ShaderMaterial).duplicate() as ShaderMaterial
	_liquid_mesh.material_override = _liquid_material
	_liquid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_liquid_mesh)


## Cumulative cavity volume at each profile point (stacked conical frustums).
func _build_volume_table() -> void:
	_profile_cum_m3.resize(_profile_r.size())
	_profile_cum_m3[0] = 0.0
	for i: int in range(1, _profile_r.size()):
		var h: float = maxf(_profile_y[i] - _profile_y[i - 1], 0.0)
		var r0: float = _profile_r[i - 1]
		var r1: float = _profile_r[i]
		_profile_cum_m3[i] = _profile_cum_m3[i - 1] + PI * h * (r0 * r0 + r0 * r1 + r1 * r1) / 3.0
	capacity_m3 = _profile_cum_m3[_cavity_top_index]


func _build_pour_rig() -> void:
	_pour_ray = RayCast3D.new()
	_pour_ray.enabled = false
	_pour_ray.top_level = true
	_pour_ray.collision_mask = SimConstants.LAYER_RIGID_VESSEL | SimConstants.LAYER_STATIC_BENCH
	_pour_ray.add_exception(self)
	add_child(_pour_ray)

	# Continuous ribbon stream: particle trails form a cohesive rope.
	_stream_process = ParticleProcessMaterial.new()
	_stream_process.direction = Vector3.DOWN
	_stream_process.spread = 1.5
	_stream_process.gravity = Vector3(0.0, -_gravity_m_s2, 0.0)
	_stream_process.damping_min = 0.0
	_stream_process.damping_max = 0.2
	var ribbon_material: StandardMaterial3D = StandardMaterial3D.new()
	ribbon_material.use_particle_trails = true
	ribbon_material.vertex_color_use_as_albedo = true
	ribbon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ribbon_material.roughness = 0.04
	ribbon_material.metallic_specular = 0.7
	ribbon_material.rim_enabled = true
	ribbon_material.rim = 0.6
	var ribbon: RibbonTrailMesh = RibbonTrailMesh.new()
	ribbon.shape = RibbonTrailMesh.SHAPE_CROSS
	ribbon.size = STREAM_REFERENCE_WIDTH_METERS
	ribbon.sections = 6
	ribbon.section_segments = 2
	ribbon.material = ribbon_material
	_stream = GPUParticles3D.new()
	_stream.top_level = true
	_stream.emitting = false
	_stream.amount = 64
	_stream.lifetime = 0.7
	_stream.local_coords = false
	_stream.trail_enabled = true
	_stream.trail_lifetime = 0.2
	_stream.process_material = _stream_process
	_stream.draw_pass_1 = ribbon
	_stream.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stream)

	# Splash crown where the stream lands.
	_splash_process = ParticleProcessMaterial.new()
	_splash_process.direction = Vector3.UP
	_splash_process.spread = 65.0
	_splash_process.gravity = Vector3(0.0, -_gravity_m_s2, 0.0)
	_splash_process.initial_velocity_min = 0.2
	_splash_process.initial_velocity_max = 0.6
	_splash_process.scale_min = 0.4
	_splash_process.scale_max = 1.0
	var droplet_material: StandardMaterial3D = StandardMaterial3D.new()
	droplet_material.vertex_color_use_as_albedo = true
	droplet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	droplet_material.roughness = 0.03
	var droplet: SphereMesh = SphereMesh.new()
	droplet.radius = 0.0018
	droplet.height = 0.0036
	droplet.radial_segments = 8
	droplet.rings = 4
	droplet.material = droplet_material
	# Floating soap bubbles (bubble potions) rising from the surface.
	_bubble_process = ParticleProcessMaterial.new()
	_bubble_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_bubble_process.emission_sphere_radius = 0.01
	_bubble_process.direction = Vector3.UP
	_bubble_process.spread = 35.0
	_bubble_process.initial_velocity_min = 0.03
	_bubble_process.initial_velocity_max = 0.09
	_bubble_process.gravity = Vector3(0.0, 0.04, 0.0)
	_bubble_process.damping_min = 0.02
	_bubble_process.damping_max = 0.06
	_bubble_process.scale_min = 0.35
	_bubble_process.scale_max = 1.6
	_bubble_process.turbulence_enabled = true
	_bubble_process.turbulence_noise_strength = 0.4
	_bubble_process.turbulence_noise_scale = 3.0
	_bubble_process.turbulence_influence_min = 0.02
	_bubble_process.turbulence_influence_max = 0.06
	var film: ShaderMaterial = ShaderMaterial.new()
	film.shader = BUBBLE_SHADER
	var bubble_mesh: SphereMesh = SphereMesh.new()
	bubble_mesh.radius = 0.011
	bubble_mesh.height = 0.022
	bubble_mesh.radial_segments = 16
	bubble_mesh.rings = 8
	bubble_mesh.material = film
	_bubbles = GPUParticles3D.new()
	_bubbles.top_level = true
	_bubbles.emitting = false
	_bubbles.amount = 40
	_bubbles.lifetime = 6.0
	_bubbles.local_coords = false
	_bubbles.process_material = _bubble_process
	_bubbles.draw_pass_1 = bubble_mesh
	_bubbles.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 3.0, 3.0))
	_bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bubbles)

	_effects = VesselEffects.new()
	add_child(_effects)
	#_splash_process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	#_stream_process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT

	_flash_light = OmniLight3D.new()
	_flash_light.visible = false
	_flash_light.omni_range = 0.8
	_flash_light.shadow_enabled = false
	add_child(_flash_light)

	_splash = GPUParticles3D.new()
	_splash.top_level = true
	_splash.emitting = false
	_splash.amount = 48
	_splash.lifetime = 0.35
	_splash.local_coords = false
	_splash.process_material = _splash_process
	_splash.draw_pass_1 = droplet
	_splash.visibility_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)


# --- Per-tick ---------------------------------------------------------------------

func _condensed_volume_m3() -> float:
	return mixture.get_liquid_volume_m3() + mixture.get_solid_volume_m3()


func _spill_overflow() -> void:
	var excess_m3: float = _condensed_volume_m3() - capacity_m3
	if excess_m3 > 0.0:
		spilled_mass_kg += mixture.transfer_liquid_volume_to(null, excess_m3)


## Invert the frustum volume table: local surface height + radius for the current volume.
func _update_fill_state() -> void:
	var fill: Vector2 = _height_for_volume(_condensed_volume_m3())
	_fill_local_y = fill.x
	_surface_radius_meters = maxf(fill.y, 0.002)


## Local surface height and radius for a given cavity volume (frustum table inverse).
func _height_for_volume(volume: float) -> Vector2:
	var volume_m3: float = clampf(volume, 0.0, capacity_m3)
	var seg: int = 1
	while seg < _cavity_top_index and _profile_cum_m3[seg] < volume_m3:
		seg += 1
	var y0: float = _profile_y[seg - 1]
	var y1: float = _profile_y[seg]
	var r0: float = _profile_r[seg - 1]
	var r1: float = _profile_r[seg]
	var target: float = volume_m3 - _profile_cum_m3[seg - 1]
	var lo: float = 0.0
	var hi: float = 1.0
	for _i: int in 24:
		var t: float = 0.5 * (lo + hi)
		var rt: float = lerpf(r0, r1, t)
		var v: float = PI * (y1 - y0) * t * (r0 * r0 + r0 * rt + rt * rt) / 3.0
		if v < target:
			lo = t
		else:
			hi = t
	var t_fill: float = 0.5 * (lo + hi)
	return Vector2(lerpf(y0, y1, t_fill), lerpf(r0, r1, t_fill))


func _update_slosh(delta: float) -> void:
	var surface_world: Vector3 = get_surface_point_world()
	var point_velocity: Vector3 = linear_velocity + angular_velocity.cross(surface_world - global_position)
	var accel: Vector3 = (point_velocity - _prev_surface_velocity) / maxf(delta, 1e-4)
	_prev_surface_velocity = point_velocity
	var target_slope: Vector2 = Vector2(accel.x, accel.z) / _gravity_m_s2

	var radius: float = _surface_radius_meters
	var depth_m: float = maxf(_fill_local_y - _profile_y[0], 1e-4)
	var k: float = SLOSH_MODE_ROOT / radius
	var omega: float = sqrt(_gravity_m_s2 * k * tanh(k * depth_m))
	var nu_m2_s: float = mixture.get_liquid_viscosity_pas() / maxf(mixture.get_liquid_density_kg_m3(), 1.0)
	var zeta: float = clampf(0.008 + 1.5 * sqrt(nu_m2_s / (sqrt(_gravity_m_s2) * pow(radius, 1.5))), 0.008, 1.5)

	var h: float = delta / float(SLOSH_SUBSTEPS)
	for _i: int in SLOSH_SUBSTEPS:
		var slope_accel: Vector2 = omega * omega * (target_slope - surface_slope) - 2.0 * zeta * omega * _slope_velocity
		_slope_velocity += slope_accel * h
		surface_slope += _slope_velocity * h
	surface_slope = surface_slope.limit_length(MAX_SURFACE_SLOPE)

	var disturbance: float = _slope_velocity.length() * radius * 4.0 + (surface_slope - target_slope).length() * 0.6
	agitation = clampf(maxf(agitation * exp(-delta * (1.5 + zeta * 6.0)), disturbance), 0.0, 1.0)


func _update_pouring(delta: float) -> void:
	is_pouring = false
	pour_rate_m3_s = 0.0
	var liquid_m3: float = mixture.get_liquid_volume_m3()
	if not open_top or liquid_m3 <= MIN_LIQUID_M3:
		_stop_stream()
		return

	var xf: Transform3D = global_transform
	var axis: Vector3 = xf.basis.y.normalized()
	var top_center: Vector3 = xf * Vector3(0.0, _lip_local_y, 0.0)
	var down_in_rim: Vector3 = Vector3.DOWN - axis * Vector3.DOWN.dot(axis)
	var pour_dir: Vector3 = Vector3.DOWN
	var lip: Vector3 = top_center
	if down_in_rim.length_squared() > 1e-6:
		pour_dir = down_in_rim.normalized()
		lip += pour_dir * _lip_radius_meters

	# Surface height at the lip includes the slosh tilt (surges spill sooner).
	var surface_world: Vector3 = get_surface_point_world()
	var slope_rise: float = -(surface_slope.x * (lip.x - surface_world.x) + surface_slope.y * (lip.z - surface_world.z))
	var head_m: float = surface_world.y + slope_rise - lip.y
	if head_m <= 0.0:
		_stop_stream()
		return

	# Weir discharge throttled by viscosity: thin liquids gush, syrups ooze.
	var viscosity_pas: float = mixture.get_liquid_viscosity_pas()
	var lip_width_m: float = 2.0 * _lip_radius_meters * lip_width_fraction
	var flow_m3_s: float = (pour_discharge_coefficient * lip_width_m * sqrt(2.0 * _gravity_m_s2)
		* pow(head_m, 1.5) / (1.0 + viscosity_pas * 40.0))
	var volume_m3: float = minf(flow_m3_s * delta, liquid_m3)

	var spout: Vector3 = lip + pour_dir * 0.003
	_pour_ray.global_transform = Transform3D(Basis.IDENTITY, spout)
	_pour_ray.target_position = Vector3(0.0, -POUR_RAY_LENGTH_METERS, 0.0)
	_pour_ray.force_raycast_update()
	var receiver: Vessel3D = _pour_ray.get_collider() as Vessel3D
	var dst: MixtureContainer = null
	if receiver != null and receiver.open_top and _pour_ray.get_collision_normal().y > 0.5:
		dst = receiver.mixture
	var moved_kg: float = mixture.transfer_liquid_volume_to(dst, volume_m3)
	if dst == null:
		spilled_mass_kg += moved_kg

	is_pouring = true
	pour_rate_m3_s = volume_m3 / maxf(delta, 1e-6)
	var exit_speed: float = sqrt(2.0 * _gravity_m_s2 * head_m)
	var stream_color: Color = mixture.get_contents_color()
	stream_color.a = clampf(stream_color.a + 0.4, 0.0, 1.0)

	# Stream width from continuity (Q = A v); viscous streams stay thick and slow.
	var stream_speed: float = maxf(exit_speed / (1.0 + viscosity_pas * 4.0), 0.05)
	var width_m: float = clampf(2.0 * sqrt(flow_m3_s / (PI * stream_speed)), 0.0015, 0.02)
	_stream.global_transform = Transform3D(Basis.IDENTITY, spout)
	_stream_process.direction = (pour_dir * 0.8 + Vector3.DOWN * 0.2).normalized()
	_stream_process.initial_velocity_min = stream_speed * 0.95
	_stream_process.initial_velocity_max = stream_speed * 1.05
	_stream_process.scale_min = width_m / STREAM_REFERENCE_WIDTH_METERS
	_stream_process.scale_max = _stream_process.scale_min
	_stream_process.color = stream_color
	_stream.trail_lifetime = clampf(0.12 + viscosity_pas * 0.05, 0.12, 0.5)
	_stream.emitting = true

	if _pour_ray.is_colliding():
		var impact_speed: float = sqrt(stream_speed * stream_speed + 2.0 * _gravity_m_s2 * maxf(spout.y - _pour_ray.get_collision_point().y, 0.0))
		var splashiness: float = clampf(flow_m3_s / 3e-5, 0.0, 1.0) / (1.0 + viscosity_pas * 60.0)
		_splash.global_transform = Transform3D(Basis.IDENTITY, _pour_ray.get_collision_point() + Vector3.UP * 0.002)
		_splash_process.initial_velocity_min = impact_speed * 0.15
		_splash_process.initial_velocity_max = impact_speed * 0.4
		_splash_process.color = stream_color
		_splash.amount_ratio = clampf(splashiness, 0.05, 1.0)
		_splash.emitting = splashiness > 0.02
		if receiver != null:
			receiver.add_agitation(splashiness * impact_speed * delta * 3.0)
	else:
		_splash.emitting = false


## Foam grows from surfactant x agitation and from reaction gas (fizz head),
## drains at a rate set by the film stabiliser. Stable, surfactant-rich foam
## sheds free-floating bubbles; buoyant (low gravity-coupling) liquids make them rise.
func _update_foam_and_bubbles(delta: float) -> void:
	var foaming: float = mixture.get_foaming()
	var stability: float = mixture.get_foam_stability()
	var gas_rate: float = mixture.gas_generation_mol_s
	var area_m2: float = PI * _surface_radius_meters * _surface_radius_meters
	var gas_m3_s: float = gas_rate * SimConstants.GAS_CONSTANT_J_MOL_K * mixture.temperature_kelvin / (SimConstants.AMBIENT_PRESSURE_KPA * 1000.0)
	var growth_m_s: float = foaming * agitation * 0.02 + gas_m3_s * (0.04 + foaming) / maxf(area_m2, 1e-5)
	var drain_per_s: float = 0.8 / (0.15 + stability * 4.0 + foaming * 0.5)
	var headroom: float = maxf(_lip_local_y - _fill_local_y, 0.0) + 0.01
	var grown: float = (foam_height_meters + growth_m_s * delta) * exp(-drain_per_s * delta)
	foam_overflow_rate_m_s = maxf(grown - headroom, 0.0) / maxf(delta, 1e-6)
	foam_height_meters = clampf(grown, 0.0, headroom)

	var bubble_drive: float = foaming * (0.25 + stability) * clampf(agitation * 3.0 + foam_height_meters * 60.0, 0.0, 1.0)
	if bubble_drive > 0.08 and open_top and get_fill_fraction() > 0.01:
		var coupling: float = mixture.get_gravity_coupling()
		_bubbles.global_transform = Transform3D(Basis.IDENTITY, global_transform * Vector3(0.0, minf(_fill_local_y + foam_height_meters, _lip_local_y) + 0.012, 0.0))
		_bubble_process.emission_sphere_radius = minf(_surface_radius_meters, _lip_radius_meters) * 0.7
		_bubble_process.gravity = Vector3(0.0, 0.03 + clampf(1.0 - coupling, 0.0, 2.0) * 0.25, 0.0)
		_bubbles.amount_ratio = clampf(bubble_drive, 0.1, 1.0)
		_bubbles.emitting = true
	else:
		_bubbles.emitting = false

	var flash: float = mixture.arcane_flash
	_flash_light.visible = flash > 0.02
	if _flash_light.visible:
		var aura: Color = mixture.get_emission_hdr()
		_flash_light.light_color = Color(aura.r + 0.3, aura.g + 0.3, aura.b + 0.3).clamp()
		_flash_light.light_energy = flash * 2.5
		_flash_light.position = Vector3(0.0, _fill_local_y, 0.0)


func _stop_stream() -> void:
	_stream.emitting = false
	_splash.emitting = false


## Contents add mass, and their arcane gravity coupling changes the net weight.
func _update_mass_properties() -> void:
	var contents_kg: float = mixture.get_total_mass_kg()
	var total_kg: float = _glass_mass_kg + contents_kg
	mass = maxf(total_kg, 0.001)
	gravity_scale = (_glass_mass_kg + contents_kg * mixture.get_gravity_coupling()) / maxf(total_kg, 0.001)


func _update_liquid_visual() -> void:
	var fill: float = get_fill_fraction()
	_liquid_mesh.visible = fill > 0.0005
	if not _liquid_mesh.visible:
		return
	var color: Color = _apply_layers()
	var surface: Color = color.lerp(Color(1.0, 1.0, 1.0, 0.9), 0.35)
	var normal: Vector3 = Vector3(surface_slope.x, 1.0, surface_slope.y).normalized()
	var gas_ratio: float = clampf(mixture.get_gas_moles() / maxf(mixture.get_total_moles(), 1e-9) * 20.0, 0.0, 1.0)
	_liquid_material.set_shader_parameter(&"fill_point_world", get_surface_point_world())
	_liquid_material.set_shader_parameter(&"surface_normal_world", normal)
	_liquid_material.set_shader_parameter(&"vessel_axis_world", global_basis.y.normalized())
	_liquid_material.set_shader_parameter(&"vessel_radius_meters", _surface_radius_meters)
	_liquid_material.set_shader_parameter(&"fill_fraction", fill)
	_liquid_material.set_shader_parameter(&"liquid_color", color)
	_liquid_material.set_shader_parameter(&"surface_color", surface)
	_liquid_material.set_shader_parameter(&"emission_hdr", mixture.get_emission_hdr() * (1.0 + mixture.arcane_flash * 3.0))
	_liquid_material.set_shader_parameter(&"foam_thickness_meters", foam_height_meters)
	_liquid_material.set_shader_parameter(&"glitter", mixture.get_glitter())
	_liquid_material.set_shader_parameter(&"rainbow", mixture.get_rainbow())
	var glow_hot: Color = mixture.get_incandescence()
	_liquid_material.set_shader_parameter(&"incandescence", Vector3(glow_hot.r, glow_hot.g, glow_hot.b))
	_liquid_material.set_shader_parameter(&"turbidity", clampf(mixture.get_liquid_turbidity() + emulsion_level * 0.6 + suspension_level * 0.8, 0.0, 1.0))
	_liquid_material.set_shader_parameter(&"swirl_rad_s", mixture.swirl_rad_s)
	_liquid_material.set_shader_parameter(&"agitation", agitation)
	var fizz: float = clampf(mixture.gas_generation_mol_s * 40.0, 0.0, 1.0)
	_liquid_material.set_shader_parameter(&"effervescence", maxf(maxf(gas_ratio, fizz), 1.0 if is_boiling else 0.0))


## Emulsion and suspension dynamics.
func _update_layers_state(delta: float) -> void:
	var groups: int = 0
	for g: int in 3:
		if mixture.get_group_volume_m3(g) > 1e-7:
			groups += 1
	var viscosity: float = mixture.get_liquid_viscosity_pas()
	var surfactant: float = mixture.get_foaming()
	if groups > 1:
		emulsion_level = clampf(emulsion_level + maxf(agitation - 0.25, 0.0) * delta * 3.0, 0.0, 1.0)
		var coalesce_per_s: float = 0.5 * (1.0 - clampf(surfactant * 1.6, 0.0, 0.98)) / (1.0 + viscosity * 5.0)
		emulsion_level *= exp(-coalesce_per_s * delta)
	else:
		emulsion_level = 0.0
	suspension_level = clampf(suspension_level + mixture.precipitation_rate_mol_s * delta * 6.0, 0.0, 1.0)
	suspension_level *= exp(-delta * 0.35 / (1.0 + viscosity * 3.0) * (1.0 - clampf(agitation, 0.0, 0.9)))


## Configure up to three stratified bands (sediment + density-ordered liquid
## groups) in the shader; returns the top band colour. Emulsions render as one
## milky band; suspended precipitate clouds every band.
func _apply_layers() -> Color:
	var solid_color: Color = mixture.get_layer_color(-1, true)
	if emulsion_level > 0.5:
		_liquid_material.set_shader_parameter(&"layer2_depth_meters", -1.0)
		_liquid_material.set_shader_parameter(&"layer3_depth_meters", -1.0)
		var milky: Color = mixture.get_contents_color().lerp(Color(0.95, 0.93, 0.88, 0.95), emulsion_level * 0.5)
		return milky.lerp(solid_color, suspension_level * 0.6) if solid_color.a > 0.0 else milky
	# Bands from the bottom up: settled sediment, then liquids by density.
	var band_colors: Array[Color] = []
	var band_tops: PackedFloat32Array = PackedFloat32Array()
	var stacked_m3: float = 0.0
	var sediment_m3: float = mixture.get_solid_volume_m3() * (1.0 - suspension_level)
	if sediment_m3 > 2e-7:
		stacked_m3 += sediment_m3
		band_colors.append(Color(solid_color.r, solid_color.g, solid_color.b, 1.0))
		band_tops.append(_height_for_volume(stacked_m3).x)
	var order: Array[int] = [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return mixture.get_group_density_kg_m3(a) > mixture.get_group_density_kg_m3(b))
	for g: int in order:
		var v: float = mixture.get_group_volume_m3(g)
		if v <= 1e-7:
			continue
		stacked_m3 += v
		var c: Color = mixture.get_layer_color(g)
		if suspension_level > 0.01 and solid_color.a > 0.0:
			c = c.lerp(Color(solid_color.r, solid_color.g, solid_color.b, 0.95), suspension_level * 0.7)
		band_colors.append(c)
		band_tops.append(_height_for_volume(stacked_m3).x)
	if band_colors.is_empty():
		return mixture.get_contents_color()
	var n: int = band_colors.size()
	var top: Color = band_colors[n - 1]
	var l2_depth: float = -1.0
	var l3_depth: float = -1.0
	if n >= 2:
		l2_depth = maxf(_fill_local_y - band_tops[n - 2], 0.0005)
		_liquid_material.set_shader_parameter(&"layer2_color", band_colors[n - 2])
	if n >= 3:
		l3_depth = maxf(_fill_local_y - band_tops[n - 3], l2_depth + 0.0005)
		_liquid_material.set_shader_parameter(&"layer3_color", band_colors[n - 3])
	_liquid_material.set_shader_parameter(&"layer2_depth_meters", l2_depth)
	_liquid_material.set_shader_parameter(&"layer3_depth_meters", l3_depth)
	return top


## Flames leap to open vessels whose rims are close by.
func _spread_fire() -> void:
	var lip: Vector3 = global_transform * Vector3(0.0, _lip_local_y, 0.0)
	for other: Vessel3D in all_vessels:
		if other == self:
			continue
		var other_lip: Vector3 = other.global_transform * Vector3(0.0, other.get_lip_local_y(), 0.0)
		if lip.distance_to(other_lip) < 0.14:
			other.ignition_source = true


func _on_body_entered(_body: Node) -> void:
	var speed: float = linear_velocity.length()
	AudioHaptics.impact(speed)
	add_agitation(speed * 0.5)
