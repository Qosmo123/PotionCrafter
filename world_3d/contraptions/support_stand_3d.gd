class_name SupportStand3D
extends StaticBody3D
## Supports for vessels that can't stand on their own:
##   CORK_RING:  a cork torus; collision is a ring of spheres that cradles a round bottom.
##   TUBE_RACK:  a wooden block with square sockets that hold test tubes upright.
##
## Every stand offers seats: a held vessel that fits (vials in racks, round
## flasks in rings) glides into the nearest free seat when let go nearby, and
## a soft glow marks the seats while a fitting vessel is in the hand.

##   PAD:        no model of its own: a flat seat on another device (stove
##               top, burner gauze, tap tray) so vessels glide onto it too.

enum Kind { CORK_RING, TUBE_RACK, PAD }

@export var pad_radius_meters: float = 0.05
## PAD only: also take round-bottom flasks (a burner gauze can hold one).
@export var accept_round: bool = false

static var all_stands: Array[SupportStand3D] = []
var _hints: Array[MeshInstance3D] = []
var _hint_time: float = 0.0

@export var kind: Kind = Kind.CORK_RING
@export var ring_radius_meters: float = 0.032
@export var ring_tube_radius_meters: float = 0.012
@export var socket_count: int = 3
@export var socket_size_meters: float = 0.044
@export var rack_height_meters: float = 0.05


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	match kind:
		Kind.CORK_RING:
			_build_cork_ring()
		Kind.TUBE_RACK:
			_build_tube_rack()
		Kind.PAD:
			pass
	all_stands.append(self)
	for i: int in seat_count():
		_hints.append(_make_hint(seat_floor_world(i)))


func _exit_tree() -> void:
	all_stands.erase(self)


# --- Seats ---------------------------------------------------------------------------

func seat_count() -> int:
	return socket_count if kind == Kind.TUBE_RACK else 1


## Centre of seat `i` at the height a vessel's underside comes to rest on.
func seat_floor_world(i: int) -> Vector3:
	if kind == Kind.TUBE_RACK:
		var length_m: float = socket_size_meters * float(socket_count) + 0.02
		return global_transform * Vector3(-length_m * 0.5 + 0.01 + (float(i) + 0.5) * socket_size_meters, 0.01, 0.0)
	if kind == Kind.PAD:
		return global_position
	return global_transform * Vector3(0.0, ring_tube_radius_meters * 2.0, 0.0)


## Height a vessel must clear before moving sideways into a seat.
func clear_top_y() -> float:
	if kind == Kind.PAD:
		return global_position.y
	return global_position.y + (rack_height_meters if kind == Kind.TUBE_RACK else ring_tube_radius_meters * 2.0)


## Vials go in racks, round-bottom flasks in cork rings.
func accepts(v: Vessel3D) -> bool:
	if v == null:
		return false
	var name_: String = v.profile.vessel_name if v.profile != null else ""
	if kind == Kind.TUBE_RACK:
		var r: float = v.profile.outer_radius_meters if v.profile != null else v.inner_radius_meters + v.wall_thickness_meters
		return name_ == "vial" or r < socket_size_meters * 0.5 - 0.002
	if kind == Kind.PAD:
		return name_ != "vial" and (accept_round or name_ != "round_flask")
	return name_ == "round_flask"


## True when no vessel (other than `ignore`) is standing in seat `i`.
func is_seat_free(i: int, ignore: Node = null) -> bool:
	var seat: Vector3 = seat_floor_world(i)
	var catch_r: float = socket_size_meters * 0.45 if kind == Kind.TUBE_RACK else ring_radius_meters + 0.02
	if kind == Kind.PAD:
		catch_r = pad_radius_meters
	for v: Vessel3D in Vessel3D.all_vessels:
		if v == ignore or not v.is_inside_tree():
			continue
		var p: Vector3 = v.global_position
		if Vector2(p.x - seat.x, p.z - seat.z).length() < catch_r and p.y > seat.y - 0.02 and p.y < seat.y + 0.2:
			return false
	return true


## The free seat nearest `x` (left/right only) that `v` fits, within `radius`.
## Returns {"stand", "index", "floor"} or an empty dictionary.
static func best_seat(v: Vessel3D, x: float, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = radius
	for stand: SupportStand3D in all_stands:
		if not stand.is_inside_tree() or not stand.accepts(v):
			continue
		for i: int in stand.seat_count():
			var floor_p: Vector3 = stand.seat_floor_world(i)
			var d: float = absf(floor_p.x - x)
			if d < best_d and stand.is_seat_free(i, v):
				best_d = d
				best = {"stand": stand, "index": i, "floor": floor_p}
	return best


## Show where `held` could go: free seats it fits glow softly, the chosen one
## brightly. Pass null to hide everything.
static func update_hints(held: Vessel3D, chosen: Dictionary, delta: float) -> void:
	for stand: SupportStand3D in all_stands:
		stand._hint_time += delta
		var fits: bool = held != null and stand.accepts(held)
		for i: int in stand._hints.size():
			var hint: MeshInstance3D = stand._hints[i]
			var on: bool = fits and stand.is_seat_free(i, held)
			hint.visible = on
			if on:
				var picked: bool = chosen.get("stand") == stand and int(chosen.get("index", -1)) == i
				var pulse: float = 0.5 + 0.5 * sin(stand._hint_time * 6.0)
				hint.transparency = lerpf(0.15, 0.0, pulse) if picked else 0.72
				hint.scale = Vector3.ONE * (1.25 + 0.15 * pulse if picked else 0.9)


func _make_hint(at: Vector3) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	quad.material = VesselEffects.billboard_material(true, 1.6, Color(1.0, 0.82, 0.42))
	var hint: MeshInstance3D = MeshInstance3D.new()
	hint.name = "SeatHint"
	hint.mesh = quad
	hint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hint.visible = false
	add_child(hint)
	hint.global_position = at + Vector3(0.0, 0.03, 0.03)
	return hint


func _build_cork_ring() -> void:
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = ring_radius_meters - ring_tube_radius_meters
	torus.outer_radius = ring_radius_meters + ring_tube_radius_meters
	torus.rings = 48
	torus.ring_segments = 16
	var cork: StandardMaterial3D = StandardMaterial3D.new()
	cork.albedo_color = Color(0.62, 0.45, 0.28)
	cork.roughness = 0.92
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = torus
	visual.material_override = cork
	visual.position.y = ring_tube_radius_meters
	add_child(visual)
	for i: int in 10:
		var angle: float = TAU * float(i) / 10.0
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = ring_tube_radius_meters
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.shape = sphere
		shape.position = Vector3(cos(angle) * ring_radius_meters, ring_tube_radius_meters, sin(angle) * ring_radius_meters)
		add_child(shape)


func _build_tube_rack() -> void:
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.28, 0.15)
	wood.roughness = 0.6
	var length_m: float = socket_size_meters * float(socket_count) + 0.02
	var wall_t: float = 0.006
	# Base plate.
	_add_box(Vector3(length_m, 0.01, socket_size_meters + 0.02), Vector3(0.0, 0.005, 0.0), wood)
	# Front and back rails.
	for z_sign: float in [-1.0, 1.0]:
		_add_box(Vector3(length_m, rack_height_meters, wall_t),
			Vector3(0.0, rack_height_meters * 0.5, z_sign * (socket_size_meters * 0.5 + wall_t * 0.5)), wood)
	# Dividers between sockets.
	for i: int in socket_count + 1:
		var x: float = -length_m * 0.5 + 0.01 + float(i) * socket_size_meters
		_add_box(Vector3(wall_t, rack_height_meters, socket_size_meters), Vector3(x, rack_height_meters * 0.5, 0.0), wood)


func _add_box(size: Vector3, center: Vector3, material: Material) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = center
	add_child(visual)
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	shape.position = center
	add_child(shape)
