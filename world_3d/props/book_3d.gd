class_name Book3D
extends RefCounted
## Builds a leather-bound book for shelf dressing: a rounded spine with raised
## bands, cover boards standing proud of an inset page block, and gilt tooling
## drawn by book_cover.gdshader. Local frame: X thickness, Y height, Z depth,
## spine facing +Z.

const COVER_SHADER: Shader = preload("res://visuals_3d/shaders/book_cover.gdshader")
const ROWS: int = 72
const ARC: int = 7
const BOARD_METERS: float = 0.0025

static var _cover_mat: ShaderMaterial = null


static func cover_material() -> ShaderMaterial:
	if _cover_mat == null:
		_cover_mat = ShaderMaterial.new()
		_cover_mat.shader = COVER_SHADER
		var dir: String = PropMaterials.TEX_DIR
		_cover_mat.set_shader_parameter(&"albedo_tex", load(dir + "leather_albedo.jpg"))
		_cover_mat.set_shader_parameter(&"normal_tex", load(dir + "leather_normal.jpg"))
		_cover_mat.set_shader_parameter(&"rough_tex", load(dir + "leather_rough.jpg"))
	return _cover_mat


## Raised-band profile (0..1) at height fraction v for a spine with n panels.
static func band_profile(v: float, panels: int, height_meters: float) -> float:
	var b: float = 0.0
	for k: int in range(1, panels):
		b = maxf(b, exp(-pow((v - float(k) / float(panels)) * height_meters / 0.0035, 2.0)))
	# Head and tail caps.
	b = maxf(b, 0.6 * exp(-pow((v - 0.012) * height_meters / 0.003, 2.0)))
	b = maxf(b, 0.6 * exp(-pow((v - 0.988) * height_meters / 0.003, 2.0)))
	return b


static func spine_bulge(thickness: float) -> float:
	return minf(thickness * 0.32, 0.011)


static func make(thickness: float, height: float, depth: float, color: Color, label: Color, rng: RandomNumberGenerator) -> Node3D:
	var root: Node3D = Node3D.new()
	var panels: int = rng.randi_range(4, 6)
	var cover: MeshInstance3D = MeshInstance3D.new()
	cover.name = &"Cover"
	cover.mesh = cover_mesh(thickness, height, depth, panels)
	cover.material_override = cover_material()
	cover.set_instance_shader_parameter(&"base_color", color)
	cover.set_instance_shader_parameter(&"label_color", label)
	cover.set_instance_shader_parameter(&"seed", rng.randf() * 100.0)
	cover.set_instance_shader_parameter(&"panels", float(panels))
	cover.set_instance_shader_parameter(&"aspect", clampf(height / float(panels) / (thickness * 1.25), 0.6, 2.5))
	root.add_child(cover)
	var z_back: float = -depth * 0.5 + 0.003
	var z_front: float = depth * 0.5 - spine_bulge(thickness)
	var pages: BoxMesh = BoxMesh.new()
	pages.size = Vector3(thickness - BOARD_METERS * 2.0, height - 0.008, z_front - z_back)
	pages.material = PropMaterials.textured("parchment", Color(0.72, 0.64, 0.5), 0.05)
	var block: MeshInstance3D = MeshInstance3D.new()
	block.name = &"Pages"
	block.mesh = pages
	block.position.z = (z_front + z_back) * 0.5
	root.add_child(block)
	return root


static func cover_mesh(t: float, h: float, d: float, panels: int) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var uv2: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	var idx: PackedInt32Array = PackedInt32Array()
	var bulge: float = spine_bulge(t)
	var zs: float = d * 0.5 - bulge
	var arc_len: float = t * 1.25
	var hy: float = h * 0.5
	var hx: float = t * 0.5
	var zb: float = -d * 0.5
	# Rounded spine with raised bands (shared vertices: smooth shading).
	for i: int in ROWS + 1:
		var v: float = float(i) / float(ROWS)
		var band: float = band_profile(v, panels, h)
		for j: int in ARC + 1:
			var s: float = float(j) / float(ARC)
			var phi: float = PI * s
			var out: Vector3 = Vector3(-cos(phi) * bulge, 0.0, sin(phi) * hx).normalized()
			verts.append(Vector3(-cos(phi) * hx, (v - 0.5) * h, zs + sin(phi) * bulge) + out * band * 0.0016)
			uvs.append(Vector2(s, v))
			uv2.append(Vector2(s * arc_len, v * h))
			cols.append(Color(1.0, band, 0.0))
	for i: int in ROWS:
		for j: int in ARC:
			var a: int = i * (ARC + 1) + j
			idx.append_array([a, a + 1, a + ARC + 1, a + 1, a + ARC + 2, a + ARC + 1])
	# Flat faces get their own vertices (hard edges). Each quad lists its four
	# corners, then the axes that map position to leather UVs.
	var quads: Array[PackedVector3Array] = []
	for sx: float in [-1.0, 1.0]:
		var xo: float = sx * hx
		var xi: float = sx * (hx - BOARD_METERS)
		# Outer board face, inner face (seen above the pages), back edge.
		quads.append(PackedVector3Array([Vector3(xo, -hy, zb), Vector3(xo, -hy, zs), Vector3(xo, hy, zs), Vector3(xo, hy, zb), Vector3.BACK, Vector3.UP]))
		quads.append(PackedVector3Array([Vector3(xi, -hy, zb), Vector3(xi, -hy, zs), Vector3(xi, hy, zs), Vector3(xi, hy, zb), Vector3.BACK, Vector3.UP]))
		quads.append(PackedVector3Array([Vector3(xo, -hy, zb), Vector3(xi, -hy, zb), Vector3(xi, hy, zb), Vector3(xo, hy, zb), Vector3.RIGHT, Vector3.UP]))
		for sy: float in [-1.0, 1.0]:
			quads.append(PackedVector3Array([Vector3(xo, sy * hy, zb), Vector3(xi, sy * hy, zb), Vector3(xi, sy * hy, zs), Vector3(xo, sy * hy, zs), Vector3.RIGHT, Vector3.BACK]))
	# Spine edge at head and tail: a strip between the outer and inner arcs.
	var bi: float = maxf(bulge - BOARD_METERS, 0.0)
	for sy: float in [-1.0, 1.0]:
		for j: int in ARC:
			var p0: float = PI * float(j) / float(ARC)
			var p1: float = PI * float(j + 1) / float(ARC)
			quads.append(PackedVector3Array([
				Vector3(-cos(p0) * hx, sy * hy, zs + sin(p0) * bulge), Vector3(-cos(p1) * hx, sy * hy, zs + sin(p1) * bulge),
				Vector3(-cos(p1) * (hx - BOARD_METERS), sy * hy, zs + sin(p1) * bi), Vector3(-cos(p0) * (hx - BOARD_METERS), sy * hy, zs + sin(p0) * bi),
				Vector3.RIGHT, Vector3.BACK]))
	for q: PackedVector3Array in quads:
		var base: int = verts.size()
		for k: int in 4:
			verts.append(q[k])
			uvs.append(Vector2(0.5, q[k].y / h + 0.5))
			uv2.append(Vector2(q[k].dot(q[4]) + 0.5, q[k].dot(q[5]) + 0.5))
			cols.append(Color(0.0, 0.0, 0.0))
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return _build(verts, idx, uvs, uv2, cols, hx - BOARD_METERS)


## Orient faces, then build normals and tangents. "Outward" is judged per
## face: board inner faces look inward toward the pages, and head/tail edges
## look up or down.
static func _build(verts: PackedVector3Array, idx: PackedInt32Array, uvs: PackedVector2Array, uv2: PackedVector2Array, cols: PackedColorArray, inner_x: float) -> ArrayMesh:
	var nrm: PackedVector3Array = PackedVector3Array()
	nrm.resize(verts.size())
	for k: int in range(0, idx.size(), 3):
		var v0: Vector3 = verts[idx[k]]
		var v1: Vector3 = verts[idx[k + 1]]
		var v2: Vector3 = verts[idx[k + 2]]
		var cr: Vector3 = (v1 - v0).cross(v2 - v0)
		if cr.length_squared() < 1e-24:
			continue
		var c: Vector3 = (v0 + v1 + v2) / 3.0
		var hint: Vector3 = Vector3(c.x, 0.0, c.z)
		var face_n: Vector3 = cr.normalized()
		if absf(face_n.y) > 0.9:
			hint = Vector3(0.0, c.y, 0.0)
		elif absf(face_n.x) > 0.9 and absf(absf(c.x) - inner_x) < 1e-5:
			hint = Vector3(-c.x, 0.0, 0.0)
		elif absf(face_n.z) > 0.9 and c.z < 0.0:
			hint = Vector3(0.0, 0.0, -1.0)
		if cr.dot(hint) > 0.0:
			# Front faces have (b-a)x(c-a) pointing into the surface.
			var tmp: int = idx[k + 1]
			idx[k + 1] = idx[k + 2]
			idx[k + 2] = tmp
			cr = -cr
		nrm[idx[k]] -= cr
		nrm[idx[k + 1]] -= cr
		nrm[idx[k + 2]] -= cr
	var tangents: PackedFloat32Array = PackedFloat32Array()
	tangents.resize(verts.size() * 4)
	for k: int in verts.size():
		var n: Vector3 = nrm[k].normalized() if nrm[k].length_squared() > 1e-24 else Vector3.BACK
		nrm[k] = n
		var tg: Vector3 = Vector3.UP.cross(n)
		if tg.length_squared() < 1e-6:
			tg = Vector3.RIGHT
		tg = tg.normalized()
		tangents[k * 4] = tg.x
		tangents[k * 4 + 1] = tg.y
		tangents[k * 4 + 2] = tg.z
		tangents[k * 4 + 3] = 1.0
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
