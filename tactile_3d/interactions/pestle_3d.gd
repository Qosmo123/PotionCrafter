class_name Pestle3D
extends StirTool3D
## The stone pestle. Held like a stirring tool (the hand's stir assist runs
## it round the bowl when it is held over the mortar), but in the mortar its
## head grinds instead of stirring: every tick the head spends inside the
## bowl, the distance it travelled times the force behind it is grinding work
## (MortarBowl3D.grind). Coming down fast is a pound: more force, and sparks.

## Press of a gentle grinding stroke, newtons (a hand leaning on the pestle).
const GRIND_FORCE_N: float = 22.0
## Extra force per m/s of downward speed (pounding).
const POUND_FORCE_N_PER_M_S: float = 60.0

var _prev_head_world: Vector3 = Vector3.ZERO
var _grind_tick: int = 0


func _init() -> void:
	length_meters = 0.15
	radius_meters = 0.011
	tool_mass_kg = 0.32
	swirl_coupling = 1.5
	agitation_gain = 0.3
	hover_offset_meters = -0.05


func _ready() -> void:
	super._ready()
	set_meta(&"sound_material", &"stone")
	var stone: StandardMaterial3D = PropMaterials.textured("stone", Color(0.7, 0.67, 0.63), 0.2)
	# Handle tapering to a rounded grinding head at the tip end.
	var handle: CylinderMesh = CylinderMesh.new()
	handle.top_radius = 0.0075
	handle.bottom_radius = 0.0105
	handle.height = length_meters - 0.02
	handle.radial_segments = 20
	handle.material = stone
	var handle_mi: MeshInstance3D = MeshInstance3D.new()
	handle_mi.mesh = handle
	handle_mi.position = Vector3(0.0, 0.01, 0.0)
	add_child(handle_mi)
	var head: SphereMesh = SphereMesh.new()
	head.radius = 0.0135
	head.height = 0.025
	head.radial_segments = 20
	head.rings = 10
	head.material = stone
	var head_mi: MeshInstance3D = MeshInstance3D.new()
	head_mi.mesh = head
	head_mi.position = Vector3(0.0, -0.5 * length_meters + 0.012, 0.0)
	add_child(head_mi)
	var knob: SphereMesh = SphereMesh.new()
	knob.radius = 0.009
	knob.height = 0.016
	knob.material = stone
	var knob_mi: MeshInstance3D = MeshInstance3D.new()
	knob_mi.mesh = knob
	knob_mi.position = Vector3(0.0, 0.5 * length_meters - 0.004, 0.0)
	add_child(knob_mi)
	_prev_head_world = global_transform * get_tip_local()


## Whether the head is inside the mortar's bowl.
func head_in_bowl(bowl: MortarBowl3D) -> bool:
	var local: Vector3 = bowl.global_transform.affine_inverse() * (global_transform * get_tip_local())
	return (Vector2(local.x, local.z).length() < MortarBowl3D.CAVITY_RADIUS_METERS + 0.004
		and local.y < MortarBowl3D.HEIGHT_METERS * 0.5 + 0.01 and local.y > bowl.get_cavity_bottom_local_y() - 0.015)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var head: Vector3 = global_transform * get_tip_local()
	var moved: Vector3 = head - _prev_head_world
	_prev_head_world = head
	var bowl: MortarBowl3D = MortarBowl3D.instance
	if bowl == null or not head_in_bowl(bowl):
		return
	var down_speed: float = maxf(-moved.y / maxf(delta, 1e-4), 0.0)
	var force: float = GRIND_FORCE_N + POUND_FORCE_N_PER_M_S * down_speed
	var work: float = bowl.grind(moved.length(), force, down_speed)
	if work > 0.0:
		AudioDirector.loop(&"mortar", &"grind_loop", head, clampf(work / (delta * 6.0), 0.25, 1.0), 0.75, -8.0)
