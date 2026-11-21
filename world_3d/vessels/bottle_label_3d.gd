class_name BottleLabel3D
extends Node3D
## A parchment label that wraps around the glass. The label is one curved
## strip whose radius follows the outside of the glass mesh row by row, so it
## sits flush on straight, conical and round bodies alike. The colour strip,
## category stamp and text are all painted into the strip's own texture (a
## small SubViewport that redraws only when the text or stamp changes), so
## nothing floats off the glass at the edges or when seen from the side.

const ICON_SHADER: Shader = preload("res://visuals_3d/shaders/label_icon_2d.gdshader")
## Texture height in pixels; the width follows the label's aspect.
const TEX_HEIGHT_PX: int = 320
const MAX_ARC_RAD: float = 2.3  # never wrap more than ~130 degrees
const GAP_METERS: float = 0.0009  # sits just proud of the glass

var _mesh: MeshInstance3D
var _viewport: SubViewport
var _paper: TextureRect
var _strip: ColorRect
var _icon: ColorRect
var _text: Label
var _tex_size: Vector2i = Vector2i(400, TEX_HEIGHT_PX)
var _category: int = -1
var _tint: Color = Color(0.2, 0.55, 0.6)


## Build the label around `vessel` at the best band of its body.
## `inner_radius_at` is the vessel's cavity radius at a local height and is
## used when the glass mesh can't be read.
func setup(glass_mesh: Mesh, foot_y: float, lip_y: float, fallback_outer_r: float, inner_radius_at: Callable) -> void:
	var outer: Callable = _outer_radius_lookup(glass_mesh, foot_y, lip_y, fallback_outer_r, inner_radius_at)
	var body_h: float = lip_y - foot_y
	# Pick the band with the most room: the largest smallest-radius over the
	# label height, preferring lower bands (the shoulder of round flasks).
	var best_y: float = lerpf(foot_y, lip_y, 0.36)
	var best_score: float = -1.0
	var r_mid: float = float(outer.call(best_y))
	var h: float = clampf(r_mid * 1.0, 0.016, 0.036)
	for k: int in 17:
		var y: float = lerpf(foot_y + body_h * 0.14, foot_y + body_h * 0.62, float(k) / 16.0)
		var r_lo: float = 1e9
		var r_hi: float = 0.0
		for s: int in 5:
			var r: float = float(outer.call(y + (float(s) / 4.0 - 0.5) * h))
			r_lo = minf(r_lo, r)
			r_hi = maxf(r_hi, r)
		var score: float = r_lo - (r_hi - r_lo) * 1.5 - (y - foot_y) / body_h * r_lo * 0.12
		if score > best_score:
			best_score = score
			best_y = y
	var r0: float = float(outer.call(best_y))
	var w: float = minf(minf(r0 * 1.65, 0.078), r0 * MAX_ARC_RAD)
	# Slim vials get a taller label so the name still has room.
	h = clampf(r0 * (1.0 if w > 0.05 else 1.35), 0.016, 0.036)
	_tex_size = Vector2i(int(round(float(TEX_HEIGHT_PX) * w / h)), TEX_HEIGHT_PX)
	_build_viewport()
	_build_mesh(outer, best_y, w, h)


## Outer radius of the glass at a local height, sampled from the glass mesh
## (largest radius per height bin), else the cavity plus wall.
func _outer_radius_lookup(glass_mesh: Mesh, foot_y: float, lip_y: float, fallback_r: float, inner_radius_at: Callable) -> Callable:
	const BINS: int = 48
	var bins: PackedFloat32Array = PackedFloat32Array()
	bins.resize(BINS)
	bins.fill(0.0)
	var have: bool = false
	if glass_mesh != null and glass_mesh.get_surface_count() > 0 and not glass_mesh is PrimitiveMesh:
		var span: float = maxf(lip_y - foot_y, 0.01)
		for s: int in glass_mesh.get_surface_count():
			var arrays: Array = glass_mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var b: int = int(floor((v.y - foot_y) / span * float(BINS)))
				if b < 0 or b >= BINS:
					continue
				bins[b] = maxf(bins[b], Vector2(v.x, v.z).length())
				have = true
	if have:
		# Fill empty bins from their neighbours.
		for b: int in BINS:
			if bins[b] <= 0.0:
				bins[b] = bins[b - 1] if b > 0 else fallback_r
		var span2: float = maxf(lip_y - foot_y, 0.01)
		return func(y: float) -> float:
			var f: float = clampf((y - foot_y) / span2 * float(BINS) - 0.5, 0.0, float(BINS - 1))
			var i: int = int(floor(f))
			var j: int = mini(i + 1, BINS - 1)
			return lerpf(bins[i], bins[j], f - float(i))
	return func(y: float) -> float:
		var r: float = float(inner_radius_at.call(y)) + 0.003 if inner_radius_at.is_valid() else fallback_r
		return minf(maxf(r, 0.004), fallback_r)


func _build_mesh(outer: Callable, mid_y: float, w: float, h: float) -> void:
	const COLS: int = 28
	const ROWS: int = 6
	var r0: float = float(outer.call(mid_y))
	var arc: float = w / r0
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in ROWS + 1:
		var v: float = float(row) / float(ROWS)
		var y: float = mid_y + (0.5 - v) * h
		var r: float = float(outer.call(y)) + GAP_METERS
		for col: int in COLS + 1:
			var u: float = float(col) / float(COLS)
			var a: float = (u - 0.5) * arc
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3(sin(a), 0.0, cos(a)))
			st.add_vertex(Vector3(sin(a) * r, y, cos(a) * r))
	for row: int in ROWS:
		for col: int in COLS:
			var i: int = row * (COLS + 1) + col
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + COLS + 1)
			st.add_index(i + 1)
			st.add_index(i + COLS + 2)
			st.add_index(i + COLS + 1)
	st.generate_tangents()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.roughness = 0.88
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	_mesh = MeshInstance3D.new()
	_mesh.name = &"LabelStrip"
	_mesh.mesh = st.commit()
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = _tex_size
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.msaa_2d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var size: Vector2 = Vector2(_tex_size)
	var root: Control = Control.new()
	root.size = size
	_viewport.add_child(root)
	_paper = TextureRect.new()
	_paper.texture = Vessel3D.parchment_texture()
	_paper.stretch_mode = TextureRect.STRETCH_SCALE
	_paper.size = size
	_paper.modulate = Color(1.02, 0.98, 0.92)
	root.add_child(_paper)
	# Narrow labels (vials) keep the colour strip and tuck a small stamp in
	# its top corner so the name gets the whole width.
	var compact: bool = size.x < size.y * 2.3
	_strip = ColorRect.new()
	_strip.position = Vector2(size.y * 0.06, 0.0)
	_strip.size = Vector2(size.y * (0.1 if compact else 0.12), size.y)
	root.add_child(_strip)
	var icon_px: float = size.y * (0.3 if compact else 0.5)
	_icon = ColorRect.new()
	var icon_mat: ShaderMaterial = ShaderMaterial.new()
	icon_mat.shader = ICON_SHADER
	_icon.material = icon_mat
	if compact:
		_icon.position = Vector2(size.x - icon_px - size.y * 0.07, size.y * 0.07)
	else:
		_icon.position = Vector2(_strip.position.x + _strip.size.x + size.y * 0.1, (size.y - icon_px) * 0.5)
	_icon.size = Vector2(icon_px, icon_px)
	root.add_child(_icon)
	_text = Label.new()
	var text_left: float = _strip.position.x + _strip.size.x + size.y * 0.1
	if not compact:
		text_left = _icon.position.x + icon_px + size.y * 0.1
	var text_right: float = size.x - size.y * (0.12 if not compact else 0.1)
	var top: float = size.y * (0.08 if not compact else 0.3)
	_text.position = Vector2(text_left, top)
	_text.size = Vector2(text_right - text_left, size.y * 0.94 - top)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_text.clip_text = false
	_text.add_theme_font_override(&"font", CosmicTheme.world_font())
	_text.add_theme_color_override(&"font_color", Color(0.118, 0.086, 0.063))
	_text.add_theme_constant_override(&"line_spacing", -4)
	root.add_child(_text)


var text: String:
	get:
		return _text.text if _text != null else ""


func set_text(t: String) -> void:
	if _text == null or _text.text == t:
		return
	_text.text = t
	_fit_text()
	_redraw()


func set_category(category: int, tint: Color) -> void:
	if category == _category or _icon == null:
		return
	_category = category
	_tint = tint
	_strip.color = tint
	var mat: ShaderMaterial = _icon.material as ShaderMaterial
	mat.set_shader_parameter(&"icon", category)
	mat.set_shader_parameter(&"tint", tint)
	_redraw()


## Largest font size at which whole words fit in two lines (three for long
## names), with the formula line allowed to be smaller.
func _fit_text() -> void:
	var f: Font = CosmicTheme.world_font()
	var box: Vector2 = _text.size
	var size_px: int = int(box.y * 0.46)
	var fit_w: float = box.x * 0.92  # Label pads glyph edges a little
	var words: PackedStringArray = _text.text.replace("\n", " ").split(" ", false)
	while size_px > 14:
		var longest: float = 0.0
		for word: String in words:
			longest = maxf(longest, f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
		var lines: int = _wrapped_lines(f, size_px, fit_w)
		var line_h: float = f.get_height(size_px) - 4.0
		if longest <= fit_w and float(lines) * line_h <= box.y:
			break
		size_px -= 2
	_text.add_theme_font_size_override(&"font_size", size_px)


func _wrapped_lines(f: Font, size_px: int, width_px: float) -> int:
	var lines: int = 0
	var space: float = f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	for part: String in _text.text.split("\n"):
		var x: float = 0.0
		lines += 1
		for word: String in part.split(" ", false):
			var w: float = f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
			if x > 0.0 and x + space + w > width_px:
				lines += 1
				x = w
			else:
				x += (space if x > 0.0 else 0.0) + w
	return lines


func _redraw() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
