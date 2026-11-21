class_name LabDressing
extends Node3D
## Fine detail for the mineral lab's props, added on top of the Blender models:
## iron corner brackets, nails and painted labels on the crates, engraved brass
## nameplates, rivet rows on the crusher, straps and bolts on the anvil block,
## grade tags on the sifter's sieves, vent slots, and stone chips scattered
## where rocks get broken.
##
## Everything is static and batched: boxes, rivets and chips are MultiMeshes
## (one draw call per material), so the whole pass costs a handful of draws.
## Positions are offsets from each prop's own node, so the detail follows a
## prop if it is moved in the scene.

@export var seed_value: int = 31

var _boxes: Dictionary = {}  # material key -> Array[Transform3D]
var _domes: Dictionary = {}  # material key -> Array[Transform3D]
var _lab: Node3D


func _ready() -> void:
	_lab = get_parent() as Node3D
	if _lab == null:
		return
	# Props add their own parts in _ready; dress them once they are all built.
	_dress.call_deferred()


func _dress() -> void:
	for crate: Array in [["RockCrate", "ROCKS"], ["SandCrate", "SAND"], ["SpecimenCrate", "SPECIMENS"]]:
		_dress_crate(_lab.get_node_or_null(crate[0]) as Node3D, crate[1])
	_dress_anvil(_lab.get_node_or_null("Anvil") as Node3D)
	_dress_crusher(_lab.get_node_or_null("RockCrusher") as Node3D)
	_dress_polisher(_lab.get_node_or_null("Polisher") as Node3D)
	_dress_faceter(_lab.get_node_or_null("Faceter") as Node3D)
	_dress_sifter(_lab.get_node_or_null("SandSifter") as Node3D)
	_build_batches()
	_scatter_chips()


# --- Props --------------------------------------------------------------------------

## Crate: 0.26 x 0.08 x 0.18 m, origin at the centre of its base.
func _dress_crate(crate: Node3D, text: String) -> void:
	if crate == null:
		return
	var o: Vector3 = crate.global_position
	var front: float = o.z + 0.096
	for sx: float in [-1.0, 1.0]:
		# Iron corner bracket wrapping the front corner, nailed on.
		_box(&"iron", Vector3(o.x + sx * 0.119, o.y + 0.04, front + 0.0006), Vector3(0.024, 0.08, 0.0016))
		_box(&"iron", Vector3(o.x + sx * 0.1308, o.y + 0.04, front - 0.011), Vector3(0.0016, 0.08, 0.024))
		for ny: float in [0.012, 0.04, 0.068]:
			_dome(&"iron", Vector3(o.x + sx * 0.119, o.y + ny, front + 0.0014), Vector3.BACK, 0.0028)
	# The side is two planks: a shadowed joint between them, and a worn top edge.
	_box(&"dark", Vector3(o.x, o.y + 0.041, front + 0.0002), Vector3(0.214, 0.0014, 0.0006))
	# Label: tacked at the corners, lettered by hand.
	for sx: float in [-1.0, 1.0]:
		_dome(&"brass", Vector3(o.x + sx * 0.035, o.y + 0.055, front + 0.0022), Vector3.BACK, 0.0016)
	_text(text, Vector3(o.x, o.y + 0.0445, front + 0.0024), 0.07, 0.016, Color(0.2, 0.09, 0.05))


## Anvil: stone block 0.16 x 0.08 x 0.12 m with an iron plate on top.
func _dress_anvil(anvil: Node3D) -> void:
	if anvil == null:
		return
	var o: Vector3 = anvil.global_position
	for by: float in [0.02, 0.06]:
		# Iron strap right round the block.
		_box(&"iron", Vector3(o.x, o.y + by, o.z), Vector3(0.1632, 0.012, 0.1232))
		for i: int in 5:
			_dome(&"iron", Vector3(o.x - 0.06 + 0.03 * float(i), o.y + by, o.z + 0.0618), Vector3.BACK, 0.003)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_dome(&"iron", Vector3(o.x + sx * 0.06, o.y + 0.09, o.z + sz * 0.04), Vector3.UP, 0.0045)


## Crusher: iron housing 0.16 m square, brass bands at 0.03 and 0.17 m, plate on the front.
func _dress_crusher(crusher: Node3D) -> void:
	if crusher == null:
		return
	var o: Vector3 = crusher.global_position
	var front: float = o.z + 0.08
	for by: float in [0.03, 0.17]:
		for i: int in 5:
			_dome(&"brass", Vector3(o.x - 0.052 + 0.026 * float(i), o.y + by, front + 0.0028), Vector3.BACK, 0.0032)
	# Inspection slots under the nameplate.
	for k: int in 3:
		_box(&"dark", Vector3(o.x, o.y + 0.058 + 0.009 * float(k), front + 0.0003), Vector3(0.05, 0.0035, 0.0008))
	for sx: float in [-1.0, 1.0]:
		_dome(&"brass", Vector3(o.x + sx * 0.031, o.y + 0.12, front + 0.0032), Vector3.BACK, 0.0018)
	_text("CRUSHER", Vector3(o.x, o.y + 0.12, front + 0.0034), 0.056, 0.012, Color(0.07, 0.035, 0.012))


## Polisher: enamel housing 0.2 x 0.1 x 0.2 m with a brass badge on the front.
func _dress_polisher(polisher: Node3D) -> void:
	if polisher == null:
		return
	var o: Vector3 = polisher.global_position
	var front: float = o.z + 0.1
	_text("POLISHER", Vector3(o.x, o.y + 0.05, front + 0.0034), 0.07, 0.011, Color(0.07, 0.035, 0.012))
	for sx: float in [-1.0, 1.0]:
		_dome(&"brass", Vector3(o.x + sx * 0.035, o.y + 0.05, front + 0.0032), Vector3.BACK, 0.0016)
		for sy: float in [0.01, 0.09]:
			_dome(&"brass", Vector3(o.x + sx * 0.09, o.y + sy, front + 0.0002), Vector3.BACK, 0.003)
	# Motor vents.
	for k: int in 4:
		_box(&"dark", Vector3(o.x - 0.07, o.y + 0.036 + 0.008 * float(k), front + 0.0003), Vector3(0.028, 0.003, 0.0008))
	# Rubber feet.
	for sx: float in [-1.0, 1.0]:
		_box(&"dark", Vector3(o.x + sx * 0.08, o.y + 0.002, front - 0.012), Vector3(0.024, 0.004, 0.02))


## Faceter: dark wooden housing 0.2 x 0.1 x 0.2 m.
func _dress_faceter(faceter: Node3D) -> void:
	if faceter == null:
		return
	var o: Vector3 = faceter.global_position
	var front: float = o.z + 0.1
	_box(&"brass", Vector3(o.x, o.y + 0.05, front + 0.001), Vector3(0.076, 0.02, 0.002))
	_text("FACETER", Vector3(o.x, o.y + 0.05, front + 0.0023), 0.066, 0.011, Color(0.07, 0.035, 0.012))
	for sx: float in [-1.0, 1.0]:
		_dome(&"brass", Vector3(o.x + sx * 0.033, o.y + 0.05, front + 0.002), Vector3.BACK, 0.0016)
		for sy: float in [0.008, 0.092]:
			# Brass corner caps, pinned.
			_box(&"brass", Vector3(o.x + sx * 0.092, o.y + sy, front + 0.0006), Vector3(0.016, 0.016, 0.0012))
			_dome(&"brass", Vector3(o.x + sx * 0.092, o.y + sy, front + 0.0012), Vector3.BACK, 0.0026)


## Sifter: three sieves stacked at 0.2, 0.235 and 0.27 m; front boards at z + 0.079.
func _dress_sifter(sifter: Node3D) -> void:
	if sifter == null:
		return
	var o: Vector3 = sifter.global_position
	var front: float = o.z + 0.079
	var grades: PackedStringArray = ["FINE", "MEDIUM", "COARSE"]
	for i: int in 3:
		var y: float = o.y + 0.215 + 0.035 * float(i)
		_box(&"brass", Vector3(o.x, y, front + 0.0006), Vector3(0.052, 0.015, 0.0012))
		_text(grades[i], Vector3(o.x, y, front + 0.0015), 0.044, 0.0085, Color(0.07, 0.035, 0.012))
		for sx: float in [-1.0, 1.0]:
			_dome(&"brass", Vector3(o.x + sx * 0.0225, y, front + 0.0012), Vector3.BACK, 0.0013)


# --- Batching -----------------------------------------------------------------------

func _box(material: StringName, center: Vector3, size: Vector3) -> void:
	if not _boxes.has(material):
		_boxes[material] = []
	(_boxes[material] as Array).append(Transform3D(Basis.from_scale(size), center))


## A domed head (rivet, nail, bolt) sitting on a surface with this normal.
func _dome(material: StringName, at: Vector3, normal: Vector3, radius: float) -> void:
	if not _domes.has(material):
		_domes[material] = []
	var y: Vector3 = normal.normalized()
	var x: Vector3 = y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP).normalized()
	var basis: Basis = Basis(x, y, x.cross(y)).scaled(Vector3.ONE * radius)
	(_domes[material] as Array).append(Transform3D(basis, at))


func _material(key: StringName) -> Material:
	var m: StandardMaterial3D
	match key:
		&"iron":
			m = PropMaterials.textured("iron", Color(0.5, 0.5, 0.53), 0.12, 0.6).duplicate() as StandardMaterial3D
		&"brass":
			m = PropMaterials.textured("metal", Color(0.95, 0.72, 0.34), 0.12, 0.85).duplicate() as StandardMaterial3D
		_:
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.035, 0.03, 0.028)
			m.roughness = 0.9
			return m
	# The instances are scaled, so map the texture in world space.
	m.uv1_world_triplanar = true
	return m


func _build_batches() -> void:
	var cube: BoxMesh = BoxMesh.new()
	cube.size = Vector3.ONE
	var dome: SphereMesh = SphereMesh.new()
	dome.radius = 1.0
	dome.height = 1.0
	dome.is_hemisphere = true
	dome.radial_segments = 10
	dome.rings = 3
	for pair: Array in [[_boxes, cube, "Boxes"], [_domes, dome, "Heads"]]:
		var groups: Dictionary = pair[0]
		for key: StringName in groups:
			var list: Array = groups[key]
			var mm: MultiMesh = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = pair[1]
			mm.instance_count = list.size()
			var to_local: Transform3D = global_transform.affine_inverse()
			for i: int in list.size():
				mm.set_instance_transform(i, to_local * (list[i] as Transform3D))
			var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
			mmi.name = "%s_%s" % [pair[2], key]
			mmi.multimesh = mm
			mmi.material_override = _material(key)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)


## Painted or engraved lettering, scaled to fit `width_m` and capped at `height_m`.
func _text(text: String, at: Vector3, width_m: float, height_m: float, color: Color) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = CosmicTheme.display_font()
	label.font_size = 64
	label.outline_size = 0
	label.modulate = color
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var size_px: Vector2 = label.font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 64)
	label.pixel_size = minf(width_m / maxf(size_px.x, 1.0), height_m / maxf(size_px.y * 0.72, 1.0))
	add_child(label)
	label.global_position = at


# --- Rubble --------------------------------------------------------------------------

## Chips and grit on the bench where rocks are struck and crushed.
func _scatter_chips() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var spots: Array = []
	var anvil: Node3D = _lab.get_node_or_null("Anvil") as Node3D
	var crusher: Node3D = _lab.get_node_or_null("RockCrusher") as Node3D
	if anvil != null:
		spots.append([anvil.global_position, 0.1, 0.19, 60])
	if crusher != null:
		spots.append([crusher.global_position + Vector3(0.0, 0.0, 0.16), 0.03, 0.1, 24])
	if spots.is_empty():
		return
	var total: int = 0
	for s: Array in spots:
		total += int(s[3])
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	# A few millimetres across on screen: a tiny low-poly lump is plenty.
	var chip: SphereMesh = SphereMesh.new()
	chip.radius = 1.0
	chip.height = 2.0
	chip.radial_segments = 5
	chip.rings = 2
	mm.mesh = chip
	mm.instance_count = total
	var to_local: Transform3D = global_transform.affine_inverse()
	var palette: Array[Color] = [Color(0.42, 0.4, 0.38), Color(0.3, 0.29, 0.28), Color(0.55, 0.5, 0.44), Color(0.36, 0.31, 0.27), Color(0.62, 0.6, 0.57)]
	var index: int = 0
	for s: Array in spots:
		var centre: Vector3 = s[0]
		for i: int in int(s[3]):
			# Denser close in, a few strays further out; most are grit, a few are chips.
			var r: float = lerpf(float(s[1]), float(s[2]), pow(rng.randf(), 1.6))
			var a: float = rng.randf() * TAU
			var size: float = 0.0012 + 0.0045 * pow(rng.randf(), 3.0)
			var basis: Basis = Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3(size, size * rng.randf_range(0.45, 0.8), size))
			var at: Vector3 = Vector3(centre.x + cos(a) * r, centre.y + size * 0.3, centre.z + sin(a) * r * 0.8)
			mm.set_instance_transform(index, to_local * Transform3D(basis, at))
			mm.set_instance_color(index, palette[rng.randi_range(0, palette.size() - 1)] * rng.randf_range(0.8, 1.15))
			index += 1
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Chips"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
