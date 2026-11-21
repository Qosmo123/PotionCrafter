class_name BottleSeal3D
extends Node3D
## Cork, sealing wax and signet medallion for a bottled vessel.
##
## Sealing pushes a tapered cork down into the neck, pours hot wax over it
## (the wax runs down the neck in uneven drips and cools from a glow to a
## glossy finish), then stamps a signet medallion onto the front of the neck.
## The wax colour follows the potion's grade and the signet's star has as many
## points as the potion's sigil seed gives, so two bottles of the same brew
## carry the same seal. Uncorking cracks the wax into flakes and pops the cork
## up with a puff of vapour.
##
## Presentation only: Vessel3D owns the sealed state; this node just shows it.

const WAX_SHADER: Shader = preload("res://visuals_3d/shaders/wax_seal.gdshader")
const SEGS: int = 48
const POUR_SECONDS: float = 0.65
const COOL_SECONDS: float = 1.8

## Wax colour per grade (S gilt, then royal purple, crimson, navy, forest, soot).
const GRADE_WAX: Dictionary = {
	"S": Color(0.78, 0.58, 0.2),
	"A": Color(0.34, 0.09, 0.4),
	"B": Color(0.56, 0.05, 0.06),
	"C": Color(0.09, 0.15, 0.4),
	"D": Color(0.12, 0.3, 0.13),
	"F": Color(0.07, 0.06, 0.055),
}

static var _cork_tex: ImageTexture = null
static var _emblem_mats: Dictionary = {}
static var _wax_mat: ShaderMaterial = null

var _vessel: Vessel3D
var _cork: MeshInstance3D
var _wax: MeshInstance3D
var _medallion: MeshInstance3D
var _cork_rest_y: float = 0.0
var _wax_top_y: float = 0.0
var _wax_bottom_y: float = 0.0
var _wax_color: Color = Color(0.56, 0.05, 0.06)
var _tween: Tween


func setup(vessel: Vessel3D) -> void:
	_vessel = vessel
	name = &"BottleSeal"
	var lip_y: float = vessel.get_lip_local_y()
	var neck_r: float = vessel.get_inner_radius_at_local_y(lip_y - 0.004)
	var wall: float = vessel.wall_thickness_meters
	# Cork: tapered plug, mostly inside the neck, its crown standing proud.
	var crown_h: float = clampf(neck_r * 0.55, 0.005, 0.011)
	var plug_h: float = clampf(neck_r * 1.1, 0.01, 0.02)
	_cork = MeshInstance3D.new()
	_cork.name = &"Cork"
	_cork.mesh = _cork_mesh(neck_r, plug_h, crown_h)
	_cork.material_override = _cork_material()
	add_child(_cork)
	_cork_rest_y = lip_y
	var crown_top_y: float = lip_y + crown_h
	var crown_r: float = neck_r * 1.12
	# Wax: a cap over the crown that runs down the outside of the neck.
	var thick: float = clampf(neck_r * 0.13, 0.0011, 0.0028)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(vessel.name)
	var built: Dictionary = _wax_mesh(vessel, lip_y, crown_top_y, crown_r, wall, thick, rng)
	_wax = MeshInstance3D.new()
	_wax.name = &"Wax"
	_wax.mesh = built["mesh"]
	_wax.material_override = _wax_material()
	_wax.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wax)
	_wax_top_y = built["top_y"]
	_wax_bottom_y = built["bottom_y"]
	# Signet medallion pressed onto the front of the waxed neck.
	var med_y: float = lip_y - clampf(neck_r * 0.75, 0.006, 0.014)
	var med_r: float = clampf(neck_r * 0.62, 0.0045, 0.0095)
	var surf_r: float = vessel.get_inner_radius_at_local_y(med_y) + wall + thick
	_medallion = MeshInstance3D.new()
	_medallion.name = &"Signet"
	_medallion.mesh = _medallion_mesh(med_r, med_r * 0.22)
	_medallion.position = Vector3(0.0, med_y, surf_r - med_r * 0.12)
	_medallion.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_medallion)
	visible = false


## Cork the bottle, pour the wax and stamp the signet. `points` is the star's
## point count (3..8); `instant` skips the animation (loading, tests).
func seal(grade: String, points: int, instant: bool = false) -> void:
	_kill_tween()
	visible = true
	_wax_color = GRADE_WAX.get(grade, GRADE_WAX["C"])
	var metal: float = 0.65 if grade == "S" else 0.0
	_medallion.material_override = _emblem_material(clampi(points, 3, 8))
	for m: MeshInstance3D in [_wax, _medallion]:
		m.visible = true
		m.set_instance_shader_parameter(&"wax_color", _wax_color)
		m.set_instance_shader_parameter(&"metal", metal)
	_cork.visible = true
	_cork.rotation = Vector3.ZERO
	_cork.scale = Vector3.ONE
	if instant or CosmicTheme.reduced_motion:
		_cork.position.y = _cork_rest_y
		_set_flow(-10.0)
		_set_heat(0.0)
		_medallion.scale = Vector3.ONE
		return
	_cork.position.y = _cork_rest_y + 0.04
	_set_flow(_wax_top_y + 0.01)
	_set_heat(1.0)
	_medallion.scale = Vector3.ZERO
	_tween = create_tween()
	_tween.tween_property(_cork, "position:y", _cork_rest_y, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_callback(AudioHaptics.tick)
	_tween.tween_method(_set_flow, _wax_top_y + 0.002, _wax_bottom_y - 0.002, POUR_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_medallion, "scale", Vector3.ONE, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_callback(AudioHaptics.tick)
	_tween.parallel().tween_method(_set_heat, 1.0, 0.0, COOL_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_callback(_set_flow.bind(-10.0))


## Crack the wax and pop the cork out with a puff of vapour.
func pop(instant: bool = false) -> void:
	_kill_tween()
	if not visible:
		return
	_wax.visible = false
	_medallion.visible = false
	if instant or not is_inside_tree() or CosmicTheme.reduced_motion:
		visible = false
		return
	var lip_world: Vector3 = global_transform * Vector3(0.0, _cork_rest_y + 0.004, 0.0)
	var fx: ImpactFx3D = ImpactFx3D.get_pool(self)
	if fx != null:
		fx.hit(lip_world, _wax_color.lerp(Color(0.92, 0.9, 0.86), 0.35), _wax_color, 0.05)
	AudioHaptics.tick()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_cork, "position:y", _cork_rest_y + 0.075, 0.38).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_cork, "position:x", 0.022, 0.38)
	_tween.tween_property(_cork, "rotation:z", -2.4, 0.38)
	_tween.tween_property(_cork, "scale", Vector3.ONE * 0.001, 0.14).set_delay(0.3)
	_tween.chain().tween_callback(func() -> void:
		visible = false
		_cork.position = Vector3(0.0, _cork_rest_y, 0.0))


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _set_flow(y: float) -> void:
	_wax.set_instance_shader_parameter(&"flow_y", y)


func _set_heat(h: float) -> void:
	_wax.set_instance_shader_parameter(&"heat", h)
	_medallion.set_instance_shader_parameter(&"heat", h * 0.8)


static func wax_color_for_grade(grade: String) -> Color:
	return GRADE_WAX.get(grade, GRADE_WAX["C"])


## Signet star points from the potion's name: same brew, same seal.
static func points_for_name(potion_name: String) -> int:
	return 3 + absi(hash(potion_name.get_slice(" [", 0))) % 6


# --- Meshes -----------------------------------------------------------------------

## Tapered cork: plug narrowing into the neck, slightly bulged crown, eased edge.
static func _cork_mesh(neck_r: float, plug_h: float, crown_h: float) -> ArrayMesh:
	var prof: PackedVector2Array = PackedVector2Array()
	prof.append(Vector2(0.0, crown_h))
	prof.append(Vector2(neck_r * 0.7, crown_h))
	prof.append(Vector2(neck_r * 1.06, crown_h * 0.88))
	prof.append(Vector2(neck_r * 1.12, crown_h * 0.6))
	prof.append(Vector2(neck_r * 1.1, 0.0))
	prof.append(Vector2(neck_r * 0.98, -0.0005))
	prof.append(Vector2(neck_r * 0.95, -plug_h * 0.5))
	prof.append(Vector2(neck_r * 0.86, -plug_h))
	prof.append(Vector2(0.0, -plug_h))
	var cols: Array[PackedVector3Array] = []
	for j: int in SEGS:
		var a: float = TAU * float(j) / float(SEGS)
		var col: PackedVector3Array = PackedVector3Array()
		for p: Vector2 in prof:
			col.append(Vector3(cos(a) * p.x, p.y, sin(a) * p.x))
		cols.append(col)
	return _lathe(cols, 0.0, true)


## Wax shell: a domed cap over the cork crown, rolling over its edge and
## running down the neck to an uneven hem with a few longer drips, each ending
## in a rounded bead. Returns the mesh plus its top and lowest y.
static func _wax_mesh(vessel: Vessel3D, lip_y: float, crown_top_y: float, crown_r: float, wall: float, thick: float, rng: RandomNumberGenerator) -> Dictionary:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 2.2
	var neck_r: float = vessel.get_inner_radius_at_local_y(lip_y - 0.004)
	var hem_depth: float = clampf(neck_r * 0.55, 0.005, 0.012)
	var drips: int = rng.randi_range(4, 7)
	var drip_ang: PackedFloat32Array = PackedFloat32Array()
	var drip_len: PackedFloat32Array = PackedFloat32Array()
	var drip_w: PackedFloat32Array = PackedFloat32Array()
	for d: int in drips:
		drip_ang.append(rng.randf() * TAU)
		drip_len.append(rng.randf_range(0.3, 1.0) * clampf(neck_r * 1.1, 0.006, 0.02))
		drip_w.append(rng.randf_range(0.12, 0.24))
	var top_y: float = crown_top_y + thick * 0.85
	var cap_r: float = crown_r + thick
	var lowest: float = top_y
	var cols: Array[PackedVector3Array] = []
	const SIDE: int = 14
	for j: int in SEGS:
		var a: float = TAU * float(j) / float(SEGS)
		var dir: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var extra: float = 0.0
		var width_boost: float = 0.0
		for d: int in drips:
			var da: float = absf(wrapf(a - drip_ang[d], -PI, PI))
			var g: float = exp(-pow(da / drip_w[d], 2.0))
			extra += drip_len[d] * g
			width_boost = maxf(width_boost, g)
		var hem: float = lip_y - hem_depth * (0.75 + 0.5 * (noise.get_noise_1d(a * 3.0) * 0.5 + 0.5)) - extra
		lowest = minf(lowest, hem - thick)
		var col: PackedVector3Array = PackedVector3Array()
		# Domed cap.
		for k: int in 4:
			var f: float = float(k) / 4.0
			col.append(dir * (cap_r * 0.92 * f) + Vector3(0.0, top_y + thick * 0.35 * (1.0 - f * f), 0.0))
		# Rolled edge over the crown.
		col.append(dir * (cap_r * 0.99) + Vector3(0.0, top_y - thick * 0.35, 0.0))
		col.append(dir * (cap_r + thick * 0.15) + Vector3(0.0, crown_top_y - thick * 0.6, 0.0))
		# Down the cork crown and the glass neck to the hem.
		var start_y: float = crown_top_y - thick * 1.6
		for s: int in SIDE:
			var f2: float = float(s) / float(SIDE - 1)
			var y: float = lerpf(start_y, hem, f2)
			var surf: float
			if y > lip_y:
				surf = lerpf(crown_r * 0.98, crown_r, clampf((y - lip_y) / maxf(crown_top_y - lip_y, 1e-4), 0.0, 1.0))
			else:
				surf = vessel.get_inner_radius_at_local_y(y) + wall
			# Wax thins as it runs, but pools fatter along a drip.
			var t: float = thick * lerpf(1.0, 0.7, f2) * (1.0 + width_boost * 0.35)
			t *= 1.0 + noise.get_noise_2d(a * 4.0, y * 300.0) * 0.25
			col.append(dir * (surf + t) + Vector3(0.0, y, 0.0))
		# Rounded bead at the hem, tucking back onto the glass.
		var bead_surf: float = vessel.get_inner_radius_at_local_y(hem - thick) + wall
		col.append(dir * (bead_surf + thick * (1.25 + width_boost * 0.5)) + Vector3(0.0, hem - thick * 0.45, 0.0))
		col.append(dir * (bead_surf + thick * 0.15) + Vector3(0.0, hem - thick, 0.0))
		cols.append(col)
	return {"mesh": _lathe(cols, lip_y, false), "top_y": top_y + thick * 0.35, "bottom_y": lowest}


## Puffy disc facing +Z with planar UVs (for the emblem normal map).
static func _medallion_mesh(r: float, h: float) -> ArrayMesh:
	const RINGS: int = 7
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var ring_r: PackedFloat32Array = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.78, 0.9, 1.0, 1.12])
	var ring_z: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 0.99, 0.97, 0.92, 0.78, 0.45, 0.0])
	for k: int in RINGS + 1:
		for j: int in SEGS:
			var a: float = TAU * float(j) / float(SEGS)
			var p: Vector3 = Vector3(cos(a) * r * ring_r[k], sin(a) * r * ring_r[k], h * ring_z[k])
			verts.append(p)
			uvs.append(Vector2(p.x / r * 0.5 + 0.5, -p.y / r * 0.5 + 0.5))
	for k: int in RINGS:
		for j: int in SEGS:
			var a2: int = k * SEGS + j
			var b2: int = k * SEGS + (j + 1) % SEGS
			var c2: int = (k + 1) * SEGS + j
			var d2: int = (k + 1) * SEGS + (j + 1) % SEGS
			idx.append_array([a2, b2, c2, b2, d2, c2])
	return _finish(verts, idx, uvs, Vector3(0.0, 0.0, -1.0), true)


## Triangulate columns (one per angle, profile points top to bottom).
## `hint_y`: outward is away from the axis point at this height.
static func _lathe(cols: Array[PackedVector3Array], hint_y: float, cork: bool) -> ArrayMesh:
	var n: int = cols[0].size()
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	for j: int in SEGS:
		for i: int in n:
			verts.append(cols[j][i])
			uvs.append(Vector2(float(j) / float(SEGS) * 3.0, cols[j][i].y * 60.0) if cork else Vector2.ZERO)
	var idx: PackedInt32Array = PackedInt32Array()
	for j: int in SEGS:
		var j2: int = (j + 1) % SEGS
		for i: int in n - 1:
			var a: int = j * n + i
			var b: int = j2 * n + i
			var c: int = j * n + i + 1
			var d: int = j2 * n + i + 1
			idx.append_array([a, b, c, b, d, c])
	return _finish(verts, idx, uvs, Vector3(0.0, hint_y, 0.0), false)


## Orient every triangle as a Godot front face seen from outside (outward is
## away from `center`, or along -`center` when `planar`), then build smooth
## normals and tangents.
static func _finish(verts: PackedVector3Array, idx: PackedInt32Array, uvs: PackedVector2Array, center: Vector3, planar: bool) -> ArrayMesh:
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
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Materials --------------------------------------------------------------------

static func _wax_material() -> ShaderMaterial:
	if _wax_mat == null:
		_wax_mat = ShaderMaterial.new()
		_wax_mat.shader = WAX_SHADER
	return _wax_mat


static func _emblem_material(points: int) -> ShaderMaterial:
	if _emblem_mats.has(points):
		return _emblem_mats[points]
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = WAX_SHADER
	mat.set_shader_parameter(&"emblem_tex", _emblem_texture(points))
	mat.set_shader_parameter(&"emblem_strength", 1.6)
	_emblem_mats[points] = mat
	return mat


## Embossed signet: a raised rim, a ring of beads, and an n-pointed star with a
## sunken centre, as a tangent-space normal map (OpenGL convention).
static func _emblem_texture(points: int) -> ImageTexture:
	const S: int = 128
	var height: PackedFloat32Array = PackedFloat32Array()
	height.resize(S * S)
	for y: int in S:
		for x: int in S:
			var p: Vector2 = Vector2((float(x) + 0.5) / S * 2.0 - 1.0, (float(y) + 0.5) / S * 2.0 - 1.0)
			var r: float = p.length()
			var th: float = atan2(p.y, p.x) + PI * 0.5
			var h: float = 0.0
			h += smoothstep(0.86, 0.9, r) * (1.0 - smoothstep(0.96, 1.0, r))  # rim
			var bead_th: float = wrapf(th * 12.0 / TAU, 0.0, 1.0) - 0.5
			var bead_d: Vector2 = Vector2(bead_th * TAU * 0.76 / 12.0, r - 0.76)
			h += (1.0 - smoothstep(0.025, 0.045, bead_d.length())) * 0.8  # bead ring
			var sector: float = wrapf(th * float(points) / TAU, 0.0, 1.0)
			var spike: float = absf(sector - 0.5) * 2.0  # 0 at a point, 1 between
			var star_r: float = lerpf(0.62, 0.3, pow(spike, 0.8))
			h += (1.0 - smoothstep(star_r - 0.03, star_r, r)) * 0.9  # star
			h -= (1.0 - smoothstep(0.1, 0.13, r)) * 0.7  # sunken centre
			height[y * S + x] = h
	var img: Image = Image.create(S, S, false, Image.FORMAT_RGB8)
	const K: float = 3.0
	for y: int in S:
		for x: int in S:
			var hl: float = height[y * S + maxi(x - 1, 0)]
			var hr: float = height[y * S + mini(x + 1, S - 1)]
			var hu: float = height[maxi(y - 1, 0) * S + x]
			var hd: float = height[mini(y + 1, S - 1) * S + x]
			var n: Vector3 = Vector3(-(hr - hl) * K, (hd - hu) * K, 1.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _cork_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = _cork_texture()
	mat.roughness = 0.92
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat


## Cork grain: warm tan with dark pores and lighter flecks.
static func _cork_texture() -> ImageTexture:
	if _cork_tex != null:
		return _cork_tex
	const S: int = 64
	var img: Image = Image.create(S, S, false, Image.FORMAT_RGB8)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.18
	noise.fractal_octaves = 3
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9
	for y: int in S:
		for x: int in S:
			var v: float = noise.get_noise_2d(float(x), float(y))
			var c: Color = Color(0.62, 0.45, 0.28) * (1.0 + v * 0.22)
			if rng.randf() < 0.07:
				c = c.darkened(rng.randf_range(0.35, 0.6))
			elif rng.randf() < 0.05:
				c = c.lightened(0.15)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_cork_tex = ImageTexture.create_from_image(img)
	return _cork_tex
