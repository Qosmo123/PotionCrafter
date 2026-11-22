class_name CosmicAtmosphere
extends Node3D
## The lab's cosmic dressing: slow star motes that drift and twinkle over all
## three stations, and soft violet / cyan accent lights that lift the shadows
## and tint glass and brass. Motes are one GPU particle system; the lights
## cast no shadows. Hidden on the mobile tier.

## Station centres along the bench (Potion Bench, Mineral Lab, Science Bench).
@export var station_x_meters: PackedFloat32Array = PackedFloat32Array([0.0, 3.0, 6.0])
@export var mote_count: int = 520
@export var violet: Color = Color(0.62, 0.42, 1.0)
@export var cyan: Color = Color(0.35, 0.85, 1.0)
@export var accent_energy: float = 0.7


func _ready() -> void:
	if QualityTier.is_mobile_tier():
		return
	for x: float in station_x_meters:
		_accent(Vector3(x - 1.1, 1.75, 0.35), violet, accent_energy)
		_accent(Vector3(x + 1.1, 1.55, 0.55), cyan, accent_energy * 0.75)
	_build_motes()


func _accent(at: Vector3, color: Color, energy: float, range_m: float = 2.6) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.light_specular = 0.2
	light.omni_range = range_m
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	add_child(light)


func _build_motes() -> void:
	var first: float = station_x_meters[0]
	var last: float = station_x_meters[station_x_meters.size() - 1]
	var region: Vector3 = Vector3(last - first + 3.2, 1.3, 1.1)
	var motes: GPUParticles3D = GPUParticles3D.new()
	motes.name = "StarMotes"
	motes.position = Vector3((first + last) * 0.5, 1.45, -0.3)
	motes.amount = mote_count
	motes.lifetime = 11.0
	motes.preprocess = 11.0
	motes.randomness = 1.0
	motes.local_coords = false
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = region * 0.5
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.004
	process.initial_velocity_max = 0.02
	process.gravity = Vector3(0.0, 0.004, 0.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.turbulence_noise_scale = 1.6
	process.turbulence_influence_min = 0.01
	process.turbulence_influence_max = 0.04
	process.scale_min = 0.35
	process.scale_max = 1.3
	# Each mote keeps one colour for its life (gold, cyan, pink, violet).
	var hues: Gradient = Gradient.new()
	hues.set_color(0, Color(1.0, 0.86, 0.5))
	hues.set_color(1, Color(0.7, 0.5, 1.0))
	hues.add_point(0.35, Color(0.5, 0.9, 1.0))
	hues.add_point(0.7, Color(1.0, 0.55, 0.85))
	var hue_tex: GradientTexture1D = GradientTexture1D.new()
	hue_tex.gradient = hues
	process.color_initial_ramp = hue_tex
	# Fade in, twinkle twice, fade out.
	var life: Gradient = Gradient.new()
	life.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	life.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	life.add_point(0.15, Color(1.0, 1.0, 1.0, 0.9))
	life.add_point(0.4, Color(1.0, 1.0, 1.0, 0.25))
	life.add_point(0.6, Color(1.0, 1.0, 1.0, 1.0))
	life.add_point(0.85, Color(1.0, 1.0, 1.0, 0.3))
	var life_tex: GradientTexture1D = GradientTexture1D.new()
	life_tex.gradient = life
	process.color_ramp = life_tex
	motes.process_material = process
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.007, 0.007)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.5, 1.5, 1.5)
	mat.albedo_texture = _spark_texture()
	mat.disable_receive_shadows = true
	quad.material = mat
	motes.draw_pass_1 = quad
	motes.visibility_aabb = AABB(-region, region * 2.0)
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)


## Soft round spark with a bright core.
func _spark_texture() -> GradientTexture2D:
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	g.add_point(0.25, Color(1.0, 1.0, 1.0, 0.45))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	return tex
