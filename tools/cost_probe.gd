extends Node
## Per-script cost table. Run:  godot --path . -- cost
## After warm-up, calls every scripted node's _process / _physics_process a
## few times, times them, and prints the total cost per script, worst first.

const WARMUP_FRAMES: int = 60
const REPEATS: int = 5

var _frame: int = 0


func _process(_delta: float) -> void:
	_frame += 1
	if _frame != WARMUP_FRAMES:
		return
	var proc: Dictionary = {}
	var phys: Dictionary = {}
	var counts: Dictionary = {}
	_walk(get_tree().root, proc, phys, counts)
	print("COST  scripts by _physics_process (ms per tick, all instances):")
	_print_sorted(phys, counts)
	print("COST  scripts by _process (ms per frame, all instances):")
	_print_sorted(proc, counts)
	print("COST  nodes in tree: %d" % get_tree().get_node_count())
	triangle_report(get_tree().current_scene)
	for v: Vessel3D in Vessel3D.all_vessels:
		if v.mixture != null and v.mixture.get_liquid_volume_m3() > 1e-6:
			print("COST  breakdown for %s:" % v.name)
			vessel_breakdown(v)
			break
	get_tree().quit()


func _walk(n: Node, proc: Dictionary, phys: Dictionary, counts: Dictionary) -> void:
	for c: Node in n.get_children():
		_walk(c, proc, phys, counts)
	if n == self:
		return
	var script: Script = n.get_script() as Script
	if script == null:
		return
	var key: String = script.resource_path.get_file()
	counts[key] = int(counts.get(key, 0)) + 1
	if n.is_physics_processing() and n.has_method(&"_physics_process"):
		var t0: int = Time.get_ticks_usec()
		for i: int in REPEATS:
			n.call(&"_physics_process", 1.0 / 60.0)
		phys[key] = float(phys.get(key, 0.0)) + float(Time.get_ticks_usec() - t0) / 1000.0 / REPEATS
	if n.is_processing() and n.has_method(&"_process"):
		var t1: int = Time.get_ticks_usec()
		for i: int in REPEATS:
			n.call(&"_process", 1.0 / 60.0)
		proc[key] = float(proc.get(key, 0.0)) + float(Time.get_ticks_usec() - t1) / 1000.0 / REPEATS


func _print_sorted(costs: Dictionary, counts: Dictionary) -> void:
	var keys: Array = costs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return costs[a] > costs[b])
	for k: String in keys.slice(0, 14):
		print("COST    %-34s %7.3f ms   (%d nodes)" % [k, costs[k], counts.get(k, 0)])


## Breakdown of one vessel's tick, by sub-step (ms per call, averaged).
static func vessel_breakdown(v: Vessel3D) -> void:
	var steps: Array = [
		["step_reactions", func() -> void: v.mixture.step_reactions(1.0 / 60.0, 0.0, v.open_top, false)],
		["step_thermal", func() -> void: v.mixture.step_thermal(1.0 / 60.0, SimConstants.AMBIENT_TEMP_KELVIN, v.ambient_conductance_w_k)],
		["vent_gas", func() -> void: v.mixture.vent_gas(1.0)],
		["_spill_overflow", func() -> void: v.call(&"_spill_overflow")],
		["_update_fill_state", func() -> void: v.call(&"_update_fill_state")],
		["_update_slosh", func() -> void: v.call(&"_update_slosh", 1.0 / 60.0)],
		["_update_foam_and_bubbles", func() -> void: v.call(&"_update_foam_and_bubbles", 1.0 / 60.0)],
		["_update_pouring", func() -> void: v.call(&"_update_pouring", 1.0 / 60.0)],
		["_update_mass_properties", func() -> void: v.call(&"_update_mass_properties")],
		["_update_layers_state", func() -> void: v.call(&"_update_layers_state", 1.0 / 60.0)],
		["effects.update_effects", func() -> void: v.get(&"_effects").update_effects(v, v.global_position, v.get_surface_point_world(), 0.02, 0.0)],
		["_update_liquid_visual", func() -> void: v.call(&"_update_liquid_visual")],
	]
	for s: Array in steps:
		var t0: int = Time.get_ticks_usec()
		for i: int in 20:
			(s[1] as Callable).call()
		print("COST      %-26s %7.3f ms" % [s[0], float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0])


## Triangle budget by mesh (visible MeshInstance3D + MultiMesh), worst first.
static func triangle_report(root: Node) -> void:
	var tris: Dictionary = {}
	var inst: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mesh: Mesh = null
		var mult: int = 1
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree():
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).is_visible_in_tree() and (n as MultiMeshInstance3D).multimesh != null:
			mesh = (n as MultiMeshInstance3D).multimesh.mesh
			mult = (n as MultiMeshInstance3D).multimesh.visible_instance_count
			if mult < 0:
				mult = (n as MultiMeshInstance3D).multimesh.instance_count
		if mesh == null:
			continue
		var t: int = 0
		for si: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(si)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			t += (idx.size() if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var key: String = "%s [%s]" % [mesh.resource_path.get_file() if mesh.resource_path != "" else mesh.get_class(), String(n.name).left(24)]
		key = key if mesh.resource_path != "" else "%s (%s)" % [mesh.get_class(), String(n.get_parent().name).left(20)]
		tris[key] = int(tris.get(key, 0)) + t * mult
		inst[key] = int(inst.get(key, 0)) + 1
	var keys: Array = tris.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return tris[a] > tris[b])
	var total: int = 0
	for k: String in keys:
		total += tris[k]
	print("TRIS  total %dk" % (total / 1000))
	for k: String in keys.slice(0, 22):
		print("TRIS    %-58s %6dk  x%d" % [k, tris[k] / 1000, inst[k]])
