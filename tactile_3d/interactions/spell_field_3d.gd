class_name SpellField3D
extends Node3D
## A live arcane field created by a recognised chalk sigil. It acts on every
## vessel whose centre lies inside the sigil's radius (horizontal distance):
##   CIRCLE   warding: insulates (heat exchange x0.05) and calms reactions
##   TRIANGLE ignis: heats toward 900 K through a power-scaled conductance
##   SQUARE   glacies: chills toward 240 K (a drawable icebox)
##   PENTAGON ascension: counters gravity, so vessels float up and hover
##   HEXAGON  vortices: spins liquids like a magnetic stirrer
##   OCTAGON  catalysis: multiplies reaction mixing

const COLORS: Array[Color] = [Color.WHITE, Color(0.6, 0.8, 1.0), Color(1.0, 0.45, 0.15), Color(0.5, 0.9, 1.0), Color(0.85, 0.6, 1.0), Color(0.4, 1.0, 0.7), Color(1.0, 0.85, 0.3)]

var kind: SigilRecognizer.Kind = SigilRecognizer.Kind.NONE
var power: float = 0.0
var radius_meters: float = 0.07
var _light: OmniLight3D
var _gravity_m_s2: float = SimConstants.GRAVITY_M_S2


func setup(result: SigilRecognizer.Result, bench_y: float) -> void:
	kind = result.kind
	power = result.power
	radius_meters = result.radius_meters * 1.1
	position = Vector3(result.center.x, bench_y, result.center.y)


func get_color() -> Color:
	return COLORS[kind]


func _ready() -> void:
	_gravity_m_s2 = ProjectSettings.get_setting("physics/3d/default_gravity", SimConstants.GRAVITY_M_S2)
	_light = OmniLight3D.new()
	_light.light_color = get_color()
	_light.light_energy = 0.4 + power * 0.8
	_light.omni_range = radius_meters * 3.0
	_light.position.y = 0.04
	add_child(_light)


func _physics_process(_delta: float) -> void:
	_light.light_energy = (0.4 + power * 0.8) * (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.004))
	for vessel: Vessel3D in Vessel3D.all_vessels:
		if vessel.mixture == null:
			continue
		var offset: Vector3 = vessel.global_position - global_position
		if Vector2(offset.x, offset.z).length() > radius_meters or offset.y > 0.6 or offset.y < -0.05:
			continue
		var t: float = vessel.mixture.temperature_kelvin
		match kind:
			SigilRecognizer.Kind.CIRCLE:
				vessel.field_insulation = minf(vessel.field_insulation, lerpf(1.0, 0.05, clampf(power, 0.0, 1.0)))
				vessel.field_catalysis *= lerpf(1.0, 0.2, clampf(power, 0.0, 1.0))
			SigilRecognizer.Kind.TRIANGLE:
				vessel.external_heat_watts += 3.0 * power * (900.0 - t)
				vessel.ignition_source = true
			SigilRecognizer.Kind.SQUARE:
				vessel.external_heat_watts += 3.0 * power * (240.0 - t)
			SigilRecognizer.Kind.PENTAGON:
				var lift: float = 1.0 + 0.25 * power if offset.y < 0.18 * power + 0.05 else 1.0
				vessel.apply_central_force(Vector3.UP * vessel.mass * _gravity_m_s2 * vessel.gravity_scale * lift)
				vessel.angular_velocity *= 0.95
			SigilRecognizer.Kind.HEXAGON:
				vessel.mixture.swirl_rad_s = lerpf(vessel.mixture.swirl_rad_s, 16.0 * power, 0.03)
			SigilRecognizer.Kind.OCTAGON:
				vessel.field_catalysis *= 1.0 + 3.0 * power
				vessel.add_agitation(0.01 * power)
