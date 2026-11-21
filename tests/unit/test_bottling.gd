extends "res://tests/unit/unit_test_base.gd"
## Bottling: wax colour per grade, deterministic signets, and well-formed
## cork / medallion meshes (outward normals, Godot front-face winding).


func test_signet_points_are_deterministic_and_in_range() -> void:
	var a: int = BottleSeal3D.points_for_name("Fuming Vitriol of Buoyant Stasis [A]")
	var b: int = BottleSeal3D.points_for_name("Fuming Vitriol of Buoyant Stasis [C]")
	check(a == b, "the grade suffix does not change a brew's signet")
	var seen: Dictionary = {}
	for i: int in 200:
		var n: int = BottleSeal3D.points_for_name("Elixir %d" % i)
		check(n >= 3 and n <= 8, "signet star has 3..8 points (got %d)" % n)
		seen[n] = true
	check(seen.size() == 6, "every star shape turns up across brews (%d kinds)" % seen.size())


func test_each_grade_has_its_own_wax() -> void:
	var colours: Dictionary = {}
	for g: String in ["S", "A", "B", "C", "D", "F"]:
		colours[BottleSeal3D.wax_color_for_grade(g).to_html()] = g
	check(colours.size() == 6, "six grades, six wax colours")
	check(BottleSeal3D.wax_color_for_grade("?") == BottleSeal3D.wax_color_for_grade("C"), "unknown grade falls back to plain wax")


func _check_outward(mesh: ArrayMesh, center: Vector3, planar_axis: Vector3, what: String) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bad_normals: int = 0
	var bad_winding: int = 0
	for k: int in verts.size():
		var out: Vector3 = planar_axis if planar_axis != Vector3.ZERO else verts[k] - center
		if out.length_squared() > 1e-12 and nrm[k].dot(out) < 0.0:
			bad_normals += 1
		if is_nan(nrm[k].x) or absf(nrm[k].length() - 1.0) > 1e-3:
			bad_normals += 1
	for k: int in range(0, idx.size(), 3):
		var v0: Vector3 = verts[idx[k]]
		var cr: Vector3 = (verts[idx[k + 1]] - v0).cross(verts[idx[k + 2]] - v0)
		var out2: Vector3 = planar_axis if planar_axis != Vector3.ZERO else (v0 + verts[idx[k + 1]] + verts[idx[k + 2]]) / 3.0 - center
		if cr.length_squared() > 1e-20 and cr.dot(out2) > 0.0:
			bad_winding += 1
	check(bad_normals == 0, "%s normals are unit length and face outward (%d bad)" % [what, bad_normals])
	check(bad_winding == 0, "%s triangles wind as front faces from outside (%d bad)" % [what, bad_winding])


func test_cork_and_signet_meshes_face_outward() -> void:
	_check_outward(BottleSeal3D._cork_mesh(0.014, 0.015, 0.008), Vector3.ZERO, Vector3.ZERO, "cork")
	_check_outward(BottleSeal3D._medallion_mesh(0.008, 0.0018), Vector3.ZERO, Vector3(0.0, 0.0, 1.0), "signet")


func test_emblem_normal_map_is_valid() -> void:
	var tex: ImageTexture = BottleSeal3D._emblem_texture(5)
	var img: Image = tex.get_image()
	check(img.get_width() == 128 and img.has_mipmaps(), "emblem is a 128 px mipmapped map")
	var flat: Color = img.get_pixel(2, 2)
	check(flat.b > 0.95 and absf(flat.r - 0.5) < 0.02, "the field outside the rim is flat")
	var relief: float = 0.0
	for x: int in 128:
		relief = maxf(relief, absf(img.get_pixel(x, 64).r - 0.5))
	check(relief > 0.2, "the star and rim are embossed (max tilt %.2f)" % relief)
