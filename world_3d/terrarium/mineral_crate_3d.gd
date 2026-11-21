class_name MineralCrate3D
extends StaticBody3D
## Open wooden crate with hollow collision (walls + floor), stocked on load
## with collectible rocks or sand bags.

@export var model: PackedScene
@export var size_meters: Vector3 = Vector3(0.26, 0.08, 0.18)
@export var stock: PackedStringArray = PackedStringArray()
## Extra random specimens drawn from the encyclopedia, weighted by rarity
## (Common is ~30x likelier than Legendary). Kinds: MineralData.Kind values.
@export var random_count: int = 0
@export var random_kinds: PackedInt32Array = PackedInt32Array()
## Seconds between restocks while the crate is running low (0 = never).
@export var restock_seconds: float = 20.0

const RARITY_WEIGHTS: PackedFloat32Array = [1.0, 0.45, 0.18, 0.07, 0.03]

var _restock_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	if model != null:
		var visual: Node3D = model.instantiate() as Node3D
		add_child(visual)
		PropMaterials.apply(visual)
	var w: float = 0.012
	_box(Vector3(size_meters.x, 0.01, size_meters.z), Vector3(0.0, 0.005, 0.0))
	for sy: float in [-1.0, 1.0]:
		_box(Vector3(size_meters.x, size_meters.y, w), Vector3(0.0, size_meters.y * 0.5, sy * (size_meters.z * 0.5)))
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(w, size_meters.y, size_meters.z), Vector3(sx * (size_meters.x * 0.5), size_meters.y * 0.5, 0.0))
	_rng.randomize()
	_fill.call_deferred()


func _box(size: Vector3, center: Vector3) -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	add_child(cs)


func _fill() -> void:
	var cols: int = 4
	for i: int in stock.size():
		var m: MineralData = Rock3D.get_mineral(stock[i])
		if m == null:
			continue
		var cx: float = (float(i % cols) - (cols - 1) * 0.5) * (size_meters.x / float(cols)) * 0.9
		var cz: float = (float(i / cols % 2) - 0.5) * size_meters.z * 0.45
		var layer: int = i / (cols * 2)
		Rock3D.spawn(get_parent(), m, global_transform * Vector3(cx, 0.04 + float(layer) * 0.06, cz), m.typical_mass_kg)
	for i: int in random_count:
		_spawn_random(i)


func _spawn_random(slot: int) -> void:
	var m: MineralData = pick_random(_rng, random_kinds)
	if m == null:
		return
	var cx: float = _rng.randf_range(-0.4, 0.4) * size_meters.x
	var cz: float = _rng.randf_range(-0.3, 0.3) * size_meters.z
	Rock3D.spawn(get_parent(), m, global_transform * Vector3(cx, 0.05 + float(slot % 3) * 0.03, cz), m.typical_mass_kg * _rng.randf_range(0.7, 1.3))


## Rarity-weighted draw from every mineral of the given kinds.
static func pick_random(rng: RandomNumberGenerator, kinds: PackedInt32Array) -> MineralData:
	var total: float = 0.0
	var pool: Array[MineralData] = []
	for m: MineralData in Rock3D.registry().values():
		if kinds.is_empty() or kinds.has(int(m.kind)):
			pool.append(m)
			total += RARITY_WEIGHTS[clampi(m.rarity, 0, 4)]
	var pick: float = rng.randf() * total
	for m: MineralData in pool:
		pick -= RARITY_WEIGHTS[clampi(m.rarity, 0, 4)]
		if pick <= 0.0:
			return m
	return pool.back() if not pool.is_empty() else null


func _physics_process(delta: float) -> void:
	if restock_seconds <= 0.0 or (random_count <= 0 and stock.is_empty()):
		return
	_restock_timer += delta
	if _restock_timer < restock_seconds:
		return
	_restock_timer = 0.0
	var inside: int = 0
	var to_local_xf: Transform3D = global_transform.affine_inverse()
	for node: Node in get_tree().get_nodes_in_group(&"collectibles"):
		var p: Vector3 = to_local_xf * (node as Node3D).global_position
		if absf(p.x) < size_meters.x * 0.6 and absf(p.z) < size_meters.z * 0.6 and p.y > -0.02 and p.y < 0.2:
			inside += 1
	var target: int = maxi(stock.size() + random_count, 1)
	if inside < target / 2:
		if random_count > 0:
			_spawn_random(inside)
		else:
			var m: MineralData = Rock3D.get_mineral(stock[_rng.randi() % stock.size()])
			if m != null:
				Rock3D.spawn(get_parent(), m, global_transform * Vector3(0.0, 0.06, 0.0), m.typical_mass_kg)
