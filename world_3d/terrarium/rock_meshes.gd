class_name RockMeshes
extends RefCounted
## Procedural meshes for collectibles: noise-displaced rocks, crystal habits
## (hexagonal prisms, cubes, octahedra, plates, blades, rhombs), sand sacks,
## shells, nuggets, cleavage fragments and ~20 faceted gem cuts.
##
## Gem cuts are built as a stack of "rings": scaled copies of the cut's girdle
## outline at different heights. A ring rotated half a step against its
## neighbour makes the triangular facets of a brilliant cut; aligned rings make
## the long trapezoid steps of an emerald cut. Meshes are cached per
## (mineral, seed, cut, size).

enum Cut { NONE, ROUND, HEART, PRINCESS, EMERALD, TRILLION, STAR, OVAL, PEAR, MARQUISE, CUSHION, ASSCHER, RADIANT,
	BAGUETTE, OLD_MINE, ROSE, BRIOLETTE, CABOCHON, CHECKERBOARD, PORTUGUESE, HEXAGON, KITE }
const CUT_NAMES: PackedStringArray = ["Uncut", "Round Brilliant", "Heart", "Princess", "Emerald", "Trillion", "Star", "Oval",
	"Pear", "Marquise", "Cushion", "Asscher", "Radiant", "Baguette", "Old Mine", "Rose", "Briolette", "Cabochon",
	"Checkerboard", "Portuguese", "Hexagon", "Kite"]
## One-line description of each cut, shown on the faceting machine.
const CUT_INFO: PackedStringArray = ["", "58 facets, the classic sparkle king", "romantic brilliant with a cleft",
	"square brilliant, crisp corners", "long step facets like a hall of mirrors", "triangle with curved sides",
	"ten-pointed fantasy star", "stretched brilliant, flatters long stones", "teardrop brilliant", "pointed boat shape",
	"pillow-soft square, antique glow", "square step cut, hypnotic tunnel", "rectangle with brilliant fire",
	"slim step-cut rectangle", "high crown, tiny table, candle-lit fire", "flat back, domed facets (Georgian)",
	"faceted teardrop drop, no table", "smooth polished dome, best for stars, cat's eyes and opal",
	"domed grid of facets", "many-ringed brilliant, extra scintillation", "six-sided step cut", "diamond-kite step cut"]

enum Style { BRILLIANT, STEP, ROSE, BRIOLETTE, CABOCHON, CHECKER, PORTUGUESE, OLD_MINE }

const GEM_PC_SHADER: Shader = preload("res://visuals_3d/shaders/gem_pc.gdshader")
const GEM_MOBILE_SHADER: Shader = preload("res://visuals_3d/shaders/gem_mobile.gdshader")
const GEM_OPAQUE_SHADER: Shader = preload("res://visuals_3d/shaders/gem_opaque.gdshader")

static var _cache: Dictionary = {}


static func for_mineral(m: MineralData, radius: float, seed_value: int, cut: int, fragment: int = -1) -> Mesh:
	# Rocks within 1.5% of each other's size share one mesh (masses are
	# random, so an exact-radius key never hit the cache).
	var step: int = int(round(log(maxf(radius, 1e-4)) / 0.015))
	radius = exp(float(step) * 0.015)
	var key: String = "%s_%d_%d_%d_%d" % [m.mineral_id, seed_value % 7, cut, fragment, step]
	if _cache.has(key):
		return _cache[key]
	var mesh: Mesh
	if cut != Cut.NONE:
		mesh = faceted(cut, radius)
	elif fragment >= 0:
		mesh = cleavage_fragment(fragment, radius, seed_value)
	else:
		match m.shape:
			MineralData.Shape.CRYSTAL: mesh = crystal(radius, seed_value, 1)
			MineralData.Shape.CLUSTER: mesh = crystal(radius, seed_value, 4)
			MineralData.Shape.BAG: mesh = sack(radius)
			MineralData.Shape.SHELL: mesh = shell(radius)
			MineralData.Shape.NUGGET: mesh = natural_rock(radius, seed_value, RockForm.LUMPY)
			MineralData.Shape.GEODE: mesh = natural_rock(radius, seed_value, RockForm.ROUND, 0.1)
			MineralData.Shape.CUBE: mesh = box_habit(radius, Vector3(1.0, 0.95, 1.0), 0.0, seed_value)
			MineralData.Shape.RHOMB: mesh = box_habit(radius, Vector3(1.0, 0.8, 0.9), 0.45, seed_value)
			MineralData.Shape.PLATE: mesh = box_habit(radius, Vector3(1.3, 0.25, 1.1), 0.0, seed_value)
			MineralData.Shape.BLADE: mesh = blade(radius, seed_value)
			MineralData.Shape.OCTAHEDRON: mesh = octahedron(radius, 1.0)
			_: mesh = natural_rock(radius, seed_value, style_for_mineral(m))
	_cache[key] = mesh
	return mesh


# ---------------------------------------------------------------- mesh helpers
## Collects triangles, fixes each to face away from `center_hint` (Godot front
## faces are clockwise) and writes explicit normals (flat, or smoothed by position).
class TriBuilder:
	var verts: PackedVector3Array = PackedVector3Array()

	func tri(a: Vector3, b: Vector3, c: Vector3) -> void:
		verts.append(a)
		verts.append(b)
		verts.append(c)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		tri(a, b, c)
		tri(a, c, d)

	func commit(center: Vector3, smooth: bool) -> Mesh:
		var normals: PackedVector3Array = PackedVector3Array()
		normals.resize(verts.size())
		var i: int = 0
		while i < verts.size():
			var a: Vector3 = verts[i]
			var b: Vector3 = verts[i + 1]
			var c: Vector3 = verts[i + 2]
			var n: Vector3 = (b - a).cross(c - a)
			if n.length_squared() < 1e-20:
				n = Vector3.UP
			n = n.normalized()
			var centroid: Vector3 = (a + b + c) / 3.0
			var axis_point: Vector3 = Vector3(center.x, lerpf(center.y, centroid.y, 0.5), center.z)
			if n.dot(centroid - axis_point) < 0.0:
				verts[i + 1] = c
				verts[i + 2] = b
				n = -n
			normals[i] = n
			normals[i + 1] = n
			normals[i + 2] = n
			i += 3
		if smooth:
			var sums: Dictionary = {}
			for k: int in verts.size():
				var key: Vector3i = Vector3i((verts[k] * 1e5).round())
				sums[key] = sums.get(key, Vector3.ZERO) + normals[k]
			for k: int in verts.size():
				normals[k] = (sums[Vector3i((verts[k] * 1e5).round())] as Vector3).normalized()
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var k2: int = 0
		while k2 < verts.size():
			# Stored with (b-a)x(c-a) outward; Godot's front faces have that
			# cross product pointing inward (matches SphereMesh), so emit a, c, b.
			for j: int in [0, 2, 1]:
				st.set_normal(normals[k2 + j])
				st.add_vertex(verts[k2 + j])
			k2 += 3
		return st.commit()


static func blob(radius: float, seed_value: int, roughness: float, frequency: float) -> Mesh:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 18
	sphere.rings = 10
	var arrays: Array = sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency / radius * 0.05
	var squash: Vector3 = Vector3(1.0, 0.75 + float(seed_value % 5) * 0.06, 0.9)
	for i: int in verts.size():
		var v: Vector3 = verts[i]
		var n: float = noise.get_noise_3dv(v * 20.0)
		verts[i] = v * (1.0 + n * roughness) * squash
	var tb: TriBuilder = TriBuilder.new()
	for i: int in range(0, indices.size(), 3):
		tb.tri(verts[indices[i]], verts[indices[i + 1]], verts[indices[i + 2]])
	return tb.commit(Vector3.ZERO, false)


# ------------------------------------------------------------ natural rocks
## Smooth, high-detail stones. Each starts as a random ellipsoid that is cut
## by random fracture planes (blended with a smooth minimum, so the broken
## faces meet in softened edges rather than sharp polygons), then gets
## low- and high-frequency noise. Normals are smooth and shared (no seams).
enum RockForm { ANGULAR, LAYERED, PEBBLE, LUMPY, ROUND }

const ICO_LEVEL: int = 4  # 2562 vertices, 5120 triangles
static var _ico_verts: PackedVector3Array = PackedVector3Array()
static var _ico_tris: PackedInt32Array = PackedInt32Array()
static var _shape_cache: Dictionary = {}


static func style_for_mineral(m: MineralData) -> int:
	if m.mineral_id.contains("pearl"):
		return RockForm.ROUND
	match m.kind:
		MineralData.Kind.ROCK:
			return RockForm.LAYERED if m.mineral_class.contains("Sedimentary") else RockForm.ANGULAR
		MineralData.Kind.GEM, MineralData.Kind.FOSSIL:
			return RockForm.PEBBLE
	return RockForm.ANGULAR


## Most points handed to the physics engine for a rock's hull.
const HULL_MAX_POINTS: int = 96


## Convex collision hull for a rock mesh, built once per mesh. The engine
## builds the hull from a spread-out sample of the mesh's vertices: about
## 0.1 ms, where Mesh.create_convex_shape(clean, simplify) took 50-80 ms per
## rock and froze the game every time a rock was spawned or cracked.
static func convex_for(mesh: Mesh) -> Shape3D:
	var id: int = mesh.get_instance_id()
	if not _shape_cache.has(id):
		var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
		shape.points = hull_points(mesh)
		_shape_cache[id] = shape
	return _shape_cache[id]


## Distinct vertices of `mesh`, thinned to at most HULL_MAX_POINTS. Always
## keeps the extreme point along each axis so the hull spans the full rock.
static func hull_points(mesh: Mesh) -> PackedVector3Array:
	var seen: Dictionary = {}
	var unique: PackedVector3Array = PackedVector3Array()
	for s: int in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			var key: Vector3i = Vector3i((v * 1e4).round())
			if not seen.has(key):
				seen[key] = true
				unique.append(v)
	if unique.size() <= HULL_MAX_POINTS:
		return unique
	var out: PackedVector3Array = PackedVector3Array()
	var lo: Vector3 = unique[0]
	var hi: Vector3 = unique[0]
	var extremes: Array[Vector3] = [unique[0], unique[0], unique[0], unique[0], unique[0], unique[0]]
	for v: Vector3 in unique:
		for axis: int in 3:
			if v[axis] < extremes[axis * 2][axis]:
				extremes[axis * 2] = v
			if v[axis] > extremes[axis * 2 + 1][axis]:
				extremes[axis * 2 + 1] = v
	for e: Vector3 in extremes:
		out.append(e)
	var step: float = float(unique.size()) / float(HULL_MAX_POINTS - extremes.size())
	var f: float = 0.0
	while int(f) < unique.size() and out.size() < HULL_MAX_POINTS:
		out.append(unique[int(f)])
		f += step
	return out


static func _icosphere() -> void:
	if not _ico_verts.is_empty():
		return
	var t: float = (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = []
	for v: Vector3 in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append(v.normalized())
	var tris: Array[int] = [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2,
		10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	for _level: int in ICO_LEVEL:
		var mids: Dictionary = {}
		var next: Array[int] = []
		for i: int in range(0, tris.size(), 3):
			var m: Array[int] = []
			for e: int in 3:
				var a: int = tris[i + e]
				var b: int = tris[i + (e + 1) % 3]
				var key: int = mini(a, b) * 100000 + maxi(a, b)
				if not mids.has(key):
					mids[key] = verts.size()
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
				m.append(mids[key])
			next.append_array([tris[i], m[0], m[2], m[0], tris[i + 1], m[1], m[2], m[1], tris[i + 2], m[0], m[1], m[2]])
		tris = next
	_ico_verts = PackedVector3Array(verts)
	_ico_tris = PackedInt32Array(tris)


static func _smin(a: float, b: float, k: float) -> float:
	var h: float = clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func natural_rock(radius: float, seed_value: int, style: int, roughness: float = -1.0) -> Mesh:
	_icosphere()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + style
	# Per-style recipe: ellipsoid, fracture planes, edge softness, noise.
	var axes: Vector3 = Vector3(1.0, rng.randf_range(0.7, 0.9), rng.randf_range(0.78, 0.95))
	var cut_count: int = 0
	var cut_depth: Vector2 = Vector2(0.7, 0.9)
	var soft: float = 0.06
	var lumps: float = 0.05
	var grain: float = 0.012
	var bands: float = 0.0
	match style:
		RockForm.ANGULAR:
			cut_count = rng.randi_range(8, 11)
			cut_depth = Vector2(0.55, 0.88)
			soft = 0.035
			grain = 0.018
		RockForm.LAYERED:
			axes = Vector3(1.0, rng.randf_range(0.5, 0.65), rng.randf_range(0.8, 0.95))
			cut_count = rng.randi_range(5, 7)
			cut_depth = Vector2(0.65, 0.88)
			soft = 0.035
			bands = 0.016
		RockForm.PEBBLE:
			cut_count = rng.randi_range(4, 6)
			cut_depth = Vector2(0.72, 0.9)
			soft = 0.28
			lumps = 0.035
			grain = 0.004
		RockForm.LUMPY:
			lumps = 0.26
			grain = 0.02
		RockForm.ROUND:
			axes = Vector3(1.0, rng.randf_range(0.9, 1.0), rng.randf_range(0.92, 1.0))
			lumps = roughness if roughness >= 0.0 else 0.03
			grain = 0.003
	var normals: Array[Vector3] = []
	var depths: Array[float] = []
	for k: int in cut_count:
		var n: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		if style == RockForm.LAYERED and k < 2:
			n = Vector3(rng.randf_range(-0.15, 0.15), 1.0 if k == 0 else -1.0, rng.randf_range(-0.15, 0.15)).normalized()
		normals.append(n)
		depths.append(rng.randf_range(cut_depth.x, cut_depth.y))
	var low: FastNoiseLite = FastNoiseLite.new()
	low.seed = seed_value
	low.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	low.frequency = 1.1 if style != RockForm.LUMPY else 1.6
	low.fractal_octaves = 3
	var fine: FastNoiseLite = FastNoiseLite.new()
	fine.seed = seed_value + 101
	fine.frequency = 7.0
	fine.fractal_octaves = 2
	var band_phase: float = rng.randf() * TAU
	var band_tilt: Vector3 = Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)).normalized()

	var count: int = _ico_verts.size()
	var verts: PackedVector3Array = PackedVector3Array()
	verts.resize(count)
	var max_len: float = 0.0
	for i: int in count:
		var d: Vector3 = _ico_verts[i]
		# Ellipsoid radius along d.
		var q: Vector3 = d / axes
		var r: float = 1.0 / q.length()
		for k: int in normals.size():
			var c: float = d.dot(normals[k])
			if c > 0.05:
				r = _smin(r, depths[k] / c, soft)
		r *= 1.0 + low.get_noise_3dv(d) * lumps + fine.get_noise_3dv(d) * grain
		if bands > 0.0:
			r *= 1.0 + sin(d.dot(band_tilt) * r * 38.0 + band_phase) * bands
		var v: Vector3 = d * r
		verts[i] = v
		max_len = maxf(max_len, v.length())
	var scale: float = radius / maxf(max_len, 1e-4)
	for i: int in count:
		verts[i] *= scale
	# Smooth area-weighted normals and a simple tangent frame.
	var nrm: PackedVector3Array = PackedVector3Array()
	nrm.resize(count)
	for i: int in range(0, _ico_tris.size(), 3):
		var a: int = _ico_tris[i]
		var b: int = _ico_tris[i + 1]
		var c: int = _ico_tris[i + 2]
		var fn: Vector3 = (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if fn.dot(verts[a]) < 0.0:
			fn = -fn
		nrm[a] += fn
		nrm[b] += fn
		nrm[c] += fn
	var tangents: PackedFloat32Array = PackedFloat32Array()
	tangents.resize(count * 4)
	for i: int in count:
		var n2: Vector3 = nrm[i].normalized()
		nrm[i] = n2
		var t2: Vector3 = Vector3.UP.cross(n2)
		if t2.length_squared() < 1e-6:
			t2 = Vector3.RIGHT
		t2 = t2.normalized()
		tangents[i * 4] = t2.x
		tangents[i * 4 + 1] = t2.y
		tangents[i * 4 + 2] = t2.z
		tangents[i * 4 + 3] = 1.0
	# Godot front faces wind clockwise seen from outside: emit each triangle
	# so that (b-a)x(c-a) points inward.
	var idx: PackedInt32Array = PackedInt32Array()
	idx.resize(_ico_tris.size())
	for i: int in range(0, _ico_tris.size(), 3):
		var a2: int = _ico_tris[i]
		var b2: int = _ico_tris[i + 1]
		var c2: int = _ico_tris[i + 2]
		if (verts[b2] - verts[a2]).cross(verts[c2] - verts[a2]).dot(verts[a2]) > 0.0:
			idx[i] = a2
			idx[i + 1] = c2
			idx[i + 2] = b2
		else:
			idx[i] = a2
			idx[i + 1] = b2
			idx[i + 2] = c2
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func crystal(radius: float, seed_value: int, count: int) -> Mesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tool: ArrayMesh = ArrayMesh.new()
	for c: int in count:
		var r: float = radius * (0.45 if count > 1 else 0.55) * rng.randf_range(0.7, 1.1)
		var h: float = radius * (1.4 if count > 1 else 1.6) * rng.randf_range(0.7, 1.2)
		var tilt: Basis = Basis(Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.5) if count > 1 else 0.0)
		var base: Vector3 = Vector3(rng.randf_range(-0.4, 0.4), -radius * 0.5, rng.randf_range(-0.4, 0.4)) * radius if count > 1 else Vector3(0.0, -h * 0.45, 0.0)
		var tb: TriBuilder = TriBuilder.new()
		var lo: Array[Vector3] = []
		var hi: Array[Vector3] = []
		for k: int in 6:
			var a: float = TAU * float(k) / 6.0
			lo.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
			hi.append(Vector3(cos(a) * r, h * 0.7, sin(a) * r))
		for k: int in 6:
			var k2: int = (k + 1) % 6
			tb.quad(lo[k], hi[k], hi[k2], lo[k2])
			tb.tri(hi[k], Vector3(0.0, h, 0.0), hi[k2])
			tb.tri(lo[k2], Vector3.ZERO, lo[k])
		var prism: Mesh = tb.commit(Vector3(0.0, h * 0.35, 0.0), false)
		st.append_from(prism, 0, Transform3D(tilt, base))
	return st.commit(tool)


## Cubes (galena, pyrite, halite), plates (mica, wulfenite) and sheared rhombs
## (calcite, dolomite). `shear` slants the box into a rhombohedron.
static func box_habit(radius: float, proportions: Vector3, shear: float, seed_value: int) -> Mesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var s: Vector3 = proportions * radius * 0.62
	var shear_basis: Basis = Basis(Vector3(1.0, 0.0, 0.0), Vector3(shear, 1.0, shear * 0.6), Vector3(0.0, 0.0, 1.0))
	var c: Array[Vector3] = []
	for k: int in 8:
		var p: Vector3 = Vector3(s.x * (1.0 if k & 1 else -1.0), s.y * (1.0 if k & 2 else -1.0), s.z * (1.0 if k & 4 else -1.0))
		p *= rng.randf_range(0.95, 1.05)
		c.append(shear_basis * p)
	var tb: TriBuilder = TriBuilder.new()
	tb.quad(c[0], c[1], c[3], c[2])
	tb.quad(c[4], c[6], c[7], c[5])
	tb.quad(c[0], c[4], c[5], c[1])
	tb.quad(c[2], c[3], c[7], c[6])
	tb.quad(c[0], c[2], c[6], c[4])
	tb.quad(c[1], c[5], c[7], c[3])
	return tb.commit(Vector3.ZERO, false)


static func octahedron(radius: float, stretch: float) -> Mesh:
	var r: float = radius * 0.8
	var top: Vector3 = Vector3(0.0, r * stretch, 0.0)
	var bottom: Vector3 = -top
	var eq: Array[Vector3] = [Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, 0, -r)]
	var tb: TriBuilder = TriBuilder.new()
	for k: int in 4:
		var k2: int = (k + 1) % 4
		tb.tri(top, eq[k], eq[k2])
		tb.tri(bottom, eq[k2], eq[k])
	return tb.commit(Vector3.ZERO, false)


## Long flattened blade with a chisel tip (kyanite, stibnite, schorl).
static func blade(radius: float, seed_value: int) -> Mesh:
	var len_m: float = radius * 1.9
	var w: float = radius * 0.32
	var t: float = radius * 0.14
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var tip: float = len_m * 0.5 + radius * rng.randf_range(0.15, 0.35)
	var ring: Array[Vector3] = [Vector3(0, w, t), Vector3(0, -w, t), Vector3(0, -w, -t), Vector3(0, w, -t)]
	var tb: TriBuilder = TriBuilder.new()
	var lo: Array[Vector3] = []
	var hi: Array[Vector3] = []
	for p: Vector3 in ring:
		lo.append(p + Vector3(-len_m * 0.5, 0, 0))
		hi.append(p + Vector3(len_m * 0.5, 0, 0))
	for k: int in 4:
		var k2: int = (k + 1) % 4
		tb.quad(lo[k], hi[k], hi[k2], lo[k2])
	tb.quad(lo[0], lo[1], lo[2], lo[3])
	var chisel_a: Vector3 = Vector3(tip, w * 0.2, 0.0)
	var chisel_b: Vector3 = Vector3(tip, -w * 0.2, 0.0)
	tb.tri(hi[0], chisel_a, hi[3])
	tb.tri(hi[1], hi[2], chisel_b)
	tb.quad(hi[0], hi[1], chisel_b, chisel_a)
	tb.quad(hi[3], chisel_a, chisel_b, hi[2])
	return tb.commit(Vector3(0.0, 0.0, 0.0), false)


## A fragment shaped by how the mineral really breaks (MineralData.Cleavage).
static func cleavage_fragment(cleavage: int, radius: float, seed_value: int) -> Mesh:
	match cleavage:
		MineralData.Cleavage.CUBIC: return box_habit(radius, Vector3(1.0, 0.85 + float(seed_value % 3) * 0.1, 0.9), 0.0, seed_value)
		MineralData.Cleavage.RHOMBOHEDRAL: return box_habit(radius, Vector3(1.0, 0.75, 0.85), 0.5, seed_value)
		MineralData.Cleavage.OCTAHEDRAL: return octahedron(radius, 0.9 + float(seed_value % 3) * 0.1)
		MineralData.Cleavage.BASAL: return box_habit(radius, Vector3(1.4, 0.18, 1.15), 0.08, seed_value)
		MineralData.Cleavage.PRISMATIC: return blade(radius, seed_value)
		MineralData.Cleavage.POOR: return natural_rock(radius, seed_value, RockForm.ANGULAR)
	return conchoidal_shard(radius, seed_value)


## Glassy shard with curved, shell-like (conchoidal) faces and sharp edges.
static func conchoidal_shard(radius: float, seed_value: int) -> Mesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts: Array[Vector3] = []
	for k: int in 5:
		var a: float = TAU * float(k) / 5.0 + rng.randf_range(-0.3, 0.3)
		pts.append(Vector3(cos(a) * radius * rng.randf_range(0.7, 1.1), rng.randf_range(-0.15, 0.15) * radius, sin(a) * radius * rng.randf_range(0.5, 0.9)))
	var top: Vector3 = Vector3(rng.randf_range(-0.2, 0.2), 0.55, rng.randf_range(-0.2, 0.2)) * radius
	var bottom: Vector3 = Vector3(rng.randf_range(-0.2, 0.2), -0.35, rng.randf_range(-0.2, 0.2)) * radius
	var tb: TriBuilder = TriBuilder.new()
	for k: int in 5:
		var k2: int = (k + 1) % 5
		# Each face is split through a slightly sunken midpoint: a shallow scallop.
		var mid_top: Vector3 = (pts[k] + pts[k2] + top) / 3.0 * 0.9
		tb.tri(pts[k], pts[k2], mid_top)
		tb.tri(pts[k2], top, mid_top)
		tb.tri(top, pts[k], mid_top)
		tb.tri(pts[k2], pts[k], bottom)
	return tb.commit(Vector3.ZERO, false)


## Tied burlap sand sack: a slumped, bottom-heavy body gathered into folds
## toward a twine-tied neck, with a ruffled tuft of cloth above the tie.
## Built as a lathe (rings x segments, poles as zero-radius rings) so the
## folds can vary around the bag; normals are smooth with no seam.
static func sack(radius: float) -> Mesh:
	const RINGS: int = 56
	const SEGS: int = 56
	var height: float = radius * 1.75
	var y0: float = -height * 0.42
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 1.3
	var verts: PackedVector3Array = PackedVector3Array()
	verts.resize((RINGS + 1) * SEGS)
	for i: int in RINGS + 1:
		var t: float = float(i) / float(RINGS)  # 0 bottom .. 1 top
		var prof: float = _sack_profile(t)
		# Gathered folds: faint on the belly, deep near the neck and tuft.
		var fold_amp: float = 0.025 + 0.13 * smoothstep(0.35, 0.68, t) * (1.0 - smoothstep(0.69, 0.76, t)) + 0.28 * smoothstep(0.78, 0.92, t)
		for j: int in SEGS:
			var a: float = TAU * float(j) / float(SEGS)
			var dir: Vector3 = Vector3(cos(a), 0.0, sin(a))
			var folds: float = sin(a * 9.0 + noise.get_noise_2d(a * 2.0, t * 3.0) * 2.5) * 0.6 + sin(a * 14.0 + 1.3) * 0.4
			var lump: float = noise.get_noise_3d(dir.x * 1.5, t * 2.0, dir.z * 1.5) * 0.06
			var r: float = prof * (1.0 + folds * fold_amp + lump) * radius
			var y: float = y0 + t * height
			# The tuft's ruffled rim rises and falls with the folds.
			if t > 0.9:
				y += folds * 0.05 * radius * smoothstep(0.9, 1.0, t)
			verts[i * SEGS + j] = Vector3(dir.x * r * 1.04, y, dir.z * r * 0.96)
	var idx: PackedInt32Array = PackedInt32Array()
	for i: int in RINGS:
		for j: int in SEGS:
			var a2: int = i * SEGS + j
			var b2: int = i * SEGS + (j + 1) % SEGS
			var c2: int = (i + 1) * SEGS + j
			var d2: int = (i + 1) * SEGS + (j + 1) % SEGS
			# (b-a)x(c-a) points inward here, which is Godot's front face.
			idx.append_array([a2, b2, c2, b2, d2, c2])
	var nrm: PackedVector3Array = PackedVector3Array()
	nrm.resize(verts.size())
	for k: int in range(0, idx.size(), 3):
		var fn: Vector3 = (verts[idx[k + 2]] - verts[idx[k]]).cross(verts[idx[k + 1]] - verts[idx[k]])
		nrm[idx[k]] += fn
		nrm[idx[k + 1]] += fn
		nrm[idx[k + 2]] += fn
	var tangents: PackedFloat32Array = PackedFloat32Array()
	tangents.resize(verts.size() * 4)
	for k: int in verts.size():
		var n2: Vector3 = nrm[k]
		if n2.length_squared() < 1e-20:
			n2 = Vector3.DOWN if k < SEGS else Vector3.UP
		n2 = n2.normalized()
		nrm[k] = n2
		var t2: Vector3 = Vector3.UP.cross(n2)
		if t2.length_squared() < 1e-6:
			t2 = Vector3.RIGHT
		t2 = t2.normalized()
		tangents[k * 4] = t2.x
		tangents[k * 4 + 1] = t2.y
		tangents[k * 4 + 2] = t2.z
		tangents[k * 4 + 3] = 1.0
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Sack radius (fraction of the bag radius) at height t (0 bottom, 1 top).
static func _sack_profile(t: float) -> float:
	if t <= 0.0 or t >= 1.0:
		return 0.0
	var bottom: float = sqrt(clampf(t / 0.06, 0.0, 1.0))  # flat-ish base
	var belly: float = 0.82 + 0.18 * exp(-pow((t - 0.28) / 0.2, 2.0))  # slumped, widest low
	var r: float = bottom * belly
	r = lerpf(r, 0.42, smoothstep(0.42, 0.66, t))  # taper toward the neck
	r = lerpf(r, 0.17, smoothstep(0.64, 0.72, t))  # pinched by the tie
	var twine: float = exp(-pow((t - 0.72) / 0.018, 2.0)) * 0.06  # twine wrap
	r += twine
	r = lerpf(r, 0.34, smoothstep(0.74, 0.88, t))  # cloth flares above the tie
	r *= 1.0 - smoothstep(0.93, 1.0, t) * 0.75  # tuft closes in
	return r


static func shell(radius: float) -> Mesh:
	var turns: float = 3.0
	var steps: int = 60
	var sides: int = 10
	var prev: Array[Vector3] = []
	var prev_c: Vector3 = Vector3.ZERO
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		var a: float = t * TAU * turns
		var spiral_r: float = radius * 0.08 * exp(t * 2.2)
		var tube_r: float = radius * 0.06 * exp(t * 2.0)
		var center: Vector3 = Vector3(cos(a) * spiral_r, t * radius * 0.5 - radius * 0.2, sin(a) * spiral_r)
		var tangent: Vector3 = Vector3(-sin(a), 0.1, cos(a)).normalized()
		var outward: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var up: Vector3 = tangent.cross(outward).normalized()
		var ring: Array[Vector3] = []
		for k: int in sides:
			var b: float = TAU * float(k) / float(sides)
			ring.append(center + (outward * cos(b) + up * sin(b)) * tube_r)
		if not prev.is_empty():
			# Each tube segment's faces point away from its own local centre.
			var seg: TriBuilder = TriBuilder.new()
			for k: int in sides:
				var k2: int = (k + 1) % sides
				seg.quad(prev[k], ring[k], ring[k2], prev[k2])
			st.append_from(seg.commit((prev_c + center) * 0.5, true), 0, Transform3D.IDENTITY)
		prev = ring
		prev_c = center
	return st.commit()


# ---------------------------------------------------------------- gem cuts
## Girdle outline (unit radius, xz plane) for a cut.
static func outline(cut: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	match cut:
		Cut.PRINCESS:
			for k: int in 4:
				var a: float = TAU * float(k) / 4.0 + PI / 4.0
				pts.append(Vector2(cos(a), sin(a)) * 0.95)
		Cut.EMERALD, Cut.ASSCHER, Cut.RADIANT:
			var half: Vector2 = Vector2(1.0, 0.72) if cut != Cut.ASSCHER else Vector2(0.78, 0.78)
			var clip: float = 0.22 if cut != Cut.RADIANT else 0.16
			var corners: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
			for c: Vector2 in corners:
				var p: Vector2 = c * half
				pts.append(p - Vector2(c.x * clip, 0.0))
				pts.append(p - Vector2(0.0, c.y * clip))
			# Keep winding consistent (angle-increasing order).
			pts = _sort_by_angle(pts)
		Cut.BAGUETTE:
			pts = _sort_by_angle(PackedVector2Array([Vector2(1, 0.36), Vector2(-1, 0.36), Vector2(-1, -0.36), Vector2(1, -0.36)]))
		Cut.TRILLION:
			for k: int in 9:
				var a: float = TAU * float(k) / 9.0 - PI / 2.0
				var bulge: float = 1.0 if k % 3 == 0 else 0.67
				pts.append(Vector2(cos(a), sin(a)) * bulge)
		Cut.STAR:
			for k: int in 10:
				var a: float = TAU * float(k) / 10.0
				pts.append(Vector2(cos(a), sin(a)) * (1.0 if k % 2 == 0 else 0.55))
		Cut.HEART:
			for k: int in 24:
				var t: float = TAU * float(k) / 24.0
				var hx: float = 16.0 * pow(sin(t), 3.0)
				var hz: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
				pts.append(Vector2(hx, -hz) / 17.0)
		Cut.OVAL:
			for k: int in 16:
				var a: float = TAU * float(k) / 16.0
				pts.append(Vector2(cos(a), sin(a) * 0.72))
		Cut.PEAR:
			for k: int in 18:
				var a: float = TAU * float(k) / 18.0
				pts.append(Vector2(cos(a), 0.78 * sin(a) * sin(a * 0.5)))
		Cut.MARQUISE:
			for k: int in 16:
				var a: float = TAU * float(k) / 16.0
				pts.append(Vector2(cos(a), 0.5 * sin(a) * absf(sin(a)) + 0.12 * sin(a)))
		Cut.CUSHION:
			for k: int in 16:
				var a: float = TAU * float(k) / 16.0
				var c: float = cos(a)
				var s: float = sin(a)
				var r: float = pow(pow(absf(c), 3.0) + pow(absf(s), 3.0), -1.0 / 3.0) * 0.82
				pts.append(Vector2(c, s * 0.92) * r)
		Cut.HEXAGON:
			for k: int in 6:
				var a: float = TAU * float(k) / 6.0
				pts.append(Vector2(cos(a), sin(a)))
		Cut.KITE:
			pts = PackedVector2Array([Vector2(1.0, 0.0), Vector2(0.0, 0.55), Vector2(-0.6, 0.0), Vector2(0.0, -0.55)])
		Cut.CABOCHON:
			for k: int in 24:
				var a: float = TAU * float(k) / 24.0
				pts.append(Vector2(cos(a), sin(a) * 0.8))
		_:
			for k: int in 16:
				var a: float = TAU * float(k) / 16.0
				pts.append(Vector2(cos(a), sin(a)))
	return pts


static func _sort_by_angle(pts: PackedVector2Array) -> PackedVector2Array:
	var arr: Array = Array(pts)
	arr.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.angle() < b.angle())
	return PackedVector2Array(arr)


static func style_for(cut: int) -> int:
	match cut:
		Cut.EMERALD, Cut.ASSCHER, Cut.BAGUETTE, Cut.HEXAGON, Cut.KITE: return Style.STEP
		Cut.ROSE: return Style.ROSE
		Cut.BRIOLETTE: return Style.BRIOLETTE
		Cut.CABOCHON: return Style.CABOCHON
		Cut.CHECKERBOARD: return Style.CHECKER
		Cut.PORTUGUESE: return Style.PORTUGUESE
		Cut.OLD_MINE: return Style.OLD_MINE
	return Style.BRILLIANT


## Ring stack per style: [scale, height, twisted(0/1)] from top to bottom.
## The first/last ring collapse to a point when scale is 0.
static func profile(style: int) -> Array:
	match style:
		Style.STEP:
			return [[0.6, 0.3, 0], [0.76, 0.22, 0], [0.9, 0.12, 0], [1.0, 0.03, 0], [1.0, -0.01, 0], [0.8, -0.22, 0], [0.56, -0.44, 0], [0.3, -0.64, 0], [0.08, -0.78, 0]]
		Style.ROSE:
			return [[0.0, 0.58, 0], [0.45, 0.44, 1], [0.8, 0.22, 0], [1.0, 0.02, 1], [1.0, -0.06, 1], [0.95, -0.08, 1]]
		Style.BRIOLETTE:
			return [[0.0, 1.05, 0], [0.32, 0.8, 1], [0.66, 0.45, 0], [0.92, 0.05, 1], [0.86, -0.3, 0], [0.55, -0.6, 1], [0.0, -0.78, 0]]
		Style.CABOCHON:
			var rings: Array = []
			for i: int in 9:
				var t: float = float(i) / 8.0
				rings.append([sin(t * PI * 0.5), cos(t * PI * 0.5) * 0.55, 0])
			rings.append([0.96, -0.08, 0])
			rings.append([0.0, -0.08, 0])
			return rings
		Style.CHECKER:
			return [[0.3, 0.36, 0], [0.55, 0.32, 1], [0.76, 0.24, 0], [0.92, 0.12, 1], [1.0, 0.02, 0], [1.0, -0.02, 0], [0.52, -0.42, 1], [0.0, -0.82, 0]]
		Style.PORTUGUESE:
			return [[0.5, 0.34, 0], [0.68, 0.28, 1], [0.84, 0.18, 0], [0.95, 0.08, 1], [1.0, 0.01, 0], [1.0, -0.02, 0], [0.76, -0.24, 1], [0.48, -0.48, 0], [0.18, -0.7, 1], [0.0, -0.84, 0]]
		Style.OLD_MINE:
			return [[0.42, 0.42, 0], [0.74, 0.27, 1], [1.0, 0.03, 0], [1.0, -0.02, 0], [0.5, -0.45, 1], [0.12, -0.78, 0], [0.0, -0.8, 0]]
	# Classic brilliant: table, star facets, girdle, pavilion mains, culet.
	return [[0.55, 0.32, 0], [0.8, 0.2, 1], [1.0, 0.02, 0], [1.0, -0.02, 0], [0.5, -0.45, 1], [0.0, -0.86, 0]]


static func faceted(cut: int, radius: float) -> Mesh:
	var base: PackedVector2Array = outline(cut)
	var n: int = base.size()
	var mids: PackedVector2Array = PackedVector2Array()
	for k: int in n:
		mids.append((base[k] + base[(k + 1) % n]) * 0.5)
	var style: int = style_for(cut)
	var rings: Array = profile(style)
	var tb: TriBuilder = TriBuilder.new()
	var prev: Array[Vector3] = []
	var prev_twist: int = 0
	var first: bool = true
	for ring_def: Array in rings:
		var s: float = ring_def[0]
		var y: float = ring_def[1] * radius
		var twist: int = ring_def[2]
		var src: PackedVector2Array = mids if twist == 1 else base
		var ring: Array[Vector3] = []
		for p: Vector2 in src:
			ring.append(Vector3(p.x * s * radius, y, p.y * s * radius))
		if first:
			if s > 0.0:
				var c: Vector3 = Vector3(0.0, y, 0.0)
				for k: int in n:
					tb.tri(c, ring[k], ring[(k + 1) % n])
			first = false
		else:
			_strip(tb, prev, prev_twist, ring, twist, n)
		prev = ring
		prev_twist = twist
	var last: Array = rings[rings.size() - 1]
	if float(last[0]) > 0.0:
		var c2: Vector3 = Vector3(0.0, float(last[1]) * radius, 0.0)
		for k: int in n:
			tb.tri(c2, prev[(k + 1) % n], prev[k])
	return tb.commit(Vector3(0.0, -0.1 * radius, 0.0), style == Style.CABOCHON)


## Connects two rings: quads when aligned, zig-zag triangles when one is
## twisted half a step (that's what makes brilliant-cut star and kite facets).
static func _strip(tb: TriBuilder, a: Array[Vector3], ta: int, b: Array[Vector3], tbw: int, n: int) -> void:
	if b[0].is_equal_approx(b[n - 1]) and b[0].is_equal_approx(b[n / 2]):
		for k: int in n:
			tb.tri(a[k], b[0], a[(k + 1) % n])
		return
	if a[0].is_equal_approx(a[n - 1]) and a[0].is_equal_approx(a[n / 2]):
		for k: int in n:
			tb.tri(a[0], b[k], b[(k + 1) % n])
		return
	for k: int in n:
		var k2: int = (k + 1) % n
		if ta == tbw:
			tb.quad(a[k], b[k], b[k2], a[k2])
		elif ta == 0:
			# a[k] at k, b[k] at k+½, a[k2] at k+1
			tb.tri(a[k], b[k], a[k2])
			tb.tri(b[k], b[k2], a[k2])
		else:
			# a[k] at k+½, b[k2] at k+1, b[k] at k
			tb.tri(b[k], a[k], b[k2])
			tb.tri(a[k], a[k2], b[k2])


# ---------------------------------------------------------------- materials
## Real-looking stone material. Transparent/translucent gems and minerals (and
## any stone with an optical phenomenon) use the gem shader; tier-aware, so
## Android never gets the screen-texture variant.
const ETCH_NORMAL: Texture2D = preload("res://content/textures_4k/crystal_etched_normal.jpg")
const ETCH_ROUGH: Texture2D = preload("res://content/textures_4k/crystal_etched_rough.jpg")


static func material_for(m: MineralData, polish: float, cut: int) -> Material:
	var transparent_stone: bool = m.diaphaneity != MineralData.Diaphaneity.OPAQUE and m.kind in [MineralData.Kind.GEM, MineralData.Kind.MINERAL]
	var phenomenal: bool = m.phenomenon != MineralData.Phenomenon.NONE and m.phenomenon != MineralData.Phenomenon.FLUORESCENCE
	var legacy_glassy: bool = m.refractive_index <= 0.0 and m.luster == MineralData.Luster.GLASSY and m.kind in [MineralData.Kind.GEM, MineralData.Kind.MINERAL]
	if (transparent_stone or phenomenal or legacy_glassy) and m.shape != MineralData.Shape.BAG:
		return gem_material(m, polish, cut, transparent_stone or legacy_glassy)
	return _standard(m, polish, cut)


static func gem_material(m: MineralData, polish: float, cut: int, see_through: bool) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	if see_through:
		mat.shader = GEM_MOBILE_SHADER if QualityTier.is_mobile_tier() else GEM_PC_SHADER
	else:
		mat.shader = GEM_OPAQUE_SHADER
	var clarity: float = 0.0
	if see_through:
		clarity = 0.85 if m.diaphaneity == MineralData.Diaphaneity.TRANSPARENT else 0.4
	# Rough crystals scatter light; polish reveals the stone's clarity.
	clarity *= lerpf(0.45, 1.0, polish if cut == Cut.NONE else 1.0)
	mat.set_shader_parameter(&"body_color", m.color)
	mat.set_shader_parameter(&"alt_color", m.color_alt if m.color_alt.a > 0.0 else m.color)
	mat.set_shader_parameter(&"clarity", clarity)
	mat.set_shader_parameter(&"ior", m.refractive_index if m.refractive_index > 1.0 else 1.55)
	mat.set_shader_parameter(&"dispersion", m.dispersion if m.dispersion > 0.0 else 0.012)
	var faceted_amount: float = 0.0 if cut == Cut.NONE or cut == Cut.CABOCHON else 1.0
	if cut == Cut.NONE and m.shape in [MineralData.Shape.CRYSTAL, MineralData.Shape.CLUSTER, MineralData.Shape.OCTAHEDRON, MineralData.Shape.CUBE, MineralData.Shape.RHOMB]:
		faceted_amount = 0.35 * polish + 0.15  # natural crystal faces still glint
	mat.set_shader_parameter(&"faceted", faceted_amount)
	mat.set_shader_parameter(&"polish", maxf(polish, 0.95 if cut != Cut.NONE else 0.0))
	mat.set_shader_parameter(&"phenomenon", int(m.phenomenon))
	mat.set_shader_parameter(&"metallic_amount", 1.0 if m.luster == MineralData.Luster.METALLIC else 0.0)
	mat.set_shader_parameter(&"inclusion_amount", clampf(0.5 - float(m.rarity) * 0.1, 0.05, 0.5) * (1.0 if m.mineral_id != &"emerald" else 1.6))
	var glow_e: float = 0.0
	if m.emission.get_luminance() > 0.005:
		glow_e = 1.0 + polish * 1.5 + (1.0 if cut != Cut.NONE else 0.0)
	mat.set_shader_parameter(&"glow_color", m.emission)
	mat.set_shader_parameter(&"glow_energy", glow_e)
	mat.set_shader_parameter(&"seed", float(hash(m.mineral_id) % 97) * 0.37)
	# Raw crystals: frosty etched 4K faces (pits, striations) that polishing
	# and cutting clear away.
	mat.set_shader_parameter(&"etch_normal", ETCH_NORMAL)
	mat.set_shader_parameter(&"etch_rough", ETCH_ROUGH)
	mat.set_shader_parameter(&"rough_surface", (1.0 - polish) if cut == Cut.NONE else 0.0)
	return mat


static func _standard(m: MineralData, polish: float, cut: int) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	var c: Color = m.color
	mat.albedo_color = c
	mat.roughness = lerpf(0.9, 0.04, polish)
	match m.luster:
		MineralData.Luster.GLASSY, MineralData.Luster.ADAMANTINE:
			mat.metallic_specular = 0.9
			mat.clearcoat_enabled = polish > 0.3
			mat.clearcoat = polish
			mat.roughness = lerpf(0.55, 0.05, polish)
		MineralData.Luster.METALLIC:
			mat.metallic = 1.0
			mat.roughness = lerpf(0.65, 0.12, polish)
		MineralData.Luster.PEARLY, MineralData.Luster.WAXY, MineralData.Luster.RESINOUS:
			mat.roughness = lerpf(0.6, 0.18, polish)
			mat.subsurf_scatter_enabled = true
			mat.subsurf_scatter_strength = 0.4
		MineralData.Luster.SILKY:
			mat.roughness = lerpf(0.5, 0.15, polish)
			mat.anisotropy_enabled = true
			mat.anisotropy = 0.7
		MineralData.Luster.GLOW:
			mat.emission_enabled = true
		_:
			mat.roughness = lerpf(0.95, 0.5, polish)
	if m.shape == MineralData.Shape.BAG:
		mat.albedo_color = Color(0.62, 0.5, 0.33)
		mat.roughness = 1.0
	if m.emission.get_luminance() > 0.005:
		mat.emission_enabled = true
		mat.emission = m.emission
		mat.emission_energy_multiplier = 1.0 + polish * 1.5 + (1.0 if cut != Cut.NONE else 0.0)
	_apply_rock_texture(mat, m, polish)
	# Translucent and transparent minerals let light into them (quartz,
	# fluorite, gems): subsurface scattering and a soft back-light glow.
	if m.diaphaneity != MineralData.Diaphaneity.OPAQUE:
		mat.subsurf_scatter_enabled = true
		mat.subsurf_scatter_strength = 0.35 if m.diaphaneity == MineralData.Diaphaneity.TRANSLUCENT else 0.2
		mat.subsurf_scatter_skin_mode = false
		mat.backlight_enabled = true
		mat.backlight = m.color.lerp(Color.WHITE, 0.3) * 0.35
		mat.rim_enabled = true
		mat.rim = 0.25
		mat.rim_tint = 0.6
	return mat


## 4K surface for an opaque stone: which set and how big one tile is (metres).
static func rock_texture_set(m: MineralData) -> Array:
	if m.shape == MineralData.Shape.BAG:
		return ["burlap", 0.12]
	match m.kind:
		MineralData.Kind.ROCK:
			var layered: bool = m.mineral_class.contains("Sedimentary") or m.mineral_class.contains("Metamorphic")
			return ["rock_layered", 0.08] if layered else ["rock_granular", 0.06]
		MineralData.Kind.FOSSIL:
			return ["stone", 0.06]
	if m.luster == MineralData.Luster.METALLIC:
		return ["ore_metallic", 0.04]
	return ["crystal_etched", 0.03]


## Tileable 4K detail (triplanar). Rough stones show the full texture; the
## bumps and matte patches fade as the stone is polished.
static func _apply_rock_texture(mat: StandardMaterial3D, m: MineralData, polish: float) -> void:
	var info: Array = rock_texture_set(m)
	var roughness_now: float = mat.roughness
	PropMaterials.apply_set(mat, String(info[0]), float(info[1]))
	# Albedo maps are mid-grey detail: lift the tint so stones keep their colour.
	var c: Color = mat.albedo_color
	mat.albedo_color = Color(minf(c.r * 1.3, 1.0), minf(c.g * 1.3, 1.0), minf(c.b * 1.3, 1.0), c.a)
	if m.shape == MineralData.Shape.BAG:
		mat.albedo_color = Color(0.95, 0.9, 0.85)
	# The roughness map is absolute (~0.75 average): scale it to the stone's finish.
	mat.roughness = clampf(roughness_now / 0.75, 0.02, 1.0)
	mat.normal_scale = lerpf(1.0, 0.12, polish)
