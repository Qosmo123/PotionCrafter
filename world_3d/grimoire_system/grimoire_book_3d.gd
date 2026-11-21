class_name GrimoireBook3D
extends StaticBody3D
## The physical grimoire on the bench. Click it to open the book UI. Its
## cover sigil pulses brighter for a few seconds whenever a recipe is learned.

@export var model: PackedScene
@export var camera: Camera3D

var _glow_light: OmniLight3D
var _pulse: float = 0.0


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	if model != null:
		var visual: Node3D = model.instantiate() as Node3D
		add_child(visual)
		PropMaterials.apply(visual)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.27, 0.07, 0.19)
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.035
	add_child(collider)
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color(1.0, 0.65, 0.25)
	_glow_light.omni_range = 0.35
	_glow_light.light_energy = 0.15
	_glow_light.position = Vector3(0.0, 0.1, 0.0)
	add_child(_glow_light)
	if GrimoireJournal.instance != null:
		GrimoireJournal.instance.toast.connect(func(_t: String, kind: StringName) -> void:
			if kind == &"discovery" or kind == &"secret":
				_pulse = 1.0)


func _process(delta: float) -> void:
	_pulse = maxf(_pulse - delta * 0.25, 0.0)
	_glow_light.light_energy = 0.15 + 0.1 * sin(Time.get_ticks_msec() * 0.002) * 0.5 + _pulse * 1.8


func _unhandled_input(event: InputEvent) -> void:
	var press: InputEventMouseButton = event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT or camera == null:
		return
	if TactileGrabber3D.input_captured or GrimoireBookUI.instance == null:
		return
	var origin: Vector3 = camera.project_ray_origin(press.position)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(press.position) * 6.0)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.get("collider") == self:
		GrimoireBookUI.instance.open()
		get_viewport().set_input_as_handled()
