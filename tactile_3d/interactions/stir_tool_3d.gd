class_name StirTool3D
extends RigidBody3D
## Grabbable stirring/mixing tool. The tool passes through glass, and when
## its tip is under a vessel's liquid surface its motion couples into the fluid:
##   * the tangential velocity around the vessel axis spins the liquid (swirl,
##     which drives the shader's paraboloid vortex and faster cooling),
##   * the speed of the stroke adds surface agitation (whisks aerate a lot),
##   * the liquid drags back on the tool in proportion to viscosity, so stirring
##     honey feels heavy and water feels light.
## Arcane tools add a chirality bias: they spin the liquid even when the motion
## is sloppy, in the direction set by `chirality_sign`.

@export var model: PackedScene
@export var length_meters: float = 0.26
@export var radius_meters: float = 0.004
@export var tool_mass_kg: float = 0.03
## How strongly the tip drags fluid into rotation (blade area).
@export var swirl_coupling: float = 6.0
@export var agitation_gain: float = 0.6
@export var drag_coefficient: float = 0.25
@export var chirality_bias_rad_s: float = 0.0
@export var chirality_sign: float = 1.0
## Lower the grab hover plane so the tip reaches into vessels.
@export var hover_offset_meters: float = -0.07

var _tip_local: Vector3 = Vector3.ZERO
var _prev_tip_world: Vector3 = Vector3.ZERO
var _active_vessel: Vessel3D = null


func _ready() -> void:
	collision_layer = SimConstants.LAYER_TACTILE_TOOL
	collision_mask = SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_TACTILE_TOOL
	mass = tool_mass_kg
	continuous_cd = true
	angular_damp = 1.0
	if model != null:
		var visual: Node3D = model.instantiate() as Node3D
		add_child(visual)
		PropMaterials.apply(visual)
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = maxf(radius_meters, 0.004)
	capsule.height = length_meters
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = capsule
	add_child(shape)
	_tip_local = Vector3(0.0, -0.5 * length_meters + 0.006, 0.0)
	_prev_tip_world = global_transform * _tip_local


func get_hover_offset_meters() -> float:
	return hover_offset_meters


## While the tool still sits inside a crock, hold it high enough that its tip
## clears the rim, so it lifts straight up and out. NAN = use the normal plane.
func get_hover_override_y() -> float:
	var tip_world: Vector3 = global_transform * _tip_local
	for crock: ToolCrock3D in ToolCrock3D.all_crocks:
		if crock.contains_xz(tip_world, 0.02) and tip_world.y < crock.rim_y() + 0.015:
			return crock.rim_y() + length_meters * 0.5 + 0.03
	return NAN


## The vessel the tip is currently stirring, or null.
func get_active_vessel() -> Vessel3D:
	return _active_vessel


func _physics_process(delta: float) -> void:
	var tip_world: Vector3 = global_transform * _tip_local
	var tip_velocity: Vector3 = (tip_world - _prev_tip_world) / maxf(delta, 1e-4)
	_prev_tip_world = tip_world
	_active_vessel = null
	for vessel: Vessel3D in Vessel3D.all_vessels:
		if vessel.mixture == null:
			continue
		var local_tip: Vector3 = vessel.global_transform.affine_inverse() * tip_world
		var radial: Vector2 = Vector2(local_tip.x, local_tip.z)
		var r: float = radial.length()
		var surface_r: float = vessel.get_surface_radius_meters()
		if r > surface_r or local_tip.y > vessel.get_fill_local_y() or local_tip.y < vessel.get_cavity_bottom_local_y() - 0.005:
			continue
		if vessel.mixture.get_liquid_volume_m3() <= 1e-8:
			continue
		_active_vessel = vessel
		_stir(vessel, tip_world, tip_velocity, r, surface_r, delta)
		break


func _stir(vessel: Vessel3D, tip_world: Vector3, tip_velocity: Vector3, r: float, surface_r: float, delta: float) -> void:
	var axis: Vector3 = vessel.global_basis.y.normalized()
	var vessel_point_velocity: Vector3 = vessel.linear_velocity + vessel.angular_velocity.cross(tip_world - vessel.global_position)
	var v_rel: Vector3 = tip_velocity - vessel_point_velocity
	var to_tip: Vector3 = tip_world - (vessel.global_position + axis * (tip_world - vessel.global_position).dot(axis))
	var tangential: float = 0.0
	if to_tip.length_squared() > 1e-8:
		tangential = to_tip.normalized().cross(v_rel).dot(axis)
	var lever_m: float = maxf(r, surface_r * 0.35)
	var target_swirl: float = tangential / lever_m + chirality_bias_rad_s * chirality_sign
	var viscosity_pas: float = vessel.mixture.get_liquid_viscosity_pas()
	var blend: float = 1.0 - exp(-delta * swirl_coupling / (1.0 + viscosity_pas * 2.0))
	vessel.mixture.swirl_rad_s = clampf(lerpf(vessel.mixture.swirl_rad_s, target_swirl, blend), -40.0, 40.0)
	vessel.add_agitation(v_rel.length() * agitation_gain * delta * 4.0)
	# Liquid swirl follows the stirring speed; the rod tings when it runs along the wall.
	var stir_speed: float = v_rel.length()
	AudioDirector.loop(&"swirl", &"swirl_loop", tip_world, clampf(stir_speed / 0.6, 0.0, 1.0), clampf(1.0 - viscosity_pas * 0.15, 0.6, 1.0) + stir_speed * 0.2, -10.0)
	if r > surface_r * 0.82 and stir_speed > 0.12 and randf() < delta * (2.0 + stir_speed * 14.0):
		AudioDirector.play(&"glass_ting", tip_world, lerpf(-22.0, -9.0, clampf(stir_speed / 0.8, 0.0, 1.0)), AudioDirector.vessel_pitch(surface_r, vessel.get_fill_fraction()))
	# Viscous drag back on the tool (felt through the spring grabber as weight).
	var drag: Vector3 = -v_rel * drag_coefficient * (0.05 + viscosity_pas)
	apply_central_force(drag.limit_length(6.0))
