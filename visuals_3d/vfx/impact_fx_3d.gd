class_name ImpactFx3D
extends Node3D
## Pooled "juice" for the mineral lab: stone-dust puffs, crystal sparks and the
## rare-find reveal (pillar of light, sparkle burst, a brief coloured light).
## Everything is built once and reused round-robin, so hammer blows never
## allocate. Presentation only: rocks report hits, this just shows them.

const DUST_POOL: int = 4
const SPARK_POOL: int = 4
const REVEAL_POOL: int = 2
const REVEAL_SECONDS: float = 2.6
const BEAM_SHADER: Shader = preload("res://visuals_3d/shaders/reveal_beam.gdshader")

static var _instance: ImpactFx3D = null

var _dust: Array[GPUParticles3D] = []
var _sparks: Array[GPUParticles3D] = []
var _reveals: Array[Dictionary] = []
var _next_dust: int = 0
var _next_spark: int = 0
var _next_reveal: int = 0


## The shared pool in the current scene (created on first use).
static func get_pool(context: Node) -> ImpactFx3D:
	if _instance != null and is_instance_valid(_instance) and _instance.is_inside_tree():
		return _instance
	if context == null or not context.is_inside_tree():
		return null
	var tree: SceneTree = context.get_tree()
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	_instance = ImpactFx3D.new()
	_instance.name = "ImpactFx"
	host.add_child(_instance)
	return _instance


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	var mobile: bool = QualityTier.is_mobile_tier()
	for i: int in DUST_POOL:
		_dust.append(_make_emitter(14 if mobile else 28, 0.9, false))
	for i: int in SPARK_POOL:
		_sparks.append(_make_emitter(10 if mobile else 22, 0.45, true))
	for i: int in REVEAL_POOL:
		_reveals.append(_make_reveal(mobile))


func _make_emitter(amount: int, lifetime_s: float, sparks: bool) -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime_s
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.012
	pm.direction = Vector3.UP
	pm.spread = 75.0 if sparks else 60.0
	pm.initial_velocity_min = 0.6 if sparks else 0.08
	pm.initial_velocity_max = 1.6 if sparks else 0.3
	pm.gravity = Vector3(0.0, -6.0 if sparks else -0.4, 0.0)
	pm.damping_min = 0.0 if sparks else 0.6
	pm.damping_max = 0.5 if sparks else 1.2
	pm.scale_min = 0.4 if sparks else 0.8
	pm.scale_max = 1.0 if sparks else 2.2
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp: GradientTexture1D = GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.009, 0.009) if sparks else Vector2(0.018, 0.018)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _soft_dot()
	if sparks:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	return p


static var _dot_tex: ImageTexture = null


static func _soft_dot() -> ImageTexture:
	if _dot_tex != null:
		return _dot_tex
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y: int in 16:
		for x: int in 16:
			var d: float = Vector2(x - 7.5, y - 7.5).length() / 7.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) * 0.8))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


func _make_reveal(mobile: bool) -> Dictionary:
	var root: Node3D = Node3D.new()
	root.visible = false
	add_child(root)
	var beam: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.02
	cyl.height = 0.7
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	beam.position.y = 0.35
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	beam.material_override = mat
	root.add_child(beam)
	var burst: GPUParticles3D = _make_emitter(16 if mobile else 40, 1.4, true)
	remove_child(burst)
	(burst.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, 0.3, 0.0)
	(burst.process_material as ParticleProcessMaterial).initial_velocity_max = 0.5
	(burst.process_material as ParticleProcessMaterial).emission_sphere_radius = 0.05
	root.add_child(burst)
	var light: OmniLight3D = OmniLight3D.new()
	light.omni_range = 0.45
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.position.y = 0.06
	light.visible = not mobile
	root.add_child(light)
	return {"root": root, "beam_mat": mat, "burst": burst, "light": light, "tween": null}


## Stone dust + crystal sparks where a blow lands. `strength` 0..1.
func hit(at: Vector3, dust_color: Color, spark_color: Color, strength: float) -> void:
	var d: GPUParticles3D = _dust[_next_dust]
	_next_dust = (_next_dust + 1) % _dust.size()
	d.global_position = at
	(d.process_material as ParticleProcessMaterial).color = Color(dust_color.lerp(Color(0.8, 0.78, 0.72), 0.5), 0.7)
	d.amount_ratio = clampf(0.35 + strength, 0.35, 1.0)
	d.restart()
	if strength < 0.12:
		return
	var s: GPUParticles3D = _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	s.global_position = at
	(s.process_material as ParticleProcessMaterial).color = spark_color
	s.amount_ratio = clampf(strength, 0.25, 1.0)
	s.restart()


## Dramatic shimmer reveal over a rare find.
func reveal(at: Vector3, color: Color) -> void:
	var r: Dictionary = _reveals[_next_reveal]
	_next_reveal = (_next_reveal + 1) % _reveals.size()
	var root: Node3D = r["root"]
	var tw: Tween = r["tween"] as Tween
	if tw != null and tw.is_valid():
		tw.kill()
	root.global_position = at
	root.visible = true
	var mat: ShaderMaterial = r["beam_mat"]
	mat.set_shader_parameter(&"color", color)
	var burst: GPUParticles3D = r["burst"]
	(burst.process_material as ParticleProcessMaterial).color = color.lightened(0.3)
	burst.restart()
	var light: OmniLight3D = r["light"]
	light.light_color = color
	tw = create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"life", v), 1.0, 0.0, REVEAL_SECONDS).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(light, "light_energy", 1.1, 0.25)
	tw.tween_property(light, "light_energy", 0.0, REVEAL_SECONDS - 0.25).set_delay(0.25)
	tw.tween_callback(func() -> void: root.visible = false).set_delay(REVEAL_SECONDS)
	r["tween"] = tw
