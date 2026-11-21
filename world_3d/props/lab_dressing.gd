class_name LabDressing
extends PropDressing
## Fine detail for the mineral lab's props, added on top of the Blender models:
## iron corner brackets, nails and painted labels on the crates, engraved brass
## nameplates, rivet rows on the crusher, straps and bolts on the anvil block,
## grade tags on the sifter's sieves, vent slots, and stone chips scattered
## where rocks get broken.
##
## Everything is static and batched through PropDressing (one draw call per
## material), so the whole pass costs a handful of draws.
## Positions are offsets from each prop's own node, so the detail follows a
## prop if it is moved in the scene.

@export var seed_value: int = 31
## Front face of the back wall, and the bench top, in world space.
@export var wall_z_meters: float = -0.825
@export var bench_top_y_meters: float = 0.8

## Mohs scale reference minerals with their typical colours.
const MOHS: Array = [
	["Talc", Color(0.78, 0.84, 0.76)], ["Gypsum", Color(0.92, 0.9, 0.84)], ["Calcite", Color(0.95, 0.88, 0.7)],
	["Fluorite", Color(0.52, 0.36, 0.72)], ["Apatite", Color(0.3, 0.62, 0.6)], ["Orthoclase", Color(0.86, 0.62, 0.5)],
	["Quartz", Color(0.88, 0.9, 0.93)], ["Topaz", Color(0.93, 0.68, 0.3)], ["Corundum", Color(0.7, 0.12, 0.2)],
	["Diamond", Color(0.8, 0.93, 0.98)],
]

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
	var bench: Node3D = _lab.get_node_or_null("LabBench") as Node3D
	if bench != null:
		_hang_mohs_chart(Vector3(bench.global_position.x + 0.5, 1.03, wall_z_meters), 0.6)  # clear wall above the polisher
		_hang_tool_rack(Vector3(bench.global_position.x + 0.255, 1.085, wall_z_meters))
		_lay_sorting_mat(Vector3(bench.global_position.x - 0.14, bench_top_y_meters, 0.51))
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


# --- Wall and bench extras -----------------------------------------------------------

## A parchment reference chart pinned to the wall: the ten Mohs minerals, each
## with a colour swatch and a bar as long as its hardness.
func _hang_mohs_chart(at: Vector3, k: float = 1.0) -> void:
	var sheet: QuadMesh = QuadMesh.new()
	sheet.size = Vector2(0.22, 0.31) * k
	var paper: StandardMaterial3D = PropMaterials.textured("parchment", Color(0.88, 0.8, 0.62), 0.25).duplicate() as StandardMaterial3D
	paper.uv1_world_triplanar = true
	sheet.material = paper
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "MohsChart"
	mi.mesh = sheet
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0.0, 0.0, 0.002)
	var z: float = at.z + 0.0032
	var ink: Color = Color(0.17, 0.09, 0.05)
	for sx: float in [-1.0, 1.0]:
		_dome(&"brass", Vector3(at.x + sx * 0.098 * k, at.y + 0.143 * k, z), Vector3.BACK, 0.0035)
	_text("MOHS SCALE", Vector3(at.x, at.y + 0.127 * k, z), 0.16 * k, 0.02 * k, ink)
	_tint(Vector3(at.x, at.y + 0.111 * k, z), Vector3(0.18 * k, 0.0012, 0.0004), ink)
	for i: int in MOHS.size():
		var y: float = at.y + (0.09 - 0.0235 * float(i)) * k
		_tint(Vector3(at.x - 0.09 * k, y, z), Vector3(0.017 * k, 0.017 * k, 0.0006), ink)
		_tint(Vector3(at.x - 0.09 * k, y, z + 0.0004), Vector3(0.014 * k, 0.014 * k, 0.0006), MOHS[i][1])
		_text("%d  %s" % [i + 1, MOHS[i][0]], Vector3(at.x - 0.035 * k, y, z), 0.085 * k, 0.0098 * k, ink)
		var bar: float = 0.0085 * float(i + 1) * k
		_tint(Vector3(at.x + 0.012 * k + bar * 0.5, y, z), Vector3(bar, 0.0045 * k, 0.0004), ink.lerp(MOHS[i][1], 0.35))


## A wooden rail with pegs, and the small tools of the trade hanging from it.
func _hang_tool_rack(at: Vector3) -> void:
	var z: float = at.z
	_box(&"wood", Vector3(at.x, at.y, z + 0.009), Vector3(0.25, 0.034, 0.018))
	for sx: float in [-1.0, 1.0]:
		_dome(&"iron", Vector3(at.x + sx * 0.112, at.y, z + 0.018), Vector3.BACK, 0.004)
	var hang_z: float = z + 0.036
	for i: int in 4:
		var x: float = at.x - 0.09 + 0.06 * float(i)
		_cyl(&"wood", Vector3(x, at.y - 0.004, z + 0.016), Vector3(x, at.y, z + 0.05), 0.0042)
		# Leather thong looped over the peg.
		_cyl(&"dark", Vector3(x, at.y, hang_z), Vector3(x, at.y - 0.03, hang_z), 0.0012)
		var top: Vector3 = Vector3(x, at.y - 0.03, hang_z)
		match i:
			0:  # flat cold chisel
				_cyl(&"iron", top, top + Vector3(0.0, -0.012, 0.0), 0.0085)
				_cyl(&"iron", top + Vector3(0.0, -0.012, 0.0), top + Vector3(0.0, -0.11, 0.0), 0.006)
				_box(&"iron", top + Vector3(0.0, -0.122, 0.0), Vector3(0.016, 0.026, 0.004))
			1:  # point chisel
				_cyl(&"iron", top, top + Vector3(0.0, -0.01, 0.0), 0.007)
				_cyl(&"iron", top + Vector3(0.0, -0.01, 0.0), top + Vector3(0.0, -0.13, 0.0), 0.0045)
				_cyl(&"iron", top + Vector3(0.0, -0.13, 0.0), top + Vector3(0.0, -0.15, 0.0), 0.002)
			2:  # dusting brush
				_cyl(&"wood", top, top + Vector3(0.0, -0.085, 0.0), 0.0065)
				_cyl(&"brass", top + Vector3(0.0, -0.085, 0.0), top + Vector3(0.0, -0.1, 0.0), 0.0085)
				_box(&"bristle", top + Vector3(0.0, -0.12, 0.0), Vector3(0.022, 0.04, 0.009))
			3:  # small pick hammer
				_cyl(&"wood", top, top + Vector3(0.0, -0.14, 0.0), 0.005)
				_box(&"iron", top + Vector3(0.0, -0.135, 0.0), Vector3(0.05, 0.014, 0.012))
				_box(&"iron", top + Vector3(0.031, -0.135, 0.0), Vector3(0.014, 0.006, 0.006))
			4:  # steel rule
				_box(&"iron", top + Vector3(0.0, -0.085, 0.0), Vector3(0.016, 0.17, 0.0012))
				for k: int in 14:
					_tint(top + Vector3(-0.004 if k % 2 == 0 else -0.0055, -0.01 - 0.0115 * float(k), 0.0008), Vector3(0.008 if k % 2 == 0 else 0.005, 0.0008, 0.0003), Color(0.05, 0.05, 0.05))


## A stitched leather mat for sorting finds, with a loupe and tweezers left on it.
func _lay_sorting_mat(at: Vector3) -> void:
	var w: float = 0.4
	var d: float = 0.14
	_box(&"leather", at + Vector3(0.0, 0.0006, 0.0), Vector3(w, 0.0012, d))
	var inset: float = 0.007
	var pitch: float = 0.011
	for i: int in int((w - inset * 2.0) / pitch) + 1:
		var x: float = at.x - w * 0.5 + inset + pitch * float(i)
		for sz: float in [-1.0, 1.0]:
			_box(&"bristle", Vector3(x, at.y + 0.0013, at.z + sz * (d * 0.5 - inset)), Vector3(0.0055, 0.0004, 0.0011))
	for i: int in int((d - inset * 2.0) / pitch):
		var zz: float = at.z - d * 0.5 + inset + pitch * (float(i) + 0.5)
		for sx: float in [-1.0, 1.0]:
			_box(&"bristle", Vector3(at.x + sx * (w * 0.5 - inset), at.y + 0.0013, zz), Vector3(0.0011, 0.0004, 0.0055))
	# Loupe: brass ring, glass, short handle.
	var loupe_at: Vector3 = at + Vector3(0.14, 0.004, 0.02)
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 0.016
	ring.outer_radius = 0.02
	ring.rings = 28
	ring.ring_segments = 8
	var ring_mi: MeshInstance3D = MeshInstance3D.new()
	ring_mi.name = "Loupe"
	ring_mi.mesh = ring
	ring_mi.material_override = PropMaterials.textured("metal", Color(0.95, 0.72, 0.34), 0.12, 0.85)
	add_child(ring_mi)
	ring_mi.global_position = loupe_at
	var lens: CylinderMesh = CylinderMesh.new()
	lens.top_radius = 0.0165
	lens.bottom_radius = 0.0165
	lens.height = 0.0015
	lens.radial_segments = 24
	var lens_mi: MeshInstance3D = MeshInstance3D.new()
	lens_mi.mesh = lens
	lens_mi.material_override = QualityTier.pick_material(PropMaterials.GLASS_PC_MATERIAL, PropMaterials.GLASS_MOBILE_MATERIAL)
	lens_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_mi.add_child(lens_mi)
	_cyl(&"brass", loupe_at + Vector3(0.019, 0.0, 0.0), loupe_at + Vector3(0.026, 0.0, 0.0), 0.003)
	_cyl(&"wood", loupe_at + Vector3(0.026, 0.0, 0.0), loupe_at + Vector3(0.07, -0.001, 0.004), 0.0045)
	# Tweezers: two springy steel blades meeting at the tips.
	var tw: Vector3 = at + Vector3(-0.12, 0.0022, 0.01)
	for s: float in [-1.0, 1.0]:
		var blade: Transform3D = Transform3D(Basis(Vector3.UP, 0.35 + s * 0.035).scaled(Vector3(0.075, 0.0009, 0.0035)), tw + Vector3(0.0, 0.0, s * 0.0016))
		if not _boxes.has(&"iron"):
			_boxes[&"iron"] = []
		(_boxes[&"iron"] as Array).append(blade)


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
			mm.set_instance_color(index, (palette[rng.randi_range(0, palette.size() - 1)] * rng.randf_range(0.8, 1.15)).srgb_to_linear())
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
