extends "res://tests/unit/unit_test_base.gd"
## Meshes built in code for set dressing: lathes, the melted candle and books.


func _normals(mesh: ArrayMesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]


func _verts(mesh: ArrayMesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func test_lathe_shades_convex_and_concave_profiles() -> void:
	# A bowl: inside walking outward and up, over the rim, down the outside.
	var bowl: ArrayMesh = MeshUtil.lathe(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.03, 0.002), Vector2(0.05, 0.02), Vector2(0.052, 0.02), Vector2(0.032, -0.004), Vector2(0.0, -0.006)]), 24)
	var v: PackedVector3Array = _verts(bowl)
	var n: PackedVector3Array = _normals(bowl)
	var inside_up: int = 0
	var outside_down: int = 0
	var bad: int = 0
	for k: int in v.size():
		if is_nan(n[k].x) or absf(n[k].length() - 1.0) > 1e-3:
			bad += 1
		var r: float = Vector2(v[k].x, v[k].z).length()
		if absf(r - 0.03) < 1e-4 and absf(v[k].y - 0.002) < 1e-4 and n[k].y > 0.5:
			inside_up += 1
		if absf(r - 0.032) < 1e-4 and v[k].y < 0.0 and n[k].y < -0.3:
			outside_down += 1
	check(bad == 0, "lathe normals are unit length (%d bad)" % bad)
	check(inside_up == 24, "the inside of a bowl faces up (%d of 24)" % inside_up)
	check(outside_down == 24, "the underside of a bowl faces down (%d of 24)" % outside_down)


func test_candle_wax_is_sound_and_keeps_its_size() -> void:
	var mesh: ArrayMesh = CandleBody.wax_mesh(0.16, 0.022, 0.008, 12)
	var top: float = -1.0
	var bottom: float = 1.0
	var widest: float = 0.0
	var not_finite: int = 0
	for p: Vector3 in _verts(mesh):
		if is_nan(p.x + p.y + p.z) or is_inf(p.x + p.y + p.z):
			not_finite += 1
		top = maxf(top, p.y)
		bottom = minf(bottom, p.y)
		widest = maxf(widest, Vector2(p.x, p.z).length())
	check(not_finite == 0, "every candle vertex is finite (%d bad)" % not_finite)
	check(top <= 0.08 and top > 0.07, "the rim stays under the flame (top %.3f m)" % top)
	check(absf(bottom - (-0.072)) < 1e-4, "the foot sits in the dish (bottom %.3f m)" % bottom)
	check(widest > 0.024 and widest < 0.04, "drips and the pooled foot widen it modestly (%.3f m)" % widest)


func test_book_bands_and_mesh() -> void:
	check(Book3D.band_profile(0.5, 4, 0.2) > 0.99, "a raised band sits at each panel boundary")
	check(Book3D.band_profile(0.375, 4, 0.2) < 0.01, "panels between bands are flat")
	var mesh: ArrayMesh = Book3D.cover_mesh(0.04, 0.2, 0.15, 4)
	var arrays: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var spine_bad: int = 0
	var front: float = 0.0
	for k: int in v.size():
		front = maxf(front, v[k].z)
		if c[k].r > 0.5 and n[k].z < -0.05:
			spine_bad += 1
	check(spine_bad == 0, "the spine faces the reader (%d normals turned away)" % spine_bad)
	check(front > 0.075 and front < 0.08, "bands stand just proud of the spine (front %.4f m)" % front)
	check((arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size() == v.size(), "leather UVs cover every vertex")
