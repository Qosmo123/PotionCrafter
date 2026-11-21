class_name LightShafts3D
extends Node3D
## Slanted beams of window light falling across a work station, with a few
## brighter dust motes drifting inside them. Beams are additive quads
## (light_shaft.gdshader); the node's own rotation sets the slant. Built in
## code so each station only needs a placed node.

@export var beam_count: int = 3
@export var beam_length_meters: float = 1.25
@export var beam_width_meters: float = 0.13
@export var beam_gap_meters: float = 0.24
@export var strength: float = 0.22
@export var motes: int = 70

const SHAFT_SHADER: Shader = preload("res://visuals_3d/shaders/light_shaft.gdshader")


func _ready() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(name) + int(global_position.x * 100.0)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHAFT_SHADER
	for i: int in beam_count:
		var beam: MeshInstance3D = MeshInstance3D.new()
		beam.name = "Beam%d" % i
		var quad: QuadMesh = QuadMesh.new()
		var w: float = beam_width_meters * rng.randf_range(0.6, 1.3)
		quad.size = Vector2(w, beam_length_meters)
		quad.center_offset = Vector3(0.0, -beam_length_meters * 0.5, 0.0)  # hang down from the window
		quad.material = mat
		beam.mesh = quad
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3((float(i) - float(beam_count - 1) * 0.5) * beam_gap_meters + rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.04, 0.04))
		beam.set_instance_shader_parameter(&"strength", strength * rng.randf_range(0.6, 1.2))
		beam.set_instance_shader_parameter(&"phase", rng.randf() * 10.0)
		add_child(beam)
	if motes > 0:
		add_child(_make_motes())


func _make_motes() -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.name = "BeamMotes"
	p.amount = motes
	p.lifetime = 10.0
	p.preprocess = 10.0
	var span: float = float(beam_count) * beam_gap_meters
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(span * 0.5, beam_length_meters * 0.3, 0.05)
	pm.direction = Vector3.DOWN
	pm.spread = 180.0
	pm.initial_velocity_min = 0.002
	pm.initial_velocity_max = 0.008
	pm.gravity = Vector3(0.0, -0.003, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.25
	pm.turbulence_noise_scale = 1.5
	pm.turbulence_influence_min = 0.01
	pm.turbulence_influence_max = 0.03
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.7, 0.0))
	ramp.set_color(1, Color(1.0, 0.9, 0.7, 0.0))
	ramp.add_point(0.5, Color(1.0, 0.92, 0.75, 0.9))
	var ramp_tex: GradientTexture1D = GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	p.process_material = pm
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.0022, 0.0022)
	var mat: StandardMaterial3D = VesselEffects.billboard_material(true, 1.5)
	quad.material = mat
	p.draw_pass_1 = quad
	p.position = Vector3(0.0, -beam_length_meters * 0.55, 0.0)
	p.visibility_aabb = AABB(Vector3(-span, -beam_length_meters, -0.3), Vector3(span * 2.0, beam_length_meters * 2.0, 0.6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p
