class_name CandleBody
extends MeshInstance3D
## Replaces the placeholder cylinder with a burnt-down candle: a melted crater
## around the wick, an uneven rim, runs of wax down the sides ending in beads,
## a pooled foot, a charred wick, and a brass chamberstick dish with a finger
## ring. The node keeps its origin and height, so the flame stays put.

@export var height_meters: float = 0.16
@export var radius_meters: float = 0.022
@export var seed_value: int = 12

const SEGS: int = 48
const SIDE_ROWS: int = 46


func _ready() -> void:
	var wax_mat: Material = mesh.surface_get_material(0) if mesh != null else null
	mesh = wax_mesh(height_meters, radius_meters, 0.008, seed_value)
	material_override = wax_mat
	var half: float = height_meters * 0.5
	var brass: StandardMaterial3D = PropMaterials.textured("metal", Color(0.78, 0.58, 0.27), 0.3, 0.95)
	var r: float = radius_meters
	var dish: MeshInstance3D = MeshInstance3D.new()
	dish.name = &"Dish"
	dish.mesh = MeshUtil.lathe(PackedVector2Array([
		Vector2(0.0, 0.0055), Vector2(r * 1.3, 0.0055), Vector2(r * 1.8, 0.008), Vector2(r * 2.1, 0.0125),
		Vector2(r * 2.2, 0.014), Vector2(r * 2.28, 0.0125), Vector2(r * 2.1, 0.006), Vector2(r * 1.6, 0.001),
		Vector2(r * 1.5, 0.0), Vector2(0.0, 0.0)]), SEGS)
	dish.material_override = brass
	dish.position.y = -half
	add_child(dish)
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 0.008
	ring.outer_radius = 0.0115
	ring.rings = 24
	ring.ring_segments = 10
	var handle: MeshInstance3D = MeshInstance3D.new()
	handle.name = &"FingerRing"
	handle.mesh = ring
	handle.material_override = brass
	handle.position = Vector3(r * 2.2 + 0.008, -half + 0.012, 0.012)
	handle.rotation = Vector3(PI * 0.5, 0.5, 0.0)
	add_child(handle)
	var wick_mesh: CylinderMesh = CylinderMesh.new()
	wick_mesh.top_radius = 0.0007
	wick_mesh.bottom_radius = 0.0011
	wick_mesh.height = 0.016
	wick_mesh.radial_segments = 8
	var wick_mat: StandardMaterial3D = StandardMaterial3D.new()
	wick_mat.albedo_color = Color(0.05, 0.04, 0.035)
	wick_mat.roughness = 1.0
	wick_mesh.material = wick_mat
	var wick: MeshInstance3D = MeshInstance3D.new()
	wick.name = &"Wick"
	wick.mesh = wick_mesh
	wick.position = Vector3(0.0005, half - 0.004, 0.0)
	wick.rotation.z = -0.15
	wick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wick)


## Candle wax, centred on the origin like the cylinder it replaces; the foot
## stops `foot_lift` above the bottom to sit in the dish.
static func wax_mesh(height: float, radius: float, foot_lift: float, seed_value: int) -> ArrayMesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.0
	var top: float = height * 0.5 - 0.002
	var foot: float = -height * 0.5 + foot_lift
	var drips: int = rng.randi_range(5, 8)
	var d_ang: PackedFloat32Array = PackedFloat32Array()
	var d_len: PackedFloat32Array = PackedFloat32Array()
	var d_wid: PackedFloat32Array = PackedFloat32Array()
	for d: int in drips:
		d_ang.append(rng.randf() * TAU)
		d_len.append(rng.randf_range(0.12, 0.8) * (top - foot))
		d_wid.append(rng.randf_range(0.1, 0.2))
	# One long run always faces the viewer (+Z).
	d_ang[0] = PI * 0.5 + rng.randf_range(-0.5, 0.5)
	d_len[0] = (top - foot) * 0.7
	var cols: Array[PackedVector2Array] = []
	for j: int in SEGS:
		var a: float = TAU * float(j) / float(SEGS)
		# The rim has burnt lower where the wax spills over.
		var spill: float = 0.0
		for d: int in drips:
			spill = maxf(spill, exp(-pow(wrapf(a - d_ang[d], -PI, PI) / (d_wid[d] * 1.6), 2.0)))
		var rim: float = top + noise.get_noise_1d(a * 2.0) * 0.0014 - spill * 0.003
		var col: PackedVector2Array = PackedVector2Array()
		col.append(Vector2(0.0, top - 0.009))
		col.append(Vector2(radius * 0.3, top - 0.0085))
		col.append(Vector2(radius * 0.62, top - 0.006))
		col.append(Vector2(radius * 0.86, rim - 0.0008))
		col.append(Vector2(radius * 0.97, rim))
		for s: int in SIDE_ROWS:
			var f: float = float(s) / float(SIDE_ROWS - 1)
			var y: float = lerpf(rim - 0.0025, foot, f)
			var r: float = lerpf(radius, radius * 1.07, f) * (1.0 + noise.get_noise_2d(a * 3.0, y * 40.0) * 0.02)
			for d: int in drips:
				var g: float = exp(-pow(wrapf(a - d_ang[d], -PI, PI) / d_wid[d], 2.0))
				var tip: float = top - d_len[d]
				var body: float = smoothstep(tip - 0.003, tip + 0.004, y)
				var bead: float = exp(-pow((y - tip - 0.004) / 0.0045, 2.0))
				r += g * (body * 0.003 + bead * 0.0028)
			# Wax pooled and set around the foot.
			var pool: float = smoothstep(foot + 0.016, foot, y)
			r += pool * pool * radius * (0.28 + 0.2 * noise.get_noise_1d(a * 4.0 + 50.0))
			col.append(Vector2(r, y))
		col.append(Vector2(0.0, foot))
		cols.append(col)
	return MeshUtil.lathe_columns(cols)
