class_name MeshUtil
extends RefCounted
## Shared helpers for meshes built in code.


## Orient every triangle as a Godot front face seen from outside (outward is
## away from `center`, or along -`center` when `planar`), then build smooth
## normals and tangents.
static func finish(verts: PackedVector3Array, idx: PackedInt32Array, uvs: PackedVector2Array, center: Vector3, planar: bool, colors: PackedColorArray = PackedColorArray()) -> ArrayMesh:
	var nrm: PackedVector3Array = PackedVector3Array()
	nrm.resize(verts.size())
	for k: int in range(0, idx.size(), 3):
		var v0: Vector3 = verts[idx[k]]
		var v1: Vector3 = verts[idx[k + 1]]
		var v2: Vector3 = verts[idx[k + 2]]
		var cr: Vector3 = (v1 - v0).cross(v2 - v0)
		if cr.length_squared() < 1e-24:
			continue
		var hint: Vector3 = -center if planar else (v0 + v1 + v2) / 3.0 - center
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
		var n2: Vector3 = nrm[k].normalized() if nrm[k].length_squared() > 1e-24 else Vector3.UP
		nrm[k] = n2
		var t2: Vector3 = Vector3.RIGHT if planar else Vector3.UP.cross(n2)
		if t2.length_squared() < 1e-6:
			t2 = Vector3.RIGHT
		t2 = (t2 - n2 * n2.dot(t2)).normalized()
		tangents[k * 4] = t2.x
		tangents[k * 4 + 1] = t2.y
		tangents[k * 4 + 2] = t2.z
		tangents[k * 4 + 3] = 1.0
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	if colors.size() == verts.size():
		arrays[Mesh.ARRAY_COLOR] = colors
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Surface of revolution from one (radius, height) profile.
static func lathe(profile: PackedVector2Array, segments: int = 40) -> ArrayMesh:
	var cols: Array[PackedVector2Array] = []
	for j: int in segments:
		cols.append(profile)
	return lathe_columns(cols)


## Lathe whose profile may differ per angle (one column of (radius, height)
## points per segment, all the same length). List each column walking from the
## top centre outward and down: the outside is then always on the left of the
## walk, so concave shapes (bowls, craters) shade correctly too.
static func lathe_columns(cols: Array[PackedVector2Array]) -> ArrayMesh:
	var segs: int = cols.size()
	var n: int = cols[0].size()
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	for j: int in segs:
		var a: float = TAU * float(j) / float(segs)
		for i: int in n:
			var p: Vector2 = cols[j][i]
			verts.append(Vector3(cos(a) * p.x, p.y, sin(a) * p.x))
			uvs.append(Vector2(float(j) / float(segs), float(i) / float(n - 1)))
	var idx: PackedInt32Array = PackedInt32Array()
	var nrm: PackedVector3Array = PackedVector3Array()
	nrm.resize(verts.size())
	for j: int in segs:
		var j2: int = (j + 1) % segs
		var am: float = TAU * (float(j) + 0.5) / float(segs)
		for i: int in n - 1:
			var d: Vector2 = (cols[j][i + 1] + cols[j2][i + 1] - cols[j][i] - cols[j2][i]) * 0.5
			if d.length_squared() < 1e-16:
				continue
			var want: Vector3 = Vector3(cos(am) * -d.y, d.x, sin(am) * -d.y)
			var quad: PackedInt32Array = PackedInt32Array([j * n + i, j2 * n + i, j * n + i + 1, j2 * n + i, j2 * n + i + 1, j * n + i + 1])
			for t: int in 2:
				var i0: int = quad[t * 3]
				var i1: int = quad[t * 3 + 1]
				var i2: int = quad[t * 3 + 2]
				var cr: Vector3 = (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
				if cr.length_squared() < 1e-24:
					continue
				if cr.dot(want) > 0.0:
					# Front faces have (b-a)x(c-a) pointing into the surface.
					var tmp: int = i1
					i1 = i2
					i2 = tmp
					cr = -cr
				idx.append_array([i0, i1, i2])
				nrm[i0] -= cr
				nrm[i1] -= cr
				nrm[i2] -= cr
	var tangents: PackedFloat32Array = PackedFloat32Array()
	tangents.resize(verts.size() * 4)
	for k: int in verts.size():
		var nn: Vector3 = nrm[k].normalized() if nrm[k].length_squared() > 1e-24 else Vector3.UP
		nrm[k] = nn
		var tg: Vector3 = Vector3.UP.cross(nn)
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
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
