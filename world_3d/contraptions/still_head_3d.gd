class_name StillHead3D
extends RigidBody3D
## A glass still head: a bulb on a ground-glass neck with a long side arm.
## Fitted on the mouth of a vessel, it takes everything that boils off (the
## vessel sends its gas phase here instead of the room). The arm is air
## cooled: vapour gives its heat to the room, condenses, and the distillate
## runs down the arm and drips from the tip into whatever open vessel stands
## under it (or onto the bench). Nothing is recipe-driven: what comes over
## first is whatever boils first (spirit before water, water before salts).
##
## Hand: hold it over a vessel and click to fit it; click the fitted head to
## lift it off. The arm points toward the nearest open vessel when fitted.

const NECK_IN_METERS: float = 0.018
const ARM_START: Vector3 = Vector3(0.022, 0.062, 0.0)
const ARM_ANGLE_DEG: float = -28.0
const ARM_LENGTH_METERS: float = 0.15
const ARM_RADIUS_METERS: float = 0.0055
## The cold arm: heat it carries away per kelvin above the room (W/K). Far
## more than a burner on full puts in, so vapour leaves the tip as cool liquid.
const CONDENSER_W_K: float = 200.0
## Gas still left once the arm is this close to room temperature will not
## condense (fizz gas) and escapes from the tip.
const NON_CONDENSABLE_MARGIN_K: float = 6.0
## Condensate runs down the arm at this rate (fraction per second).
const RUN_OFF_PER_S: float = 5.0
## The vessel tips the head off past this tilt.
const FALL_OFF_COS: float = 0.6

static var all_heads: Array[StillHead3D] = []

## What the arm holds: vapour on its way to becoming distillate.
var condenser: MixtureContainer = MixtureContainer.new()
## The vessel it is fitted on (null when loose).
var flask: Vessel3D = null
## Vapour received this tick (kg); set by the vessel.
var vapour_in_kg: float = 0.0
## Totals since the game started (kg).
var distilled_kg: float = 0.0
var spilled_kg: float = 0.0
var vented_kg: float = 0.0
## The vessel the arm is dripping into right now (null = the bench).
var receiver: Vessel3D = null
## Smoothed flow for the caption, fog and stream (kg/s).
var flow_kg_s: float = 0.0
## Distillate collected since it was last fitted (kg), for the caption.
var collected_kg: float = 0.0

var _side: float = 1.0
## Holds the glass; turned half round when the arm points left (the body's
## own yaw is locked by the side-view lock).
var _rig: Node3D
var _fog_mat: StandardMaterial3D
var _stream: PourStream3D
var _ray: RayCast3D
var _caption: WorldPill
var _drip_t: float = 0.0


func _ready() -> void:
	collision_layer = SimConstants.LAYER_TACTILE_TOOL
	collision_mask = SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_TACTILE_TOOL
	Flat2D.lock(self)
	mass = 0.09
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.03, 0.0)
	set_meta(&"sound_material", &"borosilicate")
	all_heads.append(self)
	_build_visuals()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.056, 0.084, 0.056)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, 0.042, 0.0)
	add_child(shape)
	_stream = PourStream3D.new()
	_stream.name = &"Drip"
	add_child(_stream)
	_ray = RayCast3D.new()
	_ray.top_level = true
	_ray.enabled = false
	_ray.collision_mask = SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_RIGID_VESSEL
	add_child(_ray)
	_caption = ClickSwitch.make_caption(self, Vector3(0.0, 0.13, 0.0))
	_caption.busy = func() -> bool: return flask != null and flow_kg_s > 1e-6


func _exit_tree() -> void:
	all_heads.erase(self)
	if flask != null and is_instance_valid(flask) and flask.still_head == self:
		flask.still_head = null


func _build_visuals() -> void:
	var glass_mat: Material = Vessel3D.GLASS_PC_MATERIAL
	_rig = Node3D.new()
	_rig.name = &"Rig"
	add_child(_rig)
	# Neck and bulb, walked from the top centre outward and down.
	var outline: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.084), Vector2(0.012, 0.081), Vector2(0.022, 0.074), Vector2(0.028, 0.058),
		Vector2(0.026, 0.045), Vector2(0.018, 0.036), Vector2(0.011, 0.03), Vector2(0.0105, 0.0),
	])
	var bulb: MeshInstance3D = MeshInstance3D.new()
	bulb.name = &"Glass"
	bulb.mesh = MeshUtil.lathe(outline, 48)
	bulb.material_override = glass_mat
	_rig.add_child(bulb)
	var arm_mesh: CylinderMesh = CylinderMesh.new()
	arm_mesh.top_radius = ARM_RADIUS_METERS
	arm_mesh.bottom_radius = ARM_RADIUS_METERS * 0.8
	arm_mesh.height = ARM_LENGTH_METERS
	arm_mesh.radial_segments = 20
	arm_mesh.rings = 1
	arm_mesh.material = glass_mat
	var arm: MeshInstance3D = MeshInstance3D.new()
	arm.mesh = arm_mesh
	var dir: Vector3 = _arm_dir_local()
	# CylinderMesh runs along +Y: turn +Y onto -dir (the top end at the bulb).
	arm.basis = Basis(Quaternion(Vector3.UP, -dir))
	arm.position = ARM_START + dir * ARM_LENGTH_METERS * 0.5
	_rig.add_child(arm)
	# Mist in the bulb while vapour comes over.
	_fog_mat = StandardMaterial3D.new()
	_fog_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fog_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fog_mat.albedo_color = Color(0.92, 0.95, 1.0, 0.0)
	_fog_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fog_mesh: SphereMesh = SphereMesh.new()
	fog_mesh.radius = 0.024
	fog_mesh.height = 0.04
	var fog: MeshInstance3D = MeshInstance3D.new()
	fog.mesh = fog_mesh
	fog.material_override = _fog_mat
	fog.position = Vector3(0.0, 0.058, 0.0)
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(fog)


func _arm_dir_local() -> Vector3:
	var a: float = deg_to_rad(ARM_ANGLE_DEG)
	return Vector3(cos(a), sin(a), 0.0)


## Where distillate leaves the arm, in world space.
func arm_tip_world() -> Vector3:
	return global_transform * (_rig.transform * (ARM_START + _arm_dir_local() * ARM_LENGTH_METERS))


## Whether `v` can take a still head.
static func can_fit(v: Vessel3D) -> bool:
	return v != null and v.mixture != null and v.open_top and not v.sealed and v.still_head == null \
		and not (v is MortarBowl3D) and v.global_basis.y.y > 0.8 and v.is_inside_tree()


## The vessel this (held) head would be fitted on if let go now.
func fit_candidate() -> Vessel3D:
	var best: Vessel3D = null
	var best_d: float = INF
	for v: Vessel3D in Vessel3D.all_vessels:
		if not can_fit(v):
			continue
		var mouth: Vector3 = v.global_transform * Vector3(0.0, v.get_lip_local_y(), 0.0)
		var d: float = absf(mouth.x - global_position.x)
		if d < v.get_lip_radius_meters() + 0.05 and global_position.y > mouth.y - 0.03 and d < best_d:
			best = v
			best_d = d
	return best


## Fit the head on `v`'s mouth: from now on its vapour comes here.
func fit_on(v: Vessel3D) -> bool:
	if not can_fit(v):
		return false
	if flask != null:
		unfit()
	flask = v
	v.still_head = self
	collected_kg = 0.0
	# Point the arm toward the nearest open vessel (right if none).
	_side = 1.0
	var best_d: float = 0.35
	for o: Vessel3D in Vessel3D.all_vessels:
		if o == v or not o.open_top or o.sealed or o.still_head != null or not o.is_inside_tree():
			continue
		var dx: float = o.global_position.x - v.global_position.x
		if absf(dx) > 0.06 and absf(dx) < best_d:
			best_d = absf(dx)
			_side = signf(dx)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_follow()
	AudioDirector.play(&"cork_push", global_position, -12.0, 1.4)
	return true


## Lift the head off its vessel (it becomes a loose piece of glass again).
func unfit() -> void:
	if flask != null and is_instance_valid(flask) and flask.still_head == self:
		flask.still_head = null
	flask = null
	freeze = false
	sleeping = false


func _follow() -> void:
	_rig.basis = Basis(Vector3.UP, PI) if _side < 0.0 else Basis.IDENTITY
	global_transform = Transform3D(flask.global_basis.orthonormalized(), flask.global_transform * Vector3(0.0, flask.get_lip_local_y() - NECK_IN_METERS, 0.0))


func _physics_process(delta: float) -> void:
	if flask != null:
		if not is_instance_valid(flask) or not flask.is_inside_tree() or flask.global_basis.y.normalized().y < FALL_OFF_COS or flask.sealed:
			unfit()
			linear_velocity = Vector3(0.0, 0.3, 0.0)
		else:
			_follow()
	var in_kg: float = vapour_in_kg
	vapour_in_kg = 0.0
	_condense(delta)
	flow_kg_s = lerpf(flow_kg_s, in_kg / maxf(delta, 1e-6), 1.0 - exp(-delta * 3.0))
	_fog_mat.albedo_color.a = clampf(flow_kg_s * 4000.0, 0.0, 0.45)


## Take heat from `m` into the room at CONDENSER_W_K, never past room
## temperature. Explicit (the latent heat at a boiling point is removed at
## the full rate, not linearised away). Returns the heat removed in joules.
static func cool_arm(m: MixtureContainer, delta: float) -> float:
	var over_k: float = m.temperature_kelvin - SimConstants.AMBIENT_TEMP_KELVIN
	if over_k <= 0.0:
		return 0.0
	var q: float = minf(CONDENSER_W_K * over_k * delta, m.enthalpy_joules - m.enthalpy_at(SimConstants.AMBIENT_TEMP_KELVIN))
	if q <= 0.0:
		return 0.0
	m.add_heat(-q)
	return q


## Cool the arm's contents to the room; let the condensate run out of the tip.
func _condense(delta: float) -> void:
	if condenser.get_total_mass_kg() < 1e-9:
		if _stream.visible:
			_stream.hide_stream()
		receiver = null
		return
	cool_arm(condenser, delta)
	# Whatever will not condense at room temperature (fizz gas) escapes.
	if condenser.temperature_kelvin < SimConstants.AMBIENT_TEMP_KELVIN + NON_CONDENSABLE_MARGIN_K:
		vented_kg += condenser.vent_gas(1.0)
	var condensed_m3: float = condenser.get_liquid_volume_m3() + condenser.get_solid_volume_m3()
	if condensed_m3 <= 1e-12:
		_stream.hide_stream()
		return
	var tip: Vector3 = arm_tip_world()
	receiver = _receiver_under(tip)
	var color: Color = condenser.get_contents_color()
	var frac: float = 1.0 - exp(-delta * RUN_OFF_PER_S)
	if condensed_m3 < 2e-9:
		frac = 1.0
	var dst: MixtureContainer = receiver.mixture if receiver != null else null
	var moved_kg: float = condenser.transfer_fraction_to(dst, frac)
	distilled_kg += moved_kg
	collected_kg += moved_kg
	var land_y: float = tip.y - 0.3
	if receiver != null:
		receiver.player_touched = true
		receiver.add_agitation(0.02)
		land_y = receiver.get_surface_point_world().y
	else:
		spilled_kg += moved_kg
		_ray.global_transform = Transform3D(Basis.IDENTITY, tip + Vector3(0.0, -0.005, 0.0))
		_ray.target_position = Vector3(0.0, -0.6, 0.0)
		_ray.force_raycast_update()
		if _ray.is_colliding():
			land_y = _ray.get_collision_point().y
		SpillPuddles3D.spill(self, Vector3(tip.x, land_y + 0.002, tip.z), condensed_m3 * frac, color)
	var rate_m3_s: float = condensed_m3 * frac / maxf(delta, 1e-6)
	if rate_m3_s > 4e-7:
		_stream.show_arc(tip, Vector3(0.0, -0.05, 0.0), land_y, 0.0022, color, 0.001)
	else:
		_stream.hide_stream()
		_drip_t -= delta
		if _drip_t <= 0.0:
			_drip_t = 0.35
			AudioDirector.play(&"drip", tip, -16.0, randf_range(1.1, 1.4))


## The open vessel under the tip. Left/right decides (the side view), depth
## only breaks ties, as everywhere else on the bench.
func _receiver_under(tip: Vector3) -> Vessel3D:
	var best: Vessel3D = null
	var best_score: float = INF
	for v: Vessel3D in Vessel3D.all_vessels:
		if v == flask or not v.open_top or v.sealed or v.still_head != null or v.mixture == null or not v.is_inside_tree():
			continue
		var mouth: Vector3 = v.global_transform * Vector3(0.0, v.get_lip_local_y(), 0.0)
		var dx: float = absf(tip.x - mouth.x)
		var dz: float = absf(tip.z - mouth.z)
		if tip.y > mouth.y - 0.015 and dx < v.get_lip_radius_meters() + 0.006 and dz < 0.35:
			var score: float = dx + 0.2 * dz
			if score < best_score:
				best = v
				best_score = score
	return best


func _process(_delta: float) -> void:
	if flask == null:
		_caption.text = ""
		return
	if flow_kg_s > 1e-6:
		_caption.text = "Distilling  ·  %.1f mL collected" % (collected_kg * 1000.0)
	elif collected_kg > 0.0:
		_caption.text = "%.1f mL collected" % (collected_kg * 1000.0)
	else:
		_caption.text = "Heat the %s to distil" % Vessel3D.short_name(flask)


func hover_info() -> String:
	if flask != null:
		var where: String = ("into the " + Vessel3D.short_name(receiver)) if receiver != null else "onto the bench (set a vessel under the arm)"
		return "[b]Still head[/b]  [color=#B3ADD6]on the %s: what boils off condenses in the arm and drips %s. Click to lift it off[/color]" % [Vessel3D.short_name(flask), where]
	return "[b]Still head[/b]  [color=#B3ADD6]fit it on a flask, set an empty vessel under the arm, then heat the flask: what boils first comes over first[/color]"
