class_name SafetySheetUI
extends CanvasLayer
## Full-screen Safety Data Sheet viewer (press S on a held or hovered vessel,
## or open from the Grimoire). Renders SafetySheet.build() as a printed
## WHMIS-style sheet with red-diamond pictograms.

static var instance: SafetySheetUI = null

const PAPER: Color = Color(0.98, 0.97, 0.94)
const INK: Color = Color(0.1, 0.1, 0.12)
const FADED: Color = Color(0.4, 0.4, 0.42)
const BAR: Color = Color(0.12, 0.12, 0.14)

var _root: Control
var _content: VBoxContainer
var _scroll: ScrollContainer


## Red-bordered diamond with a vector symbol for one hazard class.
class PictogramView:
	extends Control
	var kind: int = 0

	func _init(k: int) -> void:
		kind = k
		custom_minimum_size = Vector2(96, 96)
		tooltip_text = SafetySheet.PICTOGRAM_NAMES[k]

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.48
		var diamond: PackedVector2Array = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		var border: Color = Color(0.85, 0.08, 0.08) if kind != SafetySheet.Pictogram.ARCANE and kind != SafetySheet.Pictogram.SILLY else (Color(0.45, 0.2, 0.85) if kind == SafetySheet.Pictogram.ARCANE else Color(0.95, 0.55, 0.05))
		draw_colored_polygon(diamond, Color.WHITE)
		diamond.append(diamond[0])
		draw_polyline(diamond, border, r * 0.12, true)
		var k: Color = Color(0.05, 0.05, 0.05)
		var s: float = r * 0.42
		match kind:
			SafetySheet.Pictogram.FLAME:
				_flame(c + Vector2(0, s * 0.15), s, k)
				draw_line(c + Vector2(-s * 0.8, s * 0.95), c + Vector2(s * 0.8, s * 0.95), k, 4.0)
			SafetySheet.Pictogram.FLAME_OVER_CIRCLE:
				draw_arc(c + Vector2(0, s * 0.55), s * 0.42, 0.0, TAU, 24, k, 4.0)
				_flame(c + Vector2(0, -s * 0.2), s * 0.75, k)
				draw_line(c + Vector2(-s * 0.8, s * 1.1), c + Vector2(s * 0.8, s * 1.1), k, 4.0)
			SafetySheet.Pictogram.SKULL:
				draw_circle(c + Vector2(0, -s * 0.25), s * 0.55, k)
				draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.05), Vector2(s * 0.6, s * 0.4)), k)
				draw_circle(c + Vector2(-s * 0.22, -s * 0.3), s * 0.15, Color.WHITE)
				draw_circle(c + Vector2(s * 0.22, -s * 0.3), s * 0.15, Color.WHITE)
				draw_line(c + Vector2(-s * 0.9, s * 0.55), c + Vector2(s * 0.9, s * 1.05), k, 5.0)
				draw_line(c + Vector2(s * 0.9, s * 0.55), c + Vector2(-s * 0.9, s * 1.05), k, 5.0)
			SafetySheet.Pictogram.CORROSION:
				draw_line(c + Vector2(-s * 0.9, -s * 0.8), c + Vector2(-s * 0.3, -s * 0.3), k, 6.0)
				draw_line(c + Vector2(s * 0.9, -s * 0.8), c + Vector2(s * 0.3, -s * 0.3), k, 6.0)
				draw_circle(c + Vector2(-s * 0.3, s * 0.05), s * 0.1, k)
				draw_circle(c + Vector2(s * 0.3, s * 0.05), s * 0.1, k)
				draw_rect(Rect2(c + Vector2(-s, s * 0.5), Vector2(s * 0.8, s * 0.3)), k)
				draw_rect(Rect2(c + Vector2(s * 0.2, s * 0.5), Vector2(s * 0.8, s * 0.3)), k)
			SafetySheet.Pictogram.HEALTH:
				draw_circle(c + Vector2(0, -s * 0.7), s * 0.25, k)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.55, -s * 0.35), c + Vector2(s * 0.55, -s * 0.35), c + Vector2(s * 0.45, s * 1.0), c + Vector2(-s * 0.45, s * 1.0)]), k)
				for a: int in 8:
					var ang: float = TAU * float(a) / 8.0
					draw_line(c + Vector2(0, s * 0.25) + Vector2(cos(ang), sin(ang)) * s * 0.08, c + Vector2(0, s * 0.25) + Vector2(cos(ang), sin(ang)) * s * 0.32, Color.WHITE, 3.0)
			SafetySheet.Pictogram.EXCLAMATION:
				draw_rect(Rect2(c + Vector2(-s * 0.13, -s * 0.9), Vector2(s * 0.26, s * 1.25)), k)
				draw_circle(c + Vector2(0, s * 0.75), s * 0.16, k)
			SafetySheet.Pictogram.ENVIRONMENT:
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.4, -s * 0.9), c + Vector2(-s * 0.05, s * 0.2), c + Vector2(-s * 0.75, s * 0.2)]), k)
				draw_line(c + Vector2(-s * 0.4, s * 0.2), c + Vector2(-s * 0.4, s * 0.5), k, 4.0)
				draw_circle(c + Vector2(s * 0.35, s * 0.55), s * 0.28, k)
				draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.6, s * 0.55), c + Vector2(s * 0.95, s * 0.3), c + Vector2(s * 0.95, s * 0.8)]), k)
				draw_line(c + Vector2(-s, s * 0.95), c + Vector2(s, s * 0.95), k, 3.0)
			SafetySheet.Pictogram.GAS_CYLINDER:
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.9, -s * 0.25), c + Vector2(s * 0.7, -s * 0.25), c + Vector2(s * 0.95, 0), c + Vector2(s * 0.7, s * 0.25), c + Vector2(-s * 0.9, s * 0.25)]), k)
				draw_rect(Rect2(c + Vector2(s * 0.85, -s * 0.12), Vector2(s * 0.2, s * 0.24)), k)
			SafetySheet.Pictogram.ARCANE:
				var pts: PackedVector2Array = PackedVector2Array()
				for i: int in 6:
					var ang2: float = -PI * 0.5 + TAU * float(i * 2 % 5) / 5.0
					pts.append(c + Vector2(cos(ang2), sin(ang2)) * s * 0.95)
				draw_polyline(pts, Color(0.35, 0.1, 0.7), 3.5, true)
				draw_arc(c, s * 0.98, 0.0, TAU, 32, Color(0.35, 0.1, 0.7), 2.5)
			SafetySheet.Pictogram.SILLY:
				draw_circle(c, s * 0.85, Color(1.0, 0.85, 0.2))
				draw_circle(c + Vector2(-s * 0.3, -s * 0.2), s * 0.12, k)
				draw_circle(c + Vector2(s * 0.3, -s * 0.25), s * 0.18, k)
				draw_arc(c + Vector2(0, s * 0.1), s * 0.45, 0.3, PI - 0.3, 16, k, 3.5)
				draw_circle(c + Vector2(s * 0.12, s * 0.58), s * 0.15, Color(0.95, 0.35, 0.45))

	func _flame(base: Vector2, s: float, col: Color) -> void:
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in 17:
			var t: float = float(i) / 16.0
			var a: float = PI + t * TAU
			var w: float = s * 0.55 * sin(t * PI)
			pts.append(base + Vector2(cos(a) * w * 0.0 + (t - 0.5) * s * 1.1, -sin(t * PI) * s * 1.6 * (0.6 + 0.4 * absf(sin(t * 3.0 * PI)))))
		pts.append(base + Vector2(s * 0.55, s * 0.6))
		pts.append(base + Vector2(-s * 0.55, s * 0.6))
		draw_colored_polygon(pts, col)


func _ready() -> void:
	instance = self
	layer = 30
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	CosmicTheme.apply(_root)
	add_child(_root)
	# The sheet itself stays a crisp real-world paper document; the astral
	# backdrop frames it like the rest of the cosmic UI.
	var dim: ColorRect = CosmicTheme.backdrop(0.85)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	_root.add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	var paper: StyleBoxFlat = GrimoireBookUI._box(PAPER, CosmicTheme.STARLIGHT_GOLD, 2, 4, 28)
	paper.shadow_color = Color(CosmicTheme.VIOLET, 0.45)
	paper.shadow_size = 22
	panel.add_theme_stylebox_override(&"panel", paper)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.04
	panel.anchor_bottom = 0.96
	panel.offset_left = -560
	panel.offset_right = 560
	_root.add_child(panel)
	var outer: VBoxContainer = VBoxContainer.new()
	panel.add_child(outer)
	var top: HBoxContainer = HBoxContainer.new()
	outer.add_child(top)
	var title: Label = _label("SAFETY DATA SHEET   ·   WHMIS 2015 / GHS", 18, FADED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_btn: Button = Button.new()
	close_btn.text = "Close  [Esc]"
	close_btn.pressed.connect(close)
	top.add_child(close_btn)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override(&"separation", 6)
	_scroll.add_child(_content)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.keycode == KEY_S):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false
	TactileGrabber3D.input_captured = false


func open_for_vessel(v: Vessel3D) -> void:
	open_for_mixture(v.mixture, "", v.foam_height_meters, v.get_meta(&"assay", {}))


func open_for_mixture(m: MixtureContainer, product_name: String = "", foam_m: float = 0.0, assay: Dictionary = {}) -> void:
	render(SafetySheet.build(m, product_name, foam_m, assay))
	visible = true
	TactileGrabber3D.input_captured = true
	_scroll.scroll_vertical = 0


## A pure substance's sheet (1 mol at room temperature).
func open_for_substance(s: SubstanceData) -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(SubstanceRegistry.index_of(s), 1.0, SimConstants.AMBIENT_TEMP_KELVIN)
	open_for_mixture(m, s.display_name)


func render(sheet: Dictionary) -> void:
	for child: Node in _content.get_children():
		child.queue_free()
	_content.add_child(_label(String(sheet["name"]), 30, INK))
	_content.add_child(_label(String(sheet["formula"]), 18, Color(0.45, 0.12, 0.08)))
	var signal_word: String = sheet["signal"]
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	_content.add_child(row)
	if signal_word != "NONE":
		var sig: Label = _label(signal_word if signal_word != "SILLY" else "SILLY!", 34,
			{"DANGER": Color(0.8, 0.05, 0.05), "WARNING": Color(0.85, 0.45, 0.0), "SILLY": Color(0.55, 0.2, 0.85)}[signal_word])
		sig.custom_minimum_size = Vector2(190, 0)
		row.add_child(sig)
	for p: int in sheet["pictograms"]:
		var box: VBoxContainer = VBoxContainer.new()
		box.add_child(PictogramView.new(p))
		var cap: Label = _label(SafetySheet.PICTOGRAM_NAMES[p], 12, FADED)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(cap)
		row.add_child(box)
	_section("1   Identification")
	_lines(PackedStringArray(["Product: %s" % sheet["name"], "Recommended use: %s" % ("fun science & make-believe potion play (with a grown-up)" if sheet["kid"] else "laboratory alchemy and research"),
		"Supplier: Your Alchemy Lab, Workbench 1"]))
	_section("2   Hazard identification")
	_lines(sheet["hazards"], "⚠  ")
	_content.add_child(_label("Precautions", 15, FADED))
	_lines(sheet["precautions"], "•  ")
	if not (sheet["silly"] as PackedStringArray).is_empty():
		var silly_panel: PanelContainer = PanelContainer.new()
		silly_panel.add_theme_stylebox_override(&"panel", GrimoireBookUI._box(Color(1.0, 0.95, 0.7), Color(0.95, 0.6, 0.1), 2, 8, 12))
		var sv: VBoxContainer = VBoxContainer.new()
		silly_panel.add_child(sv)
		sv.add_child(_label("SILLY HAZARDS  (100% made up, 100% true)", 17, Color(0.6, 0.3, 0.0)))
		for line: String in sheet["silly"]:
			sv.add_child(_wrap("★  " + line, 15, INK))
		for note: String in sheet["label_notes"]:
			sv.add_child(_wrap("From the label  ·  " + note, 13, FADED))
		_content.add_child(silly_panel)
	_section("3   Composition / information on ingredients")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 24)
	_content.add_child(grid)
	for h: String in ["Ingredient", "Formula", "CAS No.", "% by mass"]:
		grid.add_child(_label(h, 14, FADED))
	for c: Array in sheet["composition"]:
		grid.add_child(_label(String(c[0]), 14, INK))
		grid.add_child(_label(String(c[1]), 14, INK))
		grid.add_child(_label(String(c[2]), 14, INK))
		grid.add_child(_label("%.1f" % float(c[3]) if float(c[3]) >= 0.1 else "< 0.1", 14, INK))
	_section("4   First-aid measures")
	_lines(sheet["first_aid"], "•  ")
	_section("5   Fire-fighting measures")
	_lines(sheet["fire"], "•  ")
	_section("9   Physical and chemical properties")
	var pgrid: GridContainer = GridContainer.new()
	pgrid.columns = 3
	pgrid.add_theme_constant_override(&"h_separation", 24)
	_content.add_child(pgrid)
	for prop: Array in sheet["properties"]:
		pgrid.add_child(_label(String(prop[0]), 14, FADED))
		pgrid.add_child(_label(String(prop[1]), 14, INK))
		pgrid.add_child(_label("✓ measured" if bool(prop[2]) else "calculated", 12, Color(0.15, 0.5, 0.2) if bool(prop[2]) else FADED))
	_content.add_child(_wrap("Tip: set the vessel on the Science Bench instruments to replace calculated values with measured ones.", 12, FADED))
	_section("10   Stability and reactivity")
	_lines(sheet["reactions"], "⇌  ")
	_section("11   Toxicological information")
	_lines(sheet["toxicology"], "•  ")
	_section("13   Disposal")
	_lines(PackedStringArray(["Neutralise acids and bases before disposal. Collect metals, oxidizers and toxic waste in labelled jars.",
		"Never pour arcane residues down the drain (the sink frogs complain)."]), "•  ")


func _section(text: String) -> void:
	var bar: PanelContainer = PanelContainer.new()
	bar.add_theme_stylebox_override(&"panel", GrimoireBookUI._box(BAR, BAR, 0, 2, 6))
	bar.add_child(_label(text.to_upper(), 15, Color(0.97, 0.97, 0.95)))
	_content.add_child(bar)


func _lines(lines: PackedStringArray, bullet: String = "") -> void:
	for line: String in lines:
		_content.add_child(_wrap(bullet + line, 15, INK))


func _label(text: String, size_px: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", color)
	return l


func _wrap(text: String, size_px: int, color: Color) -> Label:
	var l: Label = _label(text, size_px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1000, 0)
	return l
