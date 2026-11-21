class_name AnvilLoader
extends RefCounted
## "Load Next Rock": lobs the next uncracked rock from the Rock Crate onto the
## anvil in a real ballistic arc (no teleporting), so cracking can be chained
## smoothly. If the crate is empty, a fresh rock comes out of the satchel.

const FLIGHT_SECONDS: float = 0.55
const CLEAR_RADIUS_METERS: float = 0.09


## Returns a message for the player ("" on success).
static func load_next(context: Node) -> String:
	var tree: SceneTree = context.get_tree()
	var anvil: Node3D = tree.get_first_node_in_group(&"anvil") as Node3D
	if anvil == null:
		return "There is no anvil here"
	var top: Vector3 = anvil_top(anvil)
	for body: Node in tree.get_nodes_in_group(&"collectibles"):
		var rock: Rock3D = body as Rock3D
		if rock != null and rock.mineral != null and not rock.exhausted and rock.cut == RockMeshes.Cut.NONE \
				and rock.mineral.kind != MineralData.Kind.SAND and rock.global_position.distance_to(top) < CLEAR_RADIUS_METERS:
			return "%s is already on the anvil: give it a whack!" % rock.mineral.display_name
	var next: Rock3D = _next_from_crates(tree, top)
	if next != null:
		toss(next, top + Vector3(0.0, 0.03, 0.0))
		return ""
	if InventoryStore.instance != null:
		var ids: Array[String] = []
		for item: Dictionary in InventoryStore.instance.get_items(InventoryStore.Category.ROCKS):
			var m: MineralData = item.get("mineral") as MineralData
			if m != null and m.kind == MineralData.Kind.ROCK and not m.inclusions.is_empty():
				ids.append(String(item["id"]))
		if not ids.is_empty() and InventoryStore.instance.take(ids[randi() % ids.size()], top) != null:
			return ""
	return "The rock crate is empty: wait for a restock or take rocks from the satchel"


## Top surface of the anvil, found by a downward ray onto it.
static func anvil_top(anvil: Node3D) -> Vector3:
	var space: PhysicsDirectSpaceState3D = anvil.get_world_3d().direct_space_state
	var from: Vector3 = anvil.global_position + Vector3(0.0, 0.6, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, anvil.global_position - Vector3(0.0, 0.1, 0.0), SimConstants.LAYER_STATIC_BENCH)
	var hit: Dictionary = space.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else anvil.global_position + Vector3(0.0, 0.1, 0.0)


## Rocks waiting in a crate, nearest crate rock to the anvil first. Geodes and
## other rocks with hidden finds are preferred: that's the fun part.
static func _next_from_crates(tree: SceneTree, top: Vector3) -> Rock3D:
	var best: Rock3D = null
	var best_score: float = INF
	for crate_node: Node in tree.get_nodes_in_group(&"mineral_crates"):
		var crate: MineralCrate3D = crate_node as MineralCrate3D
		if crate == null:
			continue
		var half: Vector3 = crate.size_meters * 0.5 + Vector3(0.01, 0.1, 0.01)
		for body: Node in tree.get_nodes_in_group(&"collectibles"):
			var rock: Rock3D = body as Rock3D
			if rock == null or rock.mineral == null or rock.exhausted or rock.mineral.kind != MineralData.Kind.ROCK:
				continue
			var local: Vector3 = crate.global_transform.affine_inverse() * rock.global_position
			if absf(local.x) > half.x or local.y < -0.02 or local.y > half.y * 2.0 or absf(local.z) > half.z:
				continue
			var score: float = rock.global_position.distance_to(top) - (0.5 if not rock.mineral.inclusions.is_empty() else 0.0)
			if score < best_score:
				best = rock
				best_score = score
	return best


## Launch velocity for a ballistic hop from the body's position to `target`
## in FLIGHT_SECONDS: v = d/t + ½·g·t (upward), so physics carries it there.
static func toss_velocity(from: Vector3, target: Vector3, gravity_m_s2: float = SimConstants.GRAVITY_M_S2) -> Vector3:
	var t: float = FLIGHT_SECONDS
	var d: Vector3 = target - from
	return Vector3(d.x / t, d.y / t + 0.5 * gravity_m_s2 * t, d.z / t)


static func toss(rock: Rock3D, target: Vector3) -> void:
	rock.sleeping = false
	rock.linear_velocity = toss_velocity(rock.global_position, target)
	rock.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
