class_name ClickSwitch
extends RefCounted
## Shared click handling for bench controls (stove knob, burner, tap): a left
## click on one of the given static bodies under the pointer.


## The body in `targets` under a left click, or null.
static func clicked(node: Node3D, event: InputEvent, targets: Array) -> Object:
	var press: InputEventMouseButton = event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT or TactileGrabber3D.input_captured:
		return null
	var camera: Camera3D = node.get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin: Vector3 = camera.project_ray_origin(press.position)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(press.position) * 12.0, SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_CLICK_TARGET)
	var hit: Object = node.get_world_3d().direct_space_state.intersect_ray(query).get("collider")
	return hit if hit != null and targets.has(hit) else null


## A small clickable box (knob, button) on `parent`. It is on its own layer:
## the pointer hits it, but nothing collides with it.
static func make_button(parent: Node3D, size: Vector3, at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = SimConstants.LAYER_CLICK_TARGET
	body.collision_mask = 0
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = at
	parent.add_child(body)
	return body


## Small floating caption under a control.
static func make_caption(parent: Node3D, at: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.font_size = 26
	label.pixel_size = 0.00042
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	label.modulate = Color(1.0, 0.95, 0.85)
	parent.add_child(label)
	return label
