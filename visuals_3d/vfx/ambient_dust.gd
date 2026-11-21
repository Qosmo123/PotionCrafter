class_name AmbientDust
extends GPUParticles3D
## Slow-drifting dust motes that catch the window light and candle glow.
## Hidden on the mobile tier.

@export var region_size: Vector3 = Vector3(2.4, 1.0, 1.6)


func _ready() -> void:
	if QualityTier.is_mobile_tier():
		visible = false
		emitting = false
		return
	amount = 260
	lifetime = 14.0
	preprocess = 14.0
	local_coords = false
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = region_size * 0.5
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.002
	process.initial_velocity_max = 0.01
	process.gravity = Vector3(0.0, -0.002, 0.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.3
	process.turbulence_noise_scale = 2.0
	process.turbulence_influence_min = 0.01
	process.turbulence_influence_max = 0.03
	process.scale_min = 0.4
	process.scale_max = 1.2
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.85, 0.0))
	ramp.set_color(1, Color(1.0, 0.95, 0.85, 0.0))
	ramp.add_point(0.5, Color(1.0, 0.95, 0.85, 0.55))
	var ramp_tex: GradientTexture1D = GradientTexture1D.new()
	ramp_tex.gradient = ramp
	process.color_ramp = ramp_tex
	process_material = process
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.0025, 0.0025)
	var mat: StandardMaterial3D = VesselEffects.billboard_material(false, 0.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	quad.material = mat
	draw_pass_1 = quad
	visibility_aabb = AABB(-region_size, region_size * 2.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitting = true
