class_name TradersScale3D
extends StaticBody3D
## A brass trader's balance in the Mineral Lab. Set a gem, mineral, fossil or
## polished stone on its left pan and the caption reads its price
## (Rock3D.value(): size, polish and cut); click the brass bell on the base to
## sell it, and the coins go straight into the purse. A stone on the pan can
## simply be picked up again, so nothing is sold by surprise. Plain rough
## rocks are pushed back off. The beam dips under the sale and swings back.

const BASE_SIZE: Vector3 = Vector3(0.2, 0.02, 0.12)
const POST_HEIGHT_METERS: float = 0.2
const BEAM_HALF_METERS: float = 0.08
const PAN_DROP_METERS: float = 0.1

static var instance: TradersScale3D = null

var sold_count: int = 0
var sold_coins: int = 0

var _beam: Node3D
var _pans: Array[Node3D] = []
var _intake: MachineIntake
var _bell: StaticBody3D
var _pan_top_local: Vector3
var _caption: WorldPill
var _tilt: float = 0.0
var _tilt_vel: float = 0.0
var _tick: int = 0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	var wood: StandardMaterial3D = PropMaterials.textured("wood", Color(0.3, 0.18, 0.1), 0.3)
	var brass: StandardMaterial3D = PropMaterials.textured("metal", Color(0.9, 0.68, 0.3), 0.15, 0.9)
	var dark_brass: StandardMaterial3D = PropMaterials.textured("metal", Color(0.6, 0.42, 0.18), 0.25, 0.9)
	# Wooden base (solid) and brass post.
	_box(BASE_SIZE, Vector3(0.0, BASE_SIZE.y * 0.5, 0.0), wood, true)
	var post_at: Vector3 = Vector3(0.0, BASE_SIZE.y + POST_HEIGHT_METERS * 0.5, -0.03)
	_cylinder(0.008, 0.01, POST_HEIGHT_METERS, post_at, brass)
	_solid(Vector3(0.02, POST_HEIGHT_METERS, 0.02), post_at)
	var knob: MeshInstance3D = MeshInstance3D.new()
	var knob_mesh: SphereMesh = SphereMesh.new()
	knob_mesh.radius = 0.012
	knob_mesh.height = 0.024
	knob_mesh.material = brass
	knob.mesh = knob_mesh
	knob.position = Vector3(0.0, BASE_SIZE.y + POST_HEIGHT_METERS + 0.02, -0.03)
	add_child(knob)
	# The beam pivots on the post; pans hang from its ends and stay level.
	_beam = Node3D.new()
	_beam.position = Vector3(0.0, BASE_SIZE.y + POST_HEIGHT_METERS, -0.03)
	add_child(_beam)
	var beam_mesh: BoxMesh = BoxMesh.new()
	beam_mesh.size = Vector3(BEAM_HALF_METERS * 2.0 + 0.01, 0.007, 0.007)
	beam_mesh.material = brass
	var beam_mi: MeshInstance3D = MeshInstance3D.new()
	beam_mi.mesh = beam_mesh
	_beam.add_child(beam_mi)
	for side: float in [-1.0, 1.0]:
		var pan: Node3D = Node3D.new()
		_beam.add_child(pan)
		pan.position = Vector3(side * BEAM_HALF_METERS, 0.0, 0.03)
		for k: int in 3:
			var a: float = TAU * float(k) / 3.0
			var foot: Vector3 = Vector3(cos(a) * 0.03, -PAN_DROP_METERS, sin(a) * 0.03)
			var chain: MeshInstance3D = MeshInstance3D.new()
			var chain_mesh: CylinderMesh = CylinderMesh.new()
			chain_mesh.top_radius = 0.0012
			chain_mesh.bottom_radius = 0.0012
			chain_mesh.height = foot.length()
			chain_mesh.material = dark_brass
			chain.mesh = chain_mesh
			chain.position = foot * 0.5
			chain.basis = Basis(Quaternion(Vector3.UP, -foot.normalized()))
			pan.add_child(chain)
		var dish: MeshInstance3D = MeshInstance3D.new()
		var dish_mesh: CylinderMesh = CylinderMesh.new()
		dish_mesh.top_radius = 0.042
		dish_mesh.bottom_radius = 0.032
		dish_mesh.height = 0.008
		dish_mesh.material = brass
		dish.mesh = dish_mesh
		dish.position = Vector3(0.0, -PAN_DROP_METERS, 0.0)
		pan.add_child(dish)
		_pans.append(pan)
	# A little stack of brass weights on the right pan.
	for i: int in 3:
		_cylinder(0.014 - i * 0.003, 0.014 - i * 0.003, 0.008, Vector3(0.0, -PAN_DROP_METERS + 0.008 + i * 0.008, 0.0), dark_brass, _pans[1])
	# The left pan is a small solid seat; stones let go over it are set on it.
	var left_pan_local: Vector3 = _beam.position + Vector3(-BEAM_HALF_METERS, -PAN_DROP_METERS, 0.03)
	_pan_top_local = left_pan_local + Vector3(0.0, 0.004, 0.0)
	_solid(Vector3(0.09, 0.008, 0.09), left_pan_local)
	_intake = MachineIntake.make(self, "trader's scale", Vector3(0.07, 0.34, 0.5), left_pan_local + Vector3(0.0, 0.16, 0.0),
		_pan_top_local + Vector3(0.0, 0.03, 0.0), _takes)
	_intake.catch_dx_meters = 0.045
	_intake.on_catch = _set_on_pan
	_intake.wants = "gems, minerals, fossils and polished stones"
	_intake.drop_note = "Click to set it on the trader's scale (then click its bell to sell)"
	_intake.marker_text = func(b: Node) -> String: return ("worth %d ◉" % (b as Rock3D).value()) if b is Rock3D else ""
	# The bell on the base: a click sells what is on the pan.
	var bell_at: Vector3 = Vector3(0.06, BASE_SIZE.y + 0.011, 0.03)
	_cylinder(0.004, 0.018, 0.022, bell_at, brass)
	_cylinder(0.004, 0.004, 0.01, bell_at + Vector3(0.0, 0.015, 0.0), dark_brass)
	_bell = ClickSwitch.make_button(self, Vector3(0.05, 0.05, 0.05), bell_at + Vector3(0.0, 0.01, 0.0))
	_caption = ClickSwitch.make_caption(self, Vector3(0.0, BASE_SIZE.y + POST_HEIGHT_METERS + 0.09, 0.05))
	_caption.busy = func() -> bool: return not on_pan().is_empty()
	_update_caption()


func _box(size: Vector3, center: Vector3, mat: Material, solid: bool) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center
	add_child(mi)
	if solid:
		_solid(size, center)


func _solid(size: Vector3, center: Vector3) -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	add_child(cs)


func _cylinder(top: float, bottom: float, height: float, at: Vector3, mat: Material, parent: Node3D = null) -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	(parent if parent != null else self).add_child(mi)


func _takes(b: Node) -> bool:
	return b is Rock3D and InventoryStore.is_find(b as Rock3D)


func pan_world() -> Vector3:
	return global_transform * _pan_top_local


func _resting_on_pan(rock: Rock3D) -> bool:
	var p: Vector3 = pan_world()
	var at: Vector3 = rock.global_position
	return Vector2(at.x - p.x, at.z - p.z).length() < 0.05 and at.y > p.y - 0.01 and at.y < p.y + 0.1


## Set a stone that was let go over the scale onto the left pan.
func _set_on_pan(body: RigidBody3D) -> void:
	var rock: Rock3D = body as Rock3D
	if rock == null or _resting_on_pan(rock):
		return
	var p: Vector3 = pan_world()
	rock.global_position = p + Vector3(0.0, 0.03, 0.0)
	rock.linear_velocity = Vector3(0.0, -0.1, 0.0)
	rock.angular_velocity = Vector3.ZERO
	AudioDirector.impact(&"iron", 0.4, p, 1.2)
	_tilt_vel -= 0.6


## Finds resting on the left pan (not the one in the hand).
func on_pan() -> Array[Rock3D]:
	var out: Array[Rock3D] = []
	if _intake == null:
		return out
	for body: Node3D in _intake.get_overlapping_bodies():
		var rock: Rock3D = body as Rock3D
		if rock == null or rock == TactileGrabber3D.current_held or rock.is_queued_for_deletion() or not _takes(rock):
			continue
		if _resting_on_pan(rock):
			out.append(rock)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if ClickSwitch.clicked(self, event, [_bell]) != null:
		get_viewport().set_input_as_handled()
		sell_pan()


## Ring the bell: sell everything on the pan. Returns the coins paid.
func sell_pan() -> int:
	AudioDirector.play(&"arcane_chime", global_position, -10.0, 1.6)
	var total: int = 0
	for rock: Rock3D in on_pan():
		total += sell(rock)
	if total == 0 and GrimoireJournal.instance != null:
		GrimoireJournal.instance.toast.emit("Set a gem, mineral, fossil or polished stone on the scale's pan first", &"info")
	return total


## Sell a find for its value. Returns the coins paid (0 if it can't be sold).
func sell(rock: Rock3D) -> int:
	var journal: GrimoireJournal = GrimoireJournal.instance
	if rock == null or rock.is_queued_for_deletion() or not _takes(rock) or journal == null:
		return 0
	var price: int = maxi(rock.value(), 1)
	var name_: String = rock.describe_name()
	if TactileGrabber3D.current_held == rock and InventoryStore.instance != null and InventoryStore.instance.grabber != null:
		InventoryStore.instance.grabber.release()
	rock.queue_free()
	journal.coins += price
	journal._save()
	journal.changed.emit()
	sold_count += 1
	sold_coins += price
	_tilt_vel -= 2.2 + minf(float(price) / 60.0, 2.0)
	journal.toast.emit("Sold: %s  +%d ◉" % [name_, price], &"coins")
	return price


func _physics_process(delta: float) -> void:
	# Damped swing back to level; the pans hang plumb.
	_tilt_vel += (-_tilt * 40.0 - _tilt_vel * 5.0) * delta
	_tilt = clampf(_tilt + _tilt_vel * delta, -0.35, 0.35)
	if absf(_tilt) > 1e-4 or absf(_tilt_vel) > 1e-4:
		_beam.rotation.z = -_tilt
		for pan: Node3D in _pans:
			pan.rotation.z = _tilt


func _process(_delta: float) -> void:
	_tick += 1
	if _tick % 15 == 0:
		_update_caption()


func _pan_total(stones: Array[Rock3D]) -> int:
	var sum: int = 0
	for r: Rock3D in stones:
		sum += r.value()
	return sum


func _update_caption() -> void:
	var stones: Array[Rock3D] = on_pan()
	var text: String
	if stones.size() == 1:
		text = "%s · %d ◉\nclick the bell to sell" % [stones[0].describe_name(), stones[0].value()]
	elif stones.size() > 1:
		text = "%d stones · %d ◉\nclick the bell to sell" % [stones.size(), _pan_total(stones)]
	else:
		text = "Trader's Scale\n" + (("sold %d · +%d ◉" % [sold_count, sold_coins]) if sold_count > 0 else "set a find on the pan")
	if _caption.text != text:
		_caption.text = text


## Short hover text.
func hover_info() -> String:
	var stones: Array[Rock3D] = on_pan()
	if not stones.is_empty():
		return "[b]Trader's Scale[/b]  [color=#F2D27A]%d ◉ on the pan[/color]  [color=#B3ADD6]click the brass bell to sell, or pick the stone back up[/color]" % _pan_total(stones)
	return "[b]Trader's Scale[/b]  [color=#B3ADD6]set a gem, mineral, fossil or polished stone on the left pan, then click the brass bell to sell it. Cut and polished stones fetch more[/color]"
