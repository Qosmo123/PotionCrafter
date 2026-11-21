class_name AutoBoxCollider
extends StaticBody3D
## Static prop wrapper: fits one BoxShape3D around all child meshes on ready.
## Good enough for furniture, stands and tool clutter that vessels may bump into.

func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	PropMaterials.apply(self)
	var bounds: AABB = AABB()
	var first: bool = true
	var inv: Transform3D = global_transform.affine_inverse()
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		var local_xf: Transform3D = inv * mi.global_transform
		var box: AABB = local_xf * mi.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		return
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = bounds.size
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	collider.position = bounds.get_center()
	add_child(collider)
