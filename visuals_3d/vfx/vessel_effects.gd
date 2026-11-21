class_name VesselEffects
extends Node3D
## Per-vessel visual detail driven by the simulation (no gameplay logic):
##   steam wisps when hot or boiling, flames + flickering firelight while
##   burning, gold motes during transmutation, and foam that erupts over the
##   rim (elephant's toothpaste) and piles up on the bench.
## All particle systems are pooled here and only toggled/re-aimed per tick.

const SOFT_DOT_SIZE: int = 64

static var _soft_dot: GradientTexture2D = null
## Debug switch (capture bisecting): skip building effect particles.
static var disabled: bool = false

var _steam: GPUParticles3D
## Nebula steam: swirling coloured wisps + stardust over arcane or glowing brews.
var _nebula: GPUParticles3D
var _nebula_process: ParticleProcessMaterial
var _stardust: GPUParticles3D
var _stardust_process: ParticleProcessMaterial
## One-shot coloured puff when something new lands in the vessel.
var _puff: GPUParticles3D
var _puff_process: ParticleProcessMaterial
var _last_mass_kg: float = -1.0
var _steam_process: ParticleProcessMaterial
var _flames: GPUParticles3D
var _flame_process: ParticleProcessMaterial
var _fire_light: OmniLight3D
var _sparkles: GPUParticles3D
var _sparkle_process: ParticleProcessMaterial
var _foam: GPUParticles3D
var _stink: GPUParticles3D
var _stink_process: ParticleProcessMaterial
var _wisps: GPUParticles3D
var _sparks: GPUParticles3D
var _spark_light: OmniLight3D
var _petals: GPUParticles3D
var _petal_process: ParticleProcessMaterial
var _fog: GPUParticles3D
var _frost: GPUParticles3D
var _foam_process: ParticleProcessMaterial
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func soft_dot() -> GradientTexture2D:
	if _soft_dot == null:
		var gradient: Gradient = Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		_soft_dot = GradientTexture2D.new()
		_soft_dot.gradient = gradient
		_soft_dot.fill = GradientTexture2D.FILL_RADIAL
		_soft_dot.fill_from = Vector2(0.5, 0.5)
		_soft_dot.fill_to = Vector2(1.0, 0.5)
		_soft_dot.width = SOFT_DOT_SIZE
		_soft_dot.height = SOFT_DOT_SIZE
	return _soft_dot


static func billboard_material(additive: bool, emission_energy: float, emission_color: Color = Color.WHITE) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = soft_dot()
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission_color
		mat.emission_energy_multiplier = emission_energy
		mat.emission_texture = soft_dot()
	return mat


static func _quad(size: float, material: Material) -> QuadMesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	return quad


func _ready() -> void:
	top_level = true
	if disabled:
		set_physics_process(false)
		return
	_rng.seed = get_instance_id()

	_steam_process = ParticleProcessMaterial.new()
	_steam_process.direction = Vector3.UP
	_steam_process.spread = 18.0
	_steam_process.initial_velocity_min = 0.04
	_steam_process.initial_velocity_max = 0.1
	_steam_process.gravity = Vector3(0.0, 0.05, 0.0)
	_steam_process.scale_min = 0.6
	_steam_process.scale_max = 1.8
	_steam_process.scale_curve = _ramp_curve(0.3, 1.0)
	_steam_process.color_ramp = _alpha_ramp(Color(1.0, 1.0, 1.0, 0.0), Color(0.95, 0.96, 1.0, 0.28), Color(1.0, 1.0, 1.0, 0.0))
	_steam_process.turbulence_enabled = true
	_steam_process.turbulence_noise_strength = 0.6
	_steam_process.turbulence_influence_min = 0.05
	_steam_process.turbulence_influence_max = 0.12
	_steam = _make_particles(48, 2.6, _steam_process, _quad(0.05, billboard_material(false, 0.0)))

	_flame_process = ParticleProcessMaterial.new()
	_flame_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_flame_process.emission_sphere_radius = 0.01
	_flame_process.direction = Vector3.UP
	_flame_process.spread = 10.0
	_flame_process.initial_velocity_min = 0.12
	_flame_process.initial_velocity_max = 0.25
	_flame_process.gravity = Vector3(0.0, 0.6, 0.0)
	_flame_process.scale_min = 0.6
	_flame_process.scale_max = 1.3
	_flame_process.scale_curve = _ramp_curve(1.0, 0.1)
	_flame_process.color_ramp = _alpha_ramp(Color(0.6, 0.75, 1.0, 0.9), Color(1.0, 1.0, 1.0, 0.85), Color(0.8, 0.8, 0.8, 0.0))
	_flame_process.turbulence_enabled = true
	_flame_process.turbulence_noise_strength = 1.2
	_flame_process.turbulence_noise_scale = 6.0
	_flame_process.turbulence_influence_min = 0.08
	_flame_process.turbulence_influence_max = 0.2
	_flames = _make_particles(90, 0.45, _flame_process, _quad(0.035, billboard_material(true, 1.2, Color(1.0, 0.42, 0.08))))
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.55, 0.2)
	_fire_light.omni_range = 1.4
	_fire_light.shadow_enabled = true
	_fire_light.visible = false
	add_child(_fire_light)

	_sparkle_process = ParticleProcessMaterial.new()
	_sparkle_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_sparkle_process.emission_sphere_radius = 0.02
	_sparkle_process.direction = Vector3.UP
	_sparkle_process.spread = 180.0
	_sparkle_process.initial_velocity_min = 0.005
	_sparkle_process.initial_velocity_max = 0.02
	_sparkle_process.gravity = Vector3(0.0, 0.01, 0.0)
	_sparkle_process.orbit_velocity_min = 0.15
	_sparkle_process.orbit_velocity_max = 0.35
	_sparkle_process.scale_min = 0.3
	_sparkle_process.scale_max = 1.0
	_sparkle_process.color_ramp = _alpha_ramp(Color(1.0, 0.85, 0.3, 0.0), Color(1.0, 0.85, 0.35, 1.0), Color(1.0, 0.7, 0.2, 0.0))
	_sparkles = _make_particles(60, 1.4, _sparkle_process, _quad(0.006, billboard_material(true, 3.0, Color(1.0, 0.75, 0.2))))

	_foam_process = ParticleProcessMaterial.new()
	_foam_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_foam_process.emission_sphere_radius = 0.01
	_foam_process.direction = Vector3.UP
	_foam_process.spread = 40.0
	_foam_process.initial_velocity_min = 0.05
	_foam_process.initial_velocity_max = 0.2
	_foam_process.gravity = Vector3(0.0, -2.5, 0.0)
	_foam_process.damping_min = 0.5
	_foam_process.damping_max = 1.5
	_foam_process.scale_min = 0.6
	_foam_process.scale_max = 1.6
	_foam_process.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	_foam_process.collision_friction = 1.0
	_foam_process.collision_bounce = 0.0
	_foam_process.collision_use_scale = true
	var foam_material: StandardMaterial3D = StandardMaterial3D.new()
	foam_material.vertex_color_use_as_albedo = true
	foam_material.roughness = 0.55
	foam_material.subsurf_scatter_enabled = true
	foam_material.subsurf_scatter_strength = 0.4
	var foam_mesh: SphereMesh = SphereMesh.new()
	foam_mesh.radius = 0.007
	foam_mesh.height = 0.012
	foam_mesh.radial_segments = 10
	foam_mesh.rings = 5
	foam_mesh.material = foam_material
	_foam = _make_particles(220, 6.0, _foam_process, foam_mesh)

	# Cartoon stink clouds: lazy green puffs wobbling upward.
	_stink_process = ParticleProcessMaterial.new()
	_stink_process.direction = Vector3.UP
	_stink_process.spread = 25.0
	_stink_process.initial_velocity_min = 0.03
	_stink_process.initial_velocity_max = 0.07
	_stink_process.gravity = Vector3(0.0, 0.02, 0.0)
	_stink_process.scale_min = 0.8
	_stink_process.scale_max = 2.0
	_stink_process.scale_curve = _ramp_curve(0.4, 1.4)
	_stink_process.color_ramp = _alpha_ramp(Color(0.55, 0.8, 0.2, 0.0), Color(0.5, 0.75, 0.15, 0.45), Color(0.6, 0.8, 0.3, 0.0))
	_stink_process.turbulence_enabled = true
	_stink_process.turbulence_noise_strength = 1.5
	_stink_process.turbulence_influence_min = 0.1
	_stink_process.turbulence_influence_max = 0.25
	_stink = _make_particles(24, 3.0, _stink_process, _quad(0.05, billboard_material(false, 0.0)))

	# Spooky: pale ghost wisps that swirl up and fade.
	var wisp_p: ParticleProcessMaterial = ParticleProcessMaterial.new()
	wisp_p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	wisp_p.emission_sphere_radius = 0.03
	wisp_p.direction = Vector3.UP
	wisp_p.spread = 30.0
	wisp_p.initial_velocity_min = 0.02
	wisp_p.initial_velocity_max = 0.06
	wisp_p.gravity = Vector3(0.0, 0.03, 0.0)
	wisp_p.orbit_velocity_min = 0.2
	wisp_p.orbit_velocity_max = 0.5
	wisp_p.scale_min = 0.6
	wisp_p.scale_max = 1.8
	wisp_p.scale_curve = _ramp_curve(0.3, 1.5)
	wisp_p.color_ramp = _alpha_ramp(Color(0.7, 0.85, 1.0, 0.0), Color(0.75, 0.9, 1.0, 0.35), Color(0.8, 0.9, 1.0, 0.0))
	wisp_p.turbulence_enabled = true
	wisp_p.turbulence_noise_strength = 1.2
	wisp_p.turbulence_influence_min = 0.05
	wisp_p.turbulence_influence_max = 0.15
	_wisps = _make_particles(18, 4.0, wisp_p, _quad(0.06, billboard_material(true, 0.6, Color(0.6, 0.8, 1.0))))

	# Electric: fast crackling sparks and a flickering blue light.
	var spark_p: ParticleProcessMaterial = ParticleProcessMaterial.new()
	spark_p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spark_p.emission_sphere_radius = 0.02
	spark_p.direction = Vector3.UP
	spark_p.spread = 180.0
	spark_p.initial_velocity_min = 0.3
	spark_p.initial_velocity_max = 0.9
	spark_p.gravity = Vector3.ZERO
	spark_p.damping_min = 3.0
	spark_p.damping_max = 6.0
	spark_p.color_ramp = _alpha_ramp(Color(0.9, 0.95, 1.0, 1.0), Color(0.5, 0.75, 1.0, 1.0), Color(0.3, 0.5, 1.0, 0.0))
	_sparks = _make_particles(40, 0.18, spark_p, _quad(0.004, billboard_material(true, 4.0, Color(0.6, 0.8, 1.0))))
	_spark_light = OmniLight3D.new()
	_spark_light.light_color = Color(0.55, 0.75, 1.0)
	_spark_light.omni_range = 0.6
	_spark_light.visible = false
	add_child(_spark_light)

	# Vitality: little leaves and petals drifting down around the vessel.
	_petal_process = ParticleProcessMaterial.new()
	_petal_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_petal_process.emission_ring_radius = 0.06
	_petal_process.emission_ring_inner_radius = 0.03
	_petal_process.emission_ring_height = 0.01
	_petal_process.emission_ring_axis = Vector3.UP
	_petal_process.direction = Vector3.UP
	_petal_process.spread = 60.0
	_petal_process.initial_velocity_min = 0.05
	_petal_process.initial_velocity_max = 0.12
	_petal_process.gravity = Vector3(0.0, -0.08, 0.0)
	_petal_process.angular_velocity_min = -180.0
	_petal_process.angular_velocity_max = 180.0
	_petal_process.color_ramp = _alpha_ramp(Color(0.6, 1.0, 0.4, 0.0), Color(0.7, 1.0, 0.5, 0.9), Color(1.0, 0.7, 0.8, 0.0))
	_petals = _make_particles(16, 3.0, _petal_process, _quad(0.008, billboard_material(false, 0.5, Color(0.6, 1.0, 0.5))))

	# Cryogenic fog: heavy white mist that spills over the rim and rolls across the bench.
	var fog_p: ParticleProcessMaterial = ParticleProcessMaterial.new()
	fog_p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fog_p.emission_sphere_radius = 0.02
	fog_p.direction = Vector3(0.0, -0.2, 0.0)
	fog_p.spread = 90.0
	fog_p.initial_velocity_min = 0.05
	fog_p.initial_velocity_max = 0.15
	fog_p.gravity = Vector3(0.0, -0.25, 0.0)
	fog_p.damping_min = 0.3
	fog_p.damping_max = 0.6
	fog_p.scale_min = 1.0
	fog_p.scale_max = 2.5
	fog_p.scale_curve = _ramp_curve(0.5, 2.0)
	fog_p.color_ramp = _alpha_ramp(Color(1.0, 1.0, 1.0, 0.0), Color(0.95, 0.97, 1.0, 0.45), Color(1.0, 1.0, 1.0, 0.0))
	fog_p.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	_fog = _make_particles(60, 3.5, fog_p, _quad(0.07, billboard_material(false, 0.0)))

	# Frost: icy glints on and around very cold glass.
	var frost_p: ParticleProcessMaterial = ParticleProcessMaterial.new()
	frost_p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	frost_p.emission_sphere_radius = 0.04
	frost_p.gravity = Vector3.ZERO
	frost_p.initial_velocity_max = 0.0
	frost_p.color_ramp = _alpha_ramp(Color(0.8, 0.95, 1.0, 0.0), Color(0.9, 0.97, 1.0, 1.0), Color(0.8, 0.95, 1.0, 0.0))
	_frost = _make_particles(30, 1.2, frost_p, _quad(0.004, billboard_material(true, 2.0, Color(0.8, 0.95, 1.0))))
	_foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_build_nebula()


func _build_nebula() -> void:
	var mobile: bool = QualityTier.is_mobile_tier()
	_nebula_process = ParticleProcessMaterial.new()
	_nebula_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_nebula_process.emission_sphere_radius = 0.02
	_nebula_process.direction = Vector3.UP
	_nebula_process.spread = 20.0
	_nebula_process.initial_velocity_min = 0.03
	_nebula_process.initial_velocity_max = 0.07
	_nebula_process.gravity = Vector3(0.0, 0.03, 0.0)
	_nebula_process.orbit_velocity_min = 0.08
	_nebula_process.orbit_velocity_max = 0.22
	_nebula_process.scale_min = 0.8
	_nebula_process.scale_max = 2.2
	_nebula_process.scale_curve = _ramp_curve(0.4, 1.8)
	_nebula_process.color_ramp = _alpha_ramp(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.32), Color(1, 1, 1, 0.0))
	_nebula_process.hue_variation_min = -0.06
	_nebula_process.hue_variation_max = 0.06
	_nebula_process.turbulence_enabled = true
	_nebula_process.turbulence_noise_strength = 0.9
	_nebula_process.turbulence_influence_min = 0.05
	_nebula_process.turbulence_influence_max = 0.14
	_nebula = _make_particles(16 if mobile else 36, 3.2, _nebula_process, _quad(0.06, billboard_material(true, 0.0)))
	_stardust_process = ParticleProcessMaterial.new()
	_stardust_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_stardust_process.emission_sphere_radius = 0.03
	_stardust_process.direction = Vector3.UP
	_stardust_process.spread = 40.0
	_stardust_process.initial_velocity_min = 0.02
	_stardust_process.initial_velocity_max = 0.06
	_stardust_process.gravity = Vector3(0.0, 0.02, 0.0)
	_stardust_process.orbit_velocity_min = 0.2
	_stardust_process.orbit_velocity_max = 0.45
	_stardust_process.color_ramp = _alpha_ramp(Color(1.0, 0.9, 0.55, 0.0), Color(1.0, 0.92, 0.6, 1.0), Color(0.6, 0.9, 1.0, 0.0))
	_stardust = _make_particles(12 if mobile else 30, 2.2, _stardust_process, _quad(0.004, billboard_material(true, 3.0, Color(1.0, 0.9, 0.6))))
	_puff_process = ParticleProcessMaterial.new()
	_puff_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_puff_process.emission_sphere_radius = 0.015
	_puff_process.direction = Vector3.UP
	_puff_process.spread = 50.0
	_puff_process.initial_velocity_min = 0.06
	_puff_process.initial_velocity_max = 0.16
	_puff_process.gravity = Vector3(0.0, 0.05, 0.0)
	_puff_process.damping_min = 0.3
	_puff_process.damping_max = 0.6
	_puff_process.scale_min = 0.8
	_puff_process.scale_max = 1.8
	_puff_process.scale_curve = _ramp_curve(0.5, 1.6)
	_puff_process.color_ramp = _alpha_ramp(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0))
	_puff = _make_particles(10 if mobile else 18, 1.2, _puff_process, _quad(0.045, billboard_material(true, 0.0)))
	_puff.one_shot = true
	_puff.explosiveness = 0.85


func _make_particles(amount: int, lifetime: float, process: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.process_material = process
	p.draw_pass_1 = mesh
	p.visibility_aabb = AABB(Vector3(-1.5, -1.0, -1.5), Vector3(3.0, 3.0, 3.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## Called by the vessel each physics tick with world-space anchor points.
func update_effects(vessel: Vessel3D, lip_world: Vector3, surface_world: Vector3, surface_radius: float, overflow_rate_m_s: float) -> void:
	if disabled:
		return
	var m: MixtureContainer = vessel.mixture
	var t: float = m.temperature_kelvin
	var has_liquid: bool = m.get_liquid_volume_m3() > 1e-7

	var steam_level: float = clampf((t - 330.0) / 40.0, 0.0, 1.0)
	if vessel.is_boiling:
		steam_level = 1.0
	_steam.emitting = has_liquid and steam_level > 0.02 and vessel.open_top
	if _steam.emitting:
		_steam.global_position = lip_world
		_steam.amount_ratio = clampf(steam_level, 0.1, 1.0)

	# Steam takes on a hint of the brew's colour.
	if _steam.emitting:
		_steam_process.color = Color(1, 1, 1).lerp(m.get_contents_color(), 0.25)

	# Nebula steam over arcane or glowing brews, coloured by the brew itself.
	var aura: Color = m.get_emission_hdr()
	var glow: float = aura.r + aura.g + aura.b
	var thaums_per_mol: float = m.get_total_thaums() / maxf(m.get_total_moles(), 1e-9)
	var arcane: float = clampf(maxf(glow / 1.5, thaums_per_mol / 25.0), 0.0, 1.0)
	_nebula.emitting = has_liquid and vessel.open_top and arcane > 0.12
	_stardust.emitting = _nebula.emitting and arcane > 0.3
	if _nebula.emitting:
		var tint: Color = m.get_contents_color().lerp(Color(0.48, 0.25, 0.89), 0.35)
		if glow > 0.1:
			tint = tint.lerp(Color(aura.r, aura.g, aura.b).clamp(), 0.4)
		_nebula_process.color = Color(tint, 1.0)
		_nebula.global_position = surface_world + Vector3.UP * 0.02
		_nebula.amount_ratio = clampf(arcane, 0.25, 1.0)
		if _stardust.emitting:
			_stardust.global_position = surface_world + Vector3.UP * 0.03
			_stardust.amount_ratio = clampf(arcane, 0.3, 1.0)

	# A coloured puff whenever something new is added (≥ 1 g in one tick).
	var mass_kg: float = m.get_total_mass_kg()
	if _last_mass_kg >= 0.0 and mass_kg - _last_mass_kg > 0.001 and has_liquid and vessel.open_top and not _puff.emitting:
		_puff_process.color = Color(m.get_contents_color().lightened(0.2), 1.0)
		_puff.global_position = surface_world + Vector3.UP * 0.01
		_puff.restart()
	_last_mass_kg = mass_kg

	_flames.emitting = m.burning and vessel.open_top
	_fire_light.visible = _flames.emitting
	if _flames.emitting:
		var flame_base: Vector3 = surface_world if surface_world.y > lip_world.y - 0.04 else lip_world
		_flames.global_position = flame_base + Vector3.UP * 0.004
		_flame_process.emission_sphere_radius = clampf(surface_radius * 0.6, 0.004, 0.03)
		_flames.amount_ratio = clampf(m.burn_rate_kg_s / 0.0004, 0.3, 1.0)
		_fire_light.global_position = flame_base + Vector3.UP * 0.06
		_fire_light.light_energy = 1.4 + _rng.randf_range(-0.45, 0.45)
		var flame_color: Color = m.get_flame_color()
		_flame_process.color = flame_color
		_fire_light.light_color = flame_color.lerp(Color(1.0, 0.7, 0.4), 0.3)

	var aurum: int = SubstanceRegistry.index_of_id(&"aurum_potabile")
	var gold_moles: float = m.moles[aurum] if aurum >= 0 else 0.0
	_sparkles.emitting = has_liquid and (m.transmutation_rate_mol_s > 1e-5 or gold_moles > 0.02)
	if _sparkles.emitting:
		_sparkles.global_position = surface_world - Vector3.UP * 0.015
		_sparkle_process.emission_sphere_radius = clampf(surface_radius * 0.8, 0.004, 0.04)
		_sparkles.amount_ratio = clampf(m.transmutation_rate_mol_s * 200.0 + gold_moles * 2.0, 0.15, 1.0)

	var odor: float = m.get_odor()
	_stink.emitting = odor > 0.15 and vessel.open_top
	if _stink.emitting:
		_stink.global_position = lip_world + Vector3.UP * 0.02
		_stink.amount_ratio = clampf(odor, 0.2, 1.0)

	var spooky: float = m.get_spookiness()
	_wisps.emitting = has_liquid and spooky > 0.1
	if _wisps.emitting:
		_wisps.global_position = surface_world + Vector3.UP * 0.03
		_wisps.amount_ratio = clampf(spooky, 0.2, 1.0)
	var electric: float = m.get_electric()
	_sparks.emitting = has_liquid and electric > 0.1
	_spark_light.visible = _sparks.emitting and _rng.randf() < 0.35
	if _sparks.emitting:
		_sparks.global_position = surface_world
		_sparks.amount_ratio = clampf(electric, 0.2, 1.0)
		_spark_light.global_position = surface_world + Vector3.UP * 0.05
		_spark_light.light_energy = electric * _rng.randf_range(0.5, 2.0)
	var vitality: float = _weighted_vitality(m)
	_petals.emitting = has_liquid and vitality > 0.25
	if _petals.emitting:
		_petals.global_position = lip_world + Vector3.UP * 0.02
	var cold: bool = m.temperature_kelvin < 273.0
	_fog.emitting = has_liquid and m.gas_generation_mol_s > 0.002 and m.temperature_kelvin < 285.0
	if _fog.emitting:
		_fog.global_position = lip_world
		_fog.amount_ratio = clampf(m.gas_generation_mol_s * 20.0, 0.3, 1.0)
	_frost.emitting = cold and has_liquid
	if _frost.emitting:
		_frost.global_position = surface_world - Vector3.UP * 0.02

	_foam.emitting = overflow_rate_m_s > 1e-5
	if _foam.emitting:
		_foam.global_position = lip_world + Vector3.UP * 0.006
		_foam_process.color = Color(0.97, 0.96, 0.93).lerp(m.get_contents_color(), 0.25)
		_foam_process.initial_velocity_max = clampf(overflow_rate_m_s * 8.0, 0.08, 0.5)
		_foam.amount_ratio = clampf(overflow_rate_m_s * 60.0, 0.2, 1.0)


func _weighted_vitality(m: MixtureContainer) -> float:
	var total: float = m.get_total_mass_kg()
	if total <= 0.0:
		return 0.0
	var acc: float = 0.0
	for i: int in m.species_count:
		if m.moles[i] > 0.0:
			var s: SubstanceData = SubstanceRegistry.get_substance(i)
			acc += m.moles[i] * s.molar_mass_kg_mol * s.vitality_resonance
	return acc / total


func _ramp_curve(start: float, end: float) -> CurveTexture:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, start))
	curve.add_point(Vector2(1.0, end))
	var tex: CurveTexture = CurveTexture.new()
	tex.curve = curve
	return tex


func _alpha_ramp(a: Color, b: Color, c: Color) -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, a)
	gradient.set_color(1, c)
	gradient.add_point(0.25, b)
	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = gradient
	return tex
