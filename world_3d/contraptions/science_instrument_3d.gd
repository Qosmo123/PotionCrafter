class_name ScienceInstrument3D
extends StaticBody3D
## Science-bench instrument. Set any vessel on its brass sample pad and it
## measures the contents with real physics (LabAssay), animates the
## experiment, and writes the result onto the vessel (meta "assay") so the
## safety data sheet can quote measured values.
##   VISCOMETER  falling-ball tube: the steel ball sinks at its true terminal
##               velocity (fast in water, crawls through honey)
##   AIR_METER   graduated cylinder + gauge: % of the sample that is air
##   VOLATILITY  evaporating dish on a balance: vapour pressure, flash point
##   HYDROMETER  floating density bulb + pH probe

enum Kind { VISCOMETER, AIR_METER, VOLATILITY, HYDROMETER }

const MEASURE_INTERVAL_S: float = 0.5
const MAX_SHOWN_FALL_S: float = 10.0
const TITLES: PackedStringArray = ["Falling-Ball Viscometer", "Air-Content Meter", "Volatility Tester", "Hydrometer & pH Probe"]

@export var kind: Kind = Kind.VISCOMETER

var _pad: Area3D
var _readout: Label3D
var _vessel: Vessel3D = null
var _timer: float = 0.0
var _announced_vessel: Vessel3D = null
var _result: Dictionary = {}
var _anim_t: float = 0.0
# Visual parts (some unused per kind).
var _fluid: MeshInstance3D
var _fluid_mat: StandardMaterial3D
var _ball: MeshInstance3D
var _foam: MeshInstance3D
var _needle: Node3D
var _float_body: Node3D
var _wisps: GPUParticles3D
var _warn_mat: StandardMaterial3D
var _shown_fall_s: float = 1.0
var _target_air: float = 0.0
var _target_depth: float = 0.5


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	_build_base()
	match kind:
		Kind.VISCOMETER: _build_viscometer()
		Kind.AIR_METER: _build_air_meter()
		Kind.VOLATILITY: _build_volatility()
		Kind.HYDROMETER: _build_hydrometer()
	_set_idle_text()


# ---------------------------------------------------------------- construction
func _mat(color: Color, metallic: float = 0.0, roughness: float = 0.5) -> StandardMaterial3D:
	# Opaque brass and steel fittings use the shared 4K metal set (never mutated).
	if metallic >= 0.9 and roughness >= 0.2 and color.a >= 1.0:
		return PropMaterials.textured("metal", color, 0.3, metallic)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _glass() -> Material:
	return QualityTier.pick_material(PropMaterials.GLASS_PC_MATERIAL, PropMaterials.GLASS_MOBILE_MATERIAL)


func _mesh(mesh: Mesh, mat: Material, at: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


func _cyl(radius: float, height: float, segments: int = 24) -> CylinderMesh:
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	return c


func _build_base() -> void:
	var plinth: BoxMesh = BoxMesh.new()
	plinth.size = Vector3(0.2, 0.025, 0.24)
	_mesh(plinth, PropMaterials.textured("iron", Color(0.34, 0.35, 0.38), 0.3, 0.4), Vector3(0.0, 0.0125, 0.0))
	var trim: BoxMesh = BoxMesh.new()
	trim.size = Vector3(0.204, 0.006, 0.244)
	_mesh(trim, _mat(Color(0.75, 0.55, 0.25), 0.9, 0.3), Vector3(0.0, 0.026, 0.0))
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.2, 0.03, 0.24)
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.015
	add_child(cs)
	# Brass sample pad at the front.
	_mesh(_cyl(0.045, 0.004, 32), _mat(Color(0.8, 0.6, 0.28), 0.95, 0.25), Vector3(0.0, 0.031, 0.06))
	_pad = Area3D.new()
	_pad.collision_layer = 0
	_pad.collision_mask = SimConstants.LAYER_RIGID_VESSEL
	_pad.monitorable = false
	var probe: CylinderShape3D = CylinderShape3D.new()
	probe.radius = 0.05
	probe.height = 0.05
	var pc: CollisionShape3D = CollisionShape3D.new()
	pc.shape = probe
	_pad.add_child(pc)
	_pad.position = Vector3(0.0, 0.06, 0.06)
	add_child(_pad)
	_readout = WorldPill.new()
	_readout.busy = func() -> bool: return _vessel != null
	_readout.font_size = 30
	_readout.pixel_size = 0.00042
	_readout.position = Vector3(0.0, 0.36, -0.02)
	_readout.width = 900.0
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_readout)


func _build_fluid_column(radius: float, height: float, base_y: float, z: float) -> void:
	_mesh(_cyl(radius + 0.002, height + 0.01), _glass(), Vector3(0.0, base_y + (height + 0.01) * 0.5, z))
	_fluid_mat = _mat(Color(0.7, 0.8, 0.9, 0.0))
	_fluid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fluid_mat.roughness = 0.1
	_fluid = _mesh(_cyl(radius, height), _fluid_mat, Vector3(0.0, base_y + height * 0.5, z))


func _build_viscometer() -> void:
	# Ring stand holding a tall tube.
	_mesh(_cyl(0.004, 0.3, 8), _mat(Color(0.3, 0.3, 0.32), 0.9, 0.3), Vector3(0.06, 0.18, -0.06))
	_mesh(_cyl(0.026, 0.006), _mat(Color(0.3, 0.3, 0.32), 0.9, 0.3), Vector3(0.0, 0.3, -0.04))
	_build_fluid_column(0.02, LabAssay.COLUMN_METERS + 0.02, 0.035, -0.04)
	var ball: SphereMesh = SphereMesh.new()
	ball.radius = 0.006
	ball.height = 0.012
	_ball = _mesh(ball, _mat(Color(0.85, 0.86, 0.9), 1.0, 0.12), Vector3(0.0, 0.25, -0.04))
	# Graduation ticks.
	var tick_mat: StandardMaterial3D = _mat(Color(0.9, 0.9, 0.85))
	tick_mat.emission_enabled = true
	tick_mat.emission = Color(0.4, 0.4, 0.38)
	for k: int in 11:
		var tick: BoxMesh = BoxMesh.new()
		tick.size = Vector3(0.008 if k % 5 == 0 else 0.005, 0.0012, 0.001)
		_mesh(tick, tick_mat, Vector3(0.018, 0.045 + float(k) * 0.02, -0.018))


func _build_air_meter() -> void:
	_build_fluid_column(0.024, 0.15, 0.035, -0.05)
	var foam_mat: StandardMaterial3D = _mat(Color(0.97, 0.97, 0.95), 0.0, 0.9)
	_foam = _mesh(_cyl(0.0235, 0.01), foam_mat, Vector3(0.0, 0.1, -0.05))
	_foam.visible = false
	# Dial gauge.
	var dial: MeshInstance3D = _mesh(_cyl(0.032, 0.008, 32), PropMaterials.textured("ceramic", Color(0.95, 0.93, 0.85), 0.25), Vector3(0.065, 0.12, -0.04))
	dial.rotation.x = PI * 0.5
	_mesh(_cyl(0.035, 0.006, 32), _mat(Color(0.75, 0.55, 0.25), 0.9, 0.3), Vector3(0.065, 0.12, -0.044)).rotation.x = PI * 0.5
	_needle = Node3D.new()
	_needle.position = Vector3(0.065, 0.12, -0.035)
	add_child(_needle)
	var needle: BoxMesh = BoxMesh.new()
	needle.size = Vector3(0.0025, 0.026, 0.001)
	_mesh(needle, _mat(Color(0.8, 0.1, 0.05)), Vector3(0.0, 0.012, 0.0), _needle)
	_mesh(_cyl(0.006, 0.12, 8), _mat(Color(0.3, 0.3, 0.32), 0.9, 0.3), Vector3(0.065, 0.06, -0.045))


func _build_volatility() -> void:
	# Balance beam with an evaporating dish.
	var post: MeshInstance3D = _mesh(_cyl(0.005, 0.12, 8), _mat(Color(0.75, 0.55, 0.25), 0.9, 0.3), Vector3(0.0, 0.09, -0.05))
	post.name = "Post"
	var beam: BoxMesh = BoxMesh.new()
	beam.size = Vector3(0.15, 0.005, 0.008)
	_needle = Node3D.new()
	_needle.position = Vector3(0.0, 0.15, -0.05)
	add_child(_needle)
	_mesh(beam, _mat(Color(0.75, 0.55, 0.25), 0.9, 0.3), Vector3.ZERO, _needle)
	var dish: CylinderMesh = _cyl(0.03, 0.01, 32)
	dish.bottom_radius = 0.022
	_mesh(dish, PropMaterials.textured("ceramic", Color(0.95, 0.95, 0.93), 0.25), Vector3(-0.065, -0.01, 0.0), _needle)
	_fluid_mat = _mat(Color(0.7, 0.8, 0.9, 0.0))
	_fluid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fluid = _mesh(_cyl(0.026, 0.003, 32), _fluid_mat, Vector3(-0.065, -0.006, 0.0), _needle)
	_mesh(_cyl(0.012, 0.004, 16), _mat(Color(0.3, 0.3, 0.32), 0.9, 0.3), Vector3(0.065, -0.004, 0.0), _needle)
	_wisps = GPUParticles3D.new()
	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 15.0
	proc.initial_velocity_min = 0.02
	proc.initial_velocity_max = 0.05
	proc.gravity = Vector3(0.0, 0.02, 0.0)
	proc.scale_min = 0.6
	proc.scale_max = 1.6
	_wisps.process_material = proc
	_wisps.amount = 24
	_wisps.lifetime = 2.0
	_wisps.emitting = false
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	quad.material = VesselEffects.billboard_material(false, 0.2, Color(0.9, 0.92, 0.95))
	_wisps.draw_pass_1 = quad
	_wisps.position = Vector3(-0.065, 0.0, 0.0)
	_needle.add_child(_wisps)
	# Flammability warning lamp.
	_warn_mat = _mat(Color(0.25, 0.05, 0.03))
	_warn_mat.emission_enabled = true
	_warn_mat.emission = Color(1.0, 0.2, 0.05)
	_warn_mat.emission_energy_multiplier = 0.0
	var lamp: SphereMesh = SphereMesh.new()
	lamp.radius = 0.008
	lamp.height = 0.016
	_mesh(lamp, _warn_mat, Vector3(0.075, 0.04, -0.09))


func _build_hydrometer() -> void:
	_build_fluid_column(0.026, 0.17, 0.035, -0.05)
	_float_body = Node3D.new()
	_float_body.position = Vector3(0.0, 0.15, -0.05)
	add_child(_float_body)
	var bulb: SphereMesh = SphereMesh.new()
	bulb.radius = 0.012
	bulb.height = 0.04
	var float_glass: StandardMaterial3D = _mat(Color(0.9, 0.95, 1.0, 0.45), 0.0, 0.05)
	float_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh(bulb, float_glass, Vector3(0.0, -0.03, 0.0), _float_body)
	_mesh(_cyl(0.004, 0.1, 8), float_glass, Vector3(0.0, 0.035, 0.0), _float_body)
	var weight: SphereMesh = SphereMesh.new()
	weight.radius = 0.006
	weight.height = 0.012
	_mesh(weight, _mat(Color(0.3, 0.3, 0.3), 1.0, 0.3), Vector3(0.0, -0.045, 0.0), _float_body)
	# pH probe on a little arm.
	_mesh(_cyl(0.003, 0.16, 8), _mat(Color(0.2, 0.2, 0.22)), Vector3(0.07, 0.11, -0.05))
	var meter: BoxMesh = BoxMesh.new()
	meter.size = Vector3(0.05, 0.03, 0.012)
	_mesh(meter, _mat(Color(0.15, 0.3, 0.4)), Vector3(0.07, 0.2, -0.05))


# ---------------------------------------------------------------- runtime
func _physics_process(delta: float) -> void:
	var found: Vessel3D = null
	for body: Node3D in _pad.get_overlapping_bodies():
		var v: Vessel3D = body as Vessel3D
		if v != null and v.mixture != null and v.mixture.get_total_mass_kg() > 1e-5:
			found = v
			break
	if found != _vessel:
		_vessel = found
		_timer = 0.0
		_anim_t = 0.0
		if found == null:
			_set_idle_text()
	if _vessel == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = MEASURE_INTERVAL_S
	var foam_m3: float = _vessel.foam_height_meters * PI * pow(_vessel.get_surface_radius_meters(), 2.0)
	_result = LabAssay.assay(_vessel.mixture, foam_m3)
	var stored: Dictionary = _vessel.get_meta(&"assay", {})
	stored.merge(_result, true)
	stored["measured_" + Kind.keys()[kind].to_lower()] = true
	_vessel.set_meta(&"assay", stored)
	_apply_result()
	if _announced_vessel != _vessel:
		_announced_vessel = _vessel
		if GrimoireJournal.instance != null:
			GrimoireJournal.instance.toast.emit("%s: %s" % [TITLES[kind], headline()], &"discovery")


func _process(delta: float) -> void:
	if _vessel == null:
		return
	_anim_t += delta
	match kind:
		Kind.VISCOMETER:
			if _ball != null:
				var cycle: float = _shown_fall_s + 0.8
				var t: float = fmod(_anim_t, cycle)
				var k: float = clampf(t / maxf(_shown_fall_s, 0.01), 0.0, 1.0)
				_ball.position.y = lerpf(0.245, 0.045, k)
		Kind.AIR_METER:
			_needle.rotation.z = lerp_angle(_needle.rotation.z, deg_to_rad(120.0) - _target_air * deg_to_rad(240.0), 1.0 - exp(-delta * 4.0))
		Kind.HYDROMETER:
			var bob: float = sin(_anim_t * 2.2) * 0.0015 * exp(-_anim_t * 0.5)
			var y: float = lerpf(0.21, 0.08, _target_depth) + bob
			_float_body.position.y = lerpf(_float_body.position.y, y, 1.0 - exp(-delta * 3.0))
		Kind.VOLATILITY:
			var vp: float = float(_result.get("vapor_kpa", 0.0))
			# Evaporating sample gets lighter: the dish side slowly rises.
			var tilt: float = -clampf(log(1.0 + vp) * 0.04, 0.0, 0.18) * (0.5 + 0.5 * sin(_anim_t * 0.6))
			_needle.rotation.z = lerpf(_needle.rotation.z, tilt, 1.0 - exp(-delta * 2.0))


func _apply_result() -> void:
	var color: Color = _vessel.mixture.get_contents_color()
	if _fluid_mat != null:
		_fluid_mat.albedo_color = Color(color.r, color.g, color.b, 0.45 if kind == Kind.HYDROMETER else 0.8)
	match kind:
		Kind.VISCOMETER:
			var t: float = float(_result["fall_time_s"])
			_shown_fall_s = clampf(t, 0.12, MAX_SHOWN_FALL_S)
		Kind.AIR_METER:
			_target_air = float(_result["air_fraction"])
			_foam.visible = _target_air > 0.01
			var foam_h: float = clampf(_target_air * 0.15, 0.002, 0.14)
			(_foam.mesh as CylinderMesh).height = foam_h
			_foam.position.y = 0.035 + 0.15 - foam_h * 0.5
			_fluid.scale.y = 1.0 - _target_air
			_fluid.position.y = 0.035 + 0.15 * (1.0 - _target_air) * 0.5
		Kind.VOLATILITY:
			var vp: float = float(_result["vapor_kpa"])
			_wisps.emitting = vp > 0.3
			_wisps.amount_ratio = clampf(log(1.0 + vp) / 4.0, 0.05, 1.0)
			var flash: float = float(_result["flash_k"])
			_warn_mat.emission_energy_multiplier = 3.0 if not is_nan(flash) and flash < 333.0 else 0.0
		Kind.HYDROMETER:
			_target_depth = LabAssay.hydrometer_depth_fraction(float(_result["density_kg_m3"]))
	_readout.text = "%s\n%s" % [TITLES[kind], detail_text()]


func headline() -> String:
	match kind:
		Kind.VISCOMETER:
			var mu: float = float(_result["viscosity_pas"])
			return "%s, %s" % [LabAssay.format_viscosity(mu), LabAssay.describe(mu, LabAssay.VISCOSITY_LANDMARKS)]
		Kind.AIR_METER:
			return "%.0f%% air" % (float(_result["air_fraction"]) * 100.0)
		Kind.VOLATILITY:
			var vp: float = float(_result["vapor_kpa"])
			return "volatility %s, %.1f kPa" % [LabAssay.describe(vp, LabAssay.VOLATILITY_LANDMARKS), vp]
		Kind.HYDROMETER:
			return "density %.3f g/mL, pH %.1f" % [float(_result["density_kg_m3"]) / 1000.0, float(_result["ph"])]
	return ""


func detail_text() -> String:
	match kind:
		Kind.VISCOMETER:
			var t: float = float(_result["fall_time_s"])
			var lapse: String = "  (time-lapse ×%.0f)" % (t / MAX_SHOWN_FALL_S) if t > MAX_SHOWN_FALL_S else ""
			var fall: String = "ball floats!" if is_inf(t) else "ball falls 20 cm in %s%s" % [LabAssay.format_duration(t) if t >= 1.0 else "%.2f s" % t, lapse]
			return "%s\n%s" % [headline(), fall]
		Kind.AIR_METER:
			var air: float = float(_result["air_fraction"])
			var word: String = "dense liquid" if air < 0.05 else ("a bit bubbly" if air < 0.25 else ("frothy" if air < 0.55 else "mostly air: whipped foam!"))
			return "%s (%s)\nfizz %.1f mL/s" % [headline(), word, float(_result["fizz_ml_s"])]
		Kind.VOLATILITY:
			var vp: float = float(_result["vapor_kpa"])
			var flash: float = float(_result["flash_k"])
			var flash_text: String = "not flammable" if is_nan(flash) else "flash point %.0f °C%s" % [flash - 273.15, "  ⚠ FLAMMABLE" if flash < 333.0 else ""]
			return "%s\n10 mL half-evaporates in %s\n%s" % [headline(), LabAssay.format_duration(LabAssay.evaporation_half_life_s(vp)), flash_text]
		Kind.HYDROMETER:
			var ph: float = float(_result["ph"])
			var ph_word: String = "strong acid" if ph < 3.0 else ("acidic" if ph < 6.0 else ("neutral" if ph <= 8.0 else ("alkaline" if ph < 11.0 else "strong base")))
			return "%s\n%s, %.0f °C" % [headline(), ph_word, float(_result["temperature_k"]) - 273.15]
	return ""


func _set_idle_text() -> void:
	if _readout != null:
		_readout.text = "%s\nset a vessel on the brass pad" % TITLES[kind]
	if _wisps != null:
		_wisps.emitting = false
