class_name RecipeBoard3D
extends Node3D
## Recipe notes pinned to a small corkboard at the edge of the potion bench
## wall (out of the way of the tall glassware), in a grid.
## Learned recipes glow: their rune borders pulse in the colour of their
## grimoire category and their titles shine gold; the newest come first.
## Unlearned pages stay dim and read "???". A new discovery makes its page flare.

const PAGE_SIZE: Vector2 = Vector2(0.11, 0.13)
const CATEGORY_COLORS: Array[Color] = [Color("#5CE1E6"), Color("#B18CFF"), Color("#FF6B9D"), Color("#F4D06F")]
const SHADER: Shader = preload("res://visuals_3d/shaders/glowing_page.gdshader")

@export var page_count: int = 6
@export var spacing_meters: float = 0.24
## Grid layout on a corkboard (columns), and how big each note is drawn.
@export var columns: int = 3
@export var page_scale: float = 0.6

var _pages: Array[Dictionary] = []


func _ready() -> void:
	_build_corkboard()
	for i: int in page_count:
		_pages.append(_make_page(i))
	if RecipeBook.instance != null:
		RecipeBook.instance.recipe_discovered.connect(func(r: RecipeData, _v: Vessel3D) -> void: refresh(r))
	refresh.call_deferred(null)


func _make_page(i: int) -> Dictionary:
	var root: Node3D = Node3D.new()
	var col: int = i % columns
	var row: int = i / columns
	var cell: Vector2 = PAGE_SIZE * page_scale + Vector2(0.012, 0.014)
	root.position = Vector3((float(col) - float(columns - 1) * 0.5) * cell.x, -float(row) * cell.y, 0.012)
	root.scale = Vector3.ONE * page_scale
	# A slight, random tilt like hand-pinned notes.
	root.rotation.z = (fmod(float(i) * 0.6180339, 1.0) - 0.5) * 0.12
	add_child(root)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = PAGE_SIZE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"parchment", Vessel3D.parchment_texture())
	mat.set_shader_parameter(&"seed", float(i) * 7.31)
	var page: MeshInstance3D = MeshInstance3D.new()
	page.mesh = quad
	page.material_override = mat
	page.position.y = -PAGE_SIZE.y * 0.5
	root.add_child(page)
	# Brass pin at the top.
	var pin_mesh: SphereMesh = SphereMesh.new()
	pin_mesh.radius = 0.004
	pin_mesh.height = 0.008
	pin_mesh.radial_segments = 12
	pin_mesh.rings = 6
	var pin_mat: StandardMaterial3D = StandardMaterial3D.new()
	pin_mat.albedo_color = Color(0.85, 0.65, 0.3)
	pin_mat.metallic = 0.9
	pin_mat.roughness = 0.3
	pin_mesh.material = pin_mat
	var pin: MeshInstance3D = MeshInstance3D.new()
	pin.mesh = pin_mesh
	pin.position = Vector3(0.0, -0.008, 0.004)
	root.add_child(pin)
	var title: Label3D = _label(36, Vector3(0.0, -0.022, 0.001), PAGE_SIZE.x * 0.76, 0.00026)
	root.add_child(title)
	var body: Label3D = _label(24, Vector3(0.0, -0.074, 0.001), PAGE_SIZE.x * 0.76, 0.00024)
	root.add_child(body)
	return {"mat": mat, "title": title, "body": body}


func _label(font_size: int, at: Vector3, width_m: float, pixel_m: float) -> Label3D:
	var l: Label3D = Label3D.new()
	l.font = CosmicTheme.display_font()
	l.font_size = font_size
	l.pixel_size = pixel_m
	l.outline_size = 0
	l.width = width_m / l.pixel_size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.position = at
	l.shaded = false
	l.double_sided = false
	return l


## Show learned recipes first (newest first), then mysteries to aim for.
func refresh(just_found: RecipeData = null) -> void:
	var book: RecipeBook = RecipeBook.instance
	if book == null:
		return
	var journal: GrimoireJournal = GrimoireJournal.instance
	var known: Array[RecipeData] = []
	var unknown: Array[RecipeData] = []
	for r: RecipeData in book.recipes:
		if book.is_discovered(r):
			known.append(r)
		else:
			unknown.append(r)
	if journal != null:
		known.sort_custom(func(a: RecipeData, b: RecipeData) -> bool:
			return float(journal.discovery_of(a.recipe_id).get("time", 0.0)) > float(journal.discovery_of(b.recipe_id).get("time", 0.0)))
	var shown: Array[RecipeData] = known.slice(0, page_count)
	var k: int = 0
	while shown.size() < page_count and k < unknown.size():
		shown.append(unknown[k])
		k += 1
	for i: int in _pages.size():
		var p: Dictionary = _pages[i]
		var mat: ShaderMaterial = p["mat"]
		var title: Label3D = p["title"]
		var body: Label3D = p["body"]
		if i >= shown.size():
			title.text = ""
			body.text = ""
			mat.set_shader_parameter(&"glow_strength", 0.0)
			continue
		var r: RecipeData = shown[i]
		var is_known: bool = book.is_discovered(r)
		var col: Color = CATEGORY_COLORS[clampi(int(r.category), 0, CATEGORY_COLORS.size() - 1)]
		mat.set_shader_parameter(&"glow_color", col)
		mat.set_shader_parameter(&"glow_strength", 1.0 if is_known else 0.0)
		if is_known:
			title.text = r.title
			title.modulate = Color(1.05, 0.66, 0.2)
			body.text = r.formula
			body.modulate = Color(col.r * 0.9, col.g * 0.9, col.b * 0.9)
		else:
			title.text = "???"
			title.modulate = Color(0.35, 0.22, 0.12)
			body.text = "a sealed riddle" if r.category == RecipeData.Category.SECRET else "brew it to reveal"
			body.modulate = Color(0.4, 0.28, 0.16)
		if r == just_found:
			var tw: Tween = create_tween()
			tw.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"flash", v), 1.5, 0.0, 2.5)



## Cork panel in a dark wooden frame behind the notes.
func _build_corkboard() -> void:
	var rows: int = int(ceil(float(page_count) / float(columns)))
	var cell: Vector2 = PAGE_SIZE * page_scale + Vector2(0.012, 0.014)
	var size: Vector2 = Vector2(cell.x * columns + 0.02, cell.y * rows + 0.02)
	var top_y: float = 0.012
	var cork: StandardMaterial3D = StandardMaterial3D.new()
	cork.albedo_color = Color(0.6, 0.42, 0.26)
	cork.roughness = 1.0
	cork.albedo_texture = Vessel3D.parchment_texture()
	cork.uv1_scale = Vector3(3.0, 3.0, 1.0)
	var frame: StandardMaterial3D = PropMaterials.textured("wood", Color(0.25, 0.15, 0.08), 0.3)
	var panel: MeshInstance3D = MeshInstance3D.new()
	var panel_mesh: BoxMesh = BoxMesh.new()
	panel_mesh.size = Vector3(size.x, size.y, 0.01)
	panel_mesh.material = cork
	panel.mesh = panel_mesh
	panel.position = Vector3(0.0, top_y - size.y * 0.5, 0.004)
	add_child(panel)
	for side: Vector4 in [Vector4(0.0, top_y + 0.006, size.x + 0.024, 0.012), Vector4(0.0, top_y - size.y - 0.006, size.x + 0.024, 0.012),
			Vector4(-size.x * 0.5 - 0.006, top_y - size.y * 0.5, 0.012, size.y), Vector4(size.x * 0.5 + 0.006, top_y - size.y * 0.5, 0.012, size.y)]:
		var bar: MeshInstance3D = MeshInstance3D.new()
		var bar_mesh: BoxMesh = BoxMesh.new()
		bar_mesh.size = Vector3(side.z, side.w, 0.016)
		bar_mesh.material = frame
		bar.mesh = bar_mesh
		bar.position = Vector3(side.x, side.y, 0.006)
		add_child(bar)
