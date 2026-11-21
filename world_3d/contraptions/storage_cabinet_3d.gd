class_name StorageCabinet3D
extends StaticBody3D
## A low wooden specimen cabinet in the Mineral Lab where finds and
## materials are put away (they go into the satchel's Finds and Materials).
##   Velvet tray (left of the top): drop a gem, mineral, fossil or polished
##   stone over it and it is stored. Plain rocks and sand bags go back to
##   their crates the same way.
##   Brass pan (right of the top): set a beaker or vial on it and its
##   contents (crushed powder, sifted sand, anything) are tipped into the
##   cabinet's jars and kept by weight; the empty glass stays on the pan.
## Drawers on the front are labelled; the caption says what's stored.

const WIDTH_METERS: float = 0.24
const HEIGHT_METERS: float = 0.13
const DEPTH_METERS: float = 0.16
## A vessel must rest on the pan this long before it is emptied.
const SETTLE_SECONDS: float = 0.6

var _pan: SupportStand3D
var _caption: Label3D
var _settle_s: float = 0.0
var _settle_vessel: Vessel3D = null
var _tick: int = 0


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	var wood: StandardMaterial3D = PropMaterials.textured("wood", Color(0.42, 0.26, 0.14), 0.3)
	var dark_wood: StandardMaterial3D = PropMaterials.textured("wood", Color(0.28, 0.17, 0.09), 0.3)
	var brass: StandardMaterial3D = PropMaterials.textured("metal", Color(0.88, 0.66, 0.3), 0.1, 0.9)
	var velvet: StandardMaterial3D = StandardMaterial3D.new()
	velvet.albedo_color = Color(0.32, 0.08, 0.14)
	velvet.roughness = 1.0
	var paper: StandardMaterial3D = StandardMaterial3D.new()
	paper.albedo_color = Color(0.9, 0.84, 0.68)
	paper.roughness = 0.9
	# Carcass (also the collision body).
	_box(Vector3(WIDTH_METERS, HEIGHT_METERS, DEPTH_METERS), Vector3(0.0, HEIGHT_METERS * 0.5, 0.0), wood, true)
	# Top moulding and plinth.
	_box(Vector3(WIDTH_METERS + 0.012, 0.008, DEPTH_METERS + 0.012), Vector3(0.0, HEIGHT_METERS + 0.004, 0.0), dark_wood, true)
	_box(Vector3(WIDTH_METERS + 0.008, 0.012, DEPTH_METERS + 0.008), Vector3(0.0, 0.006, 0.0), dark_wood, false)
	# Drawers: 2 rows x 3, each with a brass pull and a paper label.
	var labels: PackedStringArray = ["GEMS", "MINERALS", "FOSSILS", "POWDERS", "SANDS", "CUT"]
	var front: float = DEPTH_METERS * 0.5
	for row: int in 2:
		for col: int in 3:
			var cx: float = (float(col) - 1.0) * (WIDTH_METERS / 3.0)
			var cy: float = 0.03 + float(1 - row) * 0.048
			_box(Vector3(WIDTH_METERS / 3.0 - 0.008, 0.04, 0.006), Vector3(cx, cy + 0.006, front + 0.002), dark_wood, false)
			var pull: MeshInstance3D = MeshInstance3D.new()
			var pull_mesh: CylinderMesh = CylinderMesh.new()
			pull_mesh.top_radius = 0.004
			pull_mesh.bottom_radius = 0.004
			pull_mesh.height = 0.022
			pull_mesh.material = brass
			pull.mesh = pull_mesh
			pull.rotation.z = PI * 0.5
			pull.position = Vector3(cx, cy, front + 0.009)
			add_child(pull)
			_box(Vector3(0.062, 0.014, 0.001), Vector3(cx, cy + 0.014, front + 0.0055), paper, false)
			var text: Label3D = Label3D.new()
			text.text = labels[row * 3 + col]
			text.font_size = 48
			text.pixel_size = 0.00017
			text.outline_size = 0
			text.modulate = Color(0.2, 0.12, 0.06)
			text.position = Vector3(cx, cy + 0.014, front + 0.0062)
			add_child(text)
	# Velvet tray on the left of the top.
	var top: float = HEIGHT_METERS + 0.008
	_box(Vector3(0.1, 0.004, 0.11), Vector3(-0.055, top + 0.002, 0.0), velvet, false)
	for side: Vector4 in [Vector4(-0.105, 0.0, 0.006, 0.12), Vector4(-0.005, 0.0, 0.006, 0.12), Vector4(-0.055, -0.058, 0.106, 0.006), Vector4(-0.055, 0.058, 0.106, 0.006)]:
		_box(Vector3(side.z, 0.016, side.w), Vector3(side.x, top + 0.008, side.y), dark_wood, true)
	# Brass pan on the right: a seat vessels glide onto.
	var pan_mesh: CylinderMesh = CylinderMesh.new()
	pan_mesh.top_radius = 0.045
	pan_mesh.bottom_radius = 0.04
	pan_mesh.height = 0.006
	pan_mesh.material = brass
	var pan_mi: MeshInstance3D = MeshInstance3D.new()
	pan_mi.mesh = pan_mesh
	pan_mi.position = Vector3(0.058, top + 0.003, 0.0)
	add_child(pan_mi)
	_box(Vector3(0.09, 0.006, 0.09), Vector3(0.058, top + 0.003, 0.0), brass, true, false)
	_pan = SupportStand3D.new()
	_pan.kind = SupportStand3D.Kind.PAD
	_pan.pad_radius_meters = 0.045
	_pan.accept_round = false
	_pan.seat_name = "storage pan"
	_pan.position = Vector3(0.058, top + 0.006, 0.0)
	add_child(_pan)
	# Finds dropped over the tray are put away.
	var tray: MachineIntake = MachineIntake.make(self, "storage cabinet", Vector3(0.12, 0.3, 0.5), Vector3(-0.055, top + 0.2, 0.0),
		Vector3(-0.055, top + 0.02, 0.0), _takes)
	tray.on_catch = _store_rock
	tray.wants = "stones and gems (set beakers of powder on its brass pan)"
	_caption = ClickSwitch.make_caption(self, Vector3(0.0, HEIGHT_METERS + 0.1, 0.05))
	_update_caption()


func _box(size: Vector3, center: Vector3, mat: Material, solid: bool, visible_: bool = true) -> void:
	if visible_:
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = size
		mesh.material = mat
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = center
		add_child(mi)
	if solid:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		var cs: CollisionShape3D = CollisionShape3D.new()
		cs.shape = shape
		cs.position = center
		add_child(cs)


func _takes(b: Node) -> bool:
	return b is Rock3D and (b as Rock3D).mineral != null


func _store_rock(body: RigidBody3D) -> void:
	var store: InventoryStore = InventoryStore.instance
	var rock: Rock3D = body as Rock3D
	if store == null or rock == null:
		return
	var find: bool = InventoryStore.is_find(rock)
	if not store.stash(rock):
		return
	AudioDirector.play(&"click", global_position, -8.0, 0.8)
	_toast(store.last_message.replace("Stored: ", "Put away: ") + ("" if find else "  (back in the Rocks tab)"))
	_update_caption()


func _physics_process(delta: float) -> void:
	_tick += 1
	if _tick % 6 != 0:
		return
	if _tick % 60 == 0:
		_update_caption()
	var step: float = delta * 6.0
	var on_pan: Vessel3D = null
	var seat: Vector3 = _pan.global_position
	for v: Vessel3D in Vessel3D.all_vessels:
		if v == TactileGrabber3D.current_held or not v.is_inside_tree() or v.mixture == null:
			continue
		var p: Vector3 = v.global_position
		if Vector2(p.x - seat.x, p.z - seat.z).length() < 0.045 and p.y > seat.y - 0.01 and p.y < seat.y + 0.2:
			on_pan = v
			break
	if on_pan != _settle_vessel:
		_settle_vessel = on_pan
		_settle_s = 0.0
	if on_pan == null or on_pan.mixture.get_total_mass_kg() < InventoryStore.MATERIAL_MIN_KG:
		return
	_settle_s += step
	if _settle_s < SETTLE_SECONDS or on_pan.linear_velocity.length() > 0.05:
		return
	var store: InventoryStore = InventoryStore.instance
	if store == null:
		return
	var kept: String = store.store_contents(on_pan)
	if kept != "":
		AudioDirector.play(&"sand_pour", global_position, -8.0)
		_toast("Stored in the cabinet: %s  ·  take it out from Materials in the satchel" % kept)
		_update_caption()
	_settle_s = 0.0


func _toast(text: String) -> void:
	if GrimoireJournal.instance != null:
		GrimoireJournal.instance.toast.emit(text, &"bottle")


func _update_caption() -> void:
	var finds: int = 0
	var mats: int = 0
	if InventoryStore.instance != null:
		for item: Dictionary in InventoryStore.instance.get_items(InventoryStore.Category.FINDS):
			finds += int(item["count"])
		mats = InventoryStore.instance.get_items(InventoryStore.Category.MATERIALS).size()
	_caption.text = "Storage Cabinet\n%d finds · %d materials" % [finds, mats]


## Short hover text.
func hover_info() -> String:
	return "[b]Storage Cabinet[/b]  [color=#B3ADD6]drop gems and stones on the velvet tray; set a beaker of powder on the brass pan. Take them out from the satchel (Finds, Materials)[/color]"
