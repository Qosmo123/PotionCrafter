class_name ToolCrock3D
extends StaticBody3D
## Upright stoneware utensil crock. Its collision is a hollow shell (a ring of
## wall segments plus a base) so stirring tools stand inside it, splayed
## outward against the rim. Tools grabbed from inside lift straight up and out
## (see StirTool3D.get_hover_override_y) instead of dragging through the wall.

const SLOT_COUNT: int = 7
const WALL_SEGMENTS: int = 16

static var all_crocks: Array[ToolCrock3D] = []

@export var model: PackedScene
@export var outer_radius_meters: float = 0.055
@export var height_meters: float = 0.17
@export var wall_meters: float = 0.006
@export var base_meters: float = 0.012
@export var splay_degrees: float = 6.0
## Tools placed in the crock on load.
@export var stocked_tools: Array[NodePath] = []

var _slots: Array[StirTool3D] = []


func _enter_tree() -> void:
	all_crocks.append(self)


func _exit_tree() -> void:
	all_crocks.erase(self)


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	_slots.resize(SLOT_COUNT)
	if model != null:
		var visual: Node3D = model.instantiate() as Node3D
		add_child(visual)
		PropMaterials.apply(visual)
	var base: CylinderShape3D = CylinderShape3D.new()
	base.radius = outer_radius_meters
	base.height = base_meters
	_add_shape(base, Transform3D(Basis.IDENTITY, Vector3(0.0, base_meters * 0.5, 0.0)))
	var mid_radius: float = outer_radius_meters - wall_meters * 0.5
	var segment_width: float = TAU * outer_radius_meters / float(WALL_SEGMENTS) * 1.08
	for i: int in WALL_SEGMENTS:
		var angle: float = TAU * float(i) / float(WALL_SEGMENTS)
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(segment_width, height_meters, wall_meters)
		var basis: Basis = Basis(Vector3.UP, -angle + PI * 0.5)
		_add_shape(box, Transform3D(basis, Vector3(cos(angle) * mid_radius, height_meters * 0.5, sin(angle) * mid_radius)))
	for path: NodePath in stocked_tools:
		var tool: StirTool3D = get_node_or_null(path) as StirTool3D
		if tool != null:
			place_tool(tool)


func _add_shape(shape: Shape3D, xf: Transform3D) -> void:
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	collider.transform = xf
	add_child(collider)


func rim_y() -> float:
	return global_position.y + height_meters


## True when a world point is inside the crock's footprint (horizontally).
func contains_xz(point: Vector3, margin_meters: float = 0.0) -> bool:
	var d: Vector2 = Vector2(point.x - global_position.x, point.z - global_position.z)
	return d.length() < outer_radius_meters + margin_meters


func has_free_slot() -> bool:
	_release_departed()
	return _slots.has(null)


## Stand a tool upright in the next free slot, tip on the base, top splayed out.
func place_tool(tool: StirTool3D) -> bool:
	_release_departed()
	var slot: int = _slots.find(null)
	if slot < 0:
		return false
	_slots[slot] = tool
	var radial: Vector3 = Vector3.ZERO
	var tilt_axis: Vector3 = Vector3.RIGHT
	var tilt: float = 0.0
	if slot > 0:
		var angle: float = TAU * float(slot - 1) / float(SLOT_COUNT - 1) + 0.4
		radial = Vector3(cos(angle), 0.0, sin(angle))
		tilt_axis = Vector3.UP.cross(radial).normalized()
		tilt = deg_to_rad(splay_degrees)
	var inner_r: float = outer_radius_meters - wall_meters - tool.radius_meters - 0.003
	var slot_r: float = minf(0.031, maxf(inner_r, 0.0)) if slot > 0 else 0.0
	var basis: Basis = Basis(tilt_axis, tilt) if tilt > 0.0 else Basis.IDENTITY
	var axis: Vector3 = basis * Vector3.UP
	var tip: Vector3 = global_position + radial * slot_r + Vector3.UP * (base_meters + 0.002)
	tool.global_transform = Transform3D(basis.rotated(Vector3.UP, float(slot) * 1.3), tip + axis * (tool.length_meters * 0.5))
	tool.linear_velocity = Vector3.ZERO
	tool.angular_velocity = Vector3.ZERO
	return true


## Forget tools that have been lifted out of the crock.
func _release_departed() -> void:
	for i: int in _slots.size():
		var tool: StirTool3D = _slots[i]
		if tool == null:
			continue
		if not is_instance_valid(tool) or not contains_xz(tool.global_position, 0.03) or tool.global_position.y > rim_y() + tool.length_meters * 0.5:
			_slots[i] = null
