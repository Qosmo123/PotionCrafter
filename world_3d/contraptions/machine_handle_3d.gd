class_name MachineHandle3D
extends RigidBody3D
## Grabbable knob for hand-powered machines. The machine pins it with a Jolt
## joint (hinge = crank, slider = shaker). Its centre of mass sits at the knob,
## so dragging it with the grabber turns the crank or slides the shaker; the
## machine reads its motion as work.

@export var knob_radius_meters: float = 0.018
@export var knob_color: Color = Color(0.55, 0.25, 0.12)

var _height_y: float = 0.0


func _ready() -> void:
	collision_layer = SimConstants.LAYER_TACTILE_TOOL
	collision_mask = 0
	mass = 0.25
	linear_damp = 1.5
	angular_damp = 1.5
	can_sleep = false
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = knob_color
	mat.roughness = 0.4
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.6
	var knob: SphereMesh = SphereMesh.new()
	knob.radius = knob_radius_meters
	knob.height = knob_radius_meters * 2.2
	knob.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = knob
	add_child(mi)
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = knob_radius_meters * 1.6  # generous pick target (touch-friendly)
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	_height_y = global_position.y


## Keep the grabber's hover plane at the knob height so it drags, not yanks.
func get_hover_override_y() -> float:
	return _height_y


## The grabber leaves orientation to the joint.
func wants_free_rotation() -> bool:
	return true
