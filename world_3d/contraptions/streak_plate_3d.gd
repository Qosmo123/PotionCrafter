class_name StreakPlate3D
extends StaticBody3D
## Unglazed white porcelain streak plate, a real field-geology test. Rub a
## mineral across it (hold it with the grabber and drag) and it leaves a line
## of its powder: the *streak* colour, which is often surprising (shiny grey
## hematite streaks cherry red, brassy pyrite streaks greenish black). The
## plate is about Mohs 6.5, so harder minerals just skate over it and leave
## no streak.

const PLATE_HARDNESS_MOHS: float = 6.5
const TEX_W: int = 256
const TEX_H: int = 128
const UPLOAD_INTERVAL_S: float = 0.08

@export var size_meters: Vector2 = Vector2(0.16, 0.08)
@export var thickness_meters: float = 0.008

var _image: Image
var _texture: ImageTexture
var _area: Area3D
var _dirty: bool = false
var _upload_timer: float = 0.0
var _last_rock: Rock3D = null
var _rub_distance_m: float = 0.0
var _announced: bool = false
var _last_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	_image = Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0.95, 0.94, 0.9))
	_texture = ImageTexture.create_from_image(_image)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = _texture
	mat.roughness = 0.85
	var tile: BoxMesh = BoxMesh.new()
	tile.size = Vector3(size_meters.x, thickness_meters, size_meters.y)
	tile.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = tile
	mi.position.y = thickness_meters * 0.5
	add_child(mi)
	# The unglazed tile sits in a low wooden tray.
	var wood: StandardMaterial3D = PropMaterials.textured("wood", Color(0.36, 0.23, 0.13), 0.15)
	var rim: float = 0.007
	var rail_h: float = thickness_meters + 0.003
	for side: Array in [
			[Vector3(size_meters.x + rim * 2.0, rail_h, rim), Vector3(0.0, rail_h * 0.5, size_meters.y * 0.5 + rim * 0.5)],
			[Vector3(size_meters.x + rim * 2.0, rail_h, rim), Vector3(0.0, rail_h * 0.5, -size_meters.y * 0.5 - rim * 0.5)],
			[Vector3(rim, rail_h, size_meters.y), Vector3(size_meters.x * 0.5 + rim * 0.5, rail_h * 0.5, 0.0)],
			[Vector3(rim, rail_h, size_meters.y), Vector3(-size_meters.x * 0.5 - rim * 0.5, rail_h * 0.5, 0.0)]]:
		var rail: BoxMesh = BoxMesh.new()
		rail.size = side[0]
		rail.material = wood
		var rail_mi: MeshInstance3D = MeshInstance3D.new()
		rail_mi.mesh = rail
		rail_mi.position = side[1]
		add_child(rail_mi)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = tile.size
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = thickness_meters * 0.5
	add_child(cs)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = SimConstants.LAYER_SOLID_REAGENT
	_area.monitorable = false
	var probe: BoxShape3D = BoxShape3D.new()
	probe.size = Vector3(size_meters.x, 0.012, size_meters.y)
	var pc: CollisionShape3D = CollisionShape3D.new()
	pc.shape = probe
	_area.add_child(pc)
	_area.position.y = thickness_meters + 0.006
	add_child(_area)
	var label: Label3D = Label3D.new()
	label.text = "Streak Plate\nrub a mineral across it"
	label.font_size = 28
	label.pixel_size = 0.0004
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 0.06, 0.0)
	add_child(label)


func _physics_process(delta: float) -> void:
	var rock: Rock3D = null
	for body: Node3D in _area.get_overlapping_bodies():
		var r: Rock3D = body as Rock3D
		if r != null and r.mineral != null and r.mineral.kind != MineralData.Kind.SAND:
			rock = r
			break
	if rock != _last_rock:
		_last_rock = rock
		_rub_distance_m = 0.0
		_announced = false
		if rock != null:
			_last_pos = rock.global_position
	if rock != null:
		var moved: float = (rock.global_position - _last_pos).length()
		_last_pos = rock.global_position
		if moved > 0.0005:
			_rub_distance_m += moved
			_paint(rock)
			if not _announced and _rub_distance_m > 0.04:
				_announced = true
				_announce(rock.mineral)
	_upload_timer -= delta
	if _dirty and _upload_timer <= 0.0:
		_texture.update(_image)
		_dirty = false
		_upload_timer = UPLOAD_INTERVAL_S


func _paint(rock: Rock3D) -> void:
	var m: MineralData = rock.mineral
	var local: Vector3 = to_local(rock.global_position)
	var u: float = local.x / size_meters.x + 0.5
	var v: float = local.z / size_meters.y + 0.5
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return
	var cx: int = int(u * float(TEX_W - 1))
	var cy: int = int(v * float(TEX_H - 1))
	var harder: bool = m.hardness_mohs > PLATE_HARDNESS_MOHS
	# Hard stones leave only a faint grey scratch-mark of plate powder.
	var ink: Color = Color(0.82, 0.82, 0.8) if harder else m.streak_color
	var strength: float = 0.12 if harder else 0.35
	var radius_px: int = 2 if harder else 4
	for dy: int in range(-radius_px, radius_px + 1):
		for dx: int in range(-radius_px, radius_px + 1):
			var x: int = cx + dx
			var y: int = cy + dy
			if x < 0 or y < 0 or x >= TEX_W or y >= TEX_H or dx * dx + dy * dy > radius_px * radius_px:
				continue
			var base: Color = _image.get_pixel(x, y)
			_image.set_pixel(x, y, base.lerp(ink, strength))
	_dirty = true


func _announce(m: MineralData) -> void:
	if GrimoireJournal.instance == null:
		return
	var text: String
	if m.hardness_mohs > PLATE_HARDNESS_MOHS:
		text = "Streak test: %s (Mohs %g) is harder than the plate (6.5), so it leaves no streak, just a scratch." % [m.display_name, m.hardness_mohs]
	else:
		var streak: String = m.streak_name if m.streak_name != "" else "white"
		text = "Streak test: %s leaves a %s streak." % [m.display_name, streak]
		if m.luster == MineralData.Luster.METALLIC:
			text += " Metallic minerals often streak a totally different colour than they look!"
	GrimoireJournal.instance.toast.emit(text, &"discovery")


## Wipe the plate clean (used by tests / a future sponge tool).
func clear_plate() -> void:
	_image.fill(Color(0.95, 0.94, 0.9))
	_texture.update(_image)


func streak_pixel(u: float, v: float) -> Color:
	return _image.get_pixel(clampi(int(u * float(TEX_W - 1)), 0, TEX_W - 1), clampi(int(v * float(TEX_H - 1)), 0, TEX_H - 1))
