class_name Hammer3D
extends RigidBody3D
## Geologist's hammer, held head-down. While held, Space (or the Strike button)
## slams it down onto whatever is below: the grabber's spring yanks it to the
## bench, and the contact's kinetic energy (½ m v²) chips at a rock's
## hardness-scaled integrity until it cracks.

const SLAM_SECONDS: float = 0.22
const MIN_STRIKE_SPEED: float = 0.8

@export var head_mass_kg: float = 0.45
@export var bench_top_y: float = 0.8

var _slam_timer: float = 0.0
var _cooldown: float = 0.0


func _ready() -> void:
	collision_layer = SimConstants.LAYER_TACTILE_TOOL
	collision_mask = SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_SOLID_REAGENT | SimConstants.LAYER_TACTILE_TOOL
	mass = head_mass_kg
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.32, 0.17)
	wood.roughness = 0.6
	var iron: StandardMaterial3D = StandardMaterial3D.new()
	iron.albedo_color = Color(0.25, 0.25, 0.27)
	iron.metallic = 0.9
	iron.roughness = 0.35
	var handle: CylinderMesh = CylinderMesh.new()
	handle.top_radius = 0.009
	handle.bottom_radius = 0.011
	handle.height = 0.24
	handle.material = wood
	var handle_mi: MeshInstance3D = MeshInstance3D.new()
	handle_mi.mesh = handle
	handle_mi.position.y = 0.04
	add_child(handle_mi)
	var head: BoxMesh = BoxMesh.new()
	head.size = Vector3(0.11, 0.035, 0.035)
	head.material = iron
	var head_mi: MeshInstance3D = MeshInstance3D.new()
	head_mi.mesh = head
	head_mi.position.y = -0.085
	add_child(head_mi)
	var pick: BoxMesh = BoxMesh.new()
	pick.size = Vector3(0.04, 0.02, 0.02)
	pick.material = iron
	var pick_mi: MeshInstance3D = MeshInstance3D.new()
	pick_mi.mesh = pick
	pick_mi.position = Vector3(0.07, -0.085, 0.0)
	add_child(pick_mi)
	var handle_shape: CapsuleShape3D = CapsuleShape3D.new()
	handle_shape.radius = 0.012
	handle_shape.height = 0.24
	var hs: CollisionShape3D = CollisionShape3D.new()
	hs.shape = handle_shape
	hs.position.y = 0.04
	add_child(hs)
	var head_shape: BoxShape3D = BoxShape3D.new()
	head_shape.size = head.size
	var hd: CollisionShape3D = CollisionShape3D.new()
	hd.shape = head_shape
	hd.position.y = -0.085
	add_child(hd)


func slam() -> void:
	if _cooldown <= 0.0:
		_slam_timer = SLAM_SECONDS
		_cooldown = SLAM_SECONDS + 0.15


func _physics_process(delta: float) -> void:
	_slam_timer = maxf(_slam_timer - delta, 0.0)
	_cooldown = maxf(_cooldown - delta, 0.0)


## While slamming, pull the head down to the bench top.
func get_hover_override_y() -> float:
	return bench_top_y + 0.1 if _slam_timer > 0.0 else NAN


func _on_body_entered(body: Node) -> void:
	var rock: Rock3D = body as Rock3D
	if rock == null:
		return
	var v_rel: float = (linear_velocity - rock.linear_velocity).length()
	if v_rel >= MIN_STRIKE_SPEED:
		rock.strike(0.5 * head_mass_kg * v_rel * v_rel)
