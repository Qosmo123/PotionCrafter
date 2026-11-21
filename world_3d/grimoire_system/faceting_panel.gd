extends CanvasLayer
## Faceting Station panel (Mineral Lab): a visual cut picker with each cut's
## silhouette, how well it suits the stone you're holding or cutting, mastery
## badges, a quick-facet toggle for mastered cuts, and live meters for cut
## progress, hand steadiness and projected clarity. Opens from the faceting
## machine's dial or the F key; [ and ] step through cuts. Presentation only:
## the machine (LapidaryWheel3D) owns all cutting logic.

const PANEL_WIDTH: float = 400.0


## Draws a cut's outline as a gem silhouette with facet lines.
class CutSilhouette:
	extends Control
	var cut: int = 1
	var tint: Color = CosmicTheme.PRISM_CYAN

	func _draw() -> void:
		var pts: PackedVector2Array = RockMeshes.outline(cut)
		if pts.size() < 3:
			return
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.42
		var poly: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in pts:
			poly.append(c + p * r)
		draw_colored_polygon(poly, Color(tint, 0.22))
		for i: int in poly.size():
			if i % maxi(poly.size() / 8, 1) == 0:
				draw_line(c, poly[i], Color(tint, 0.35), 1.0, true)
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, Color(CosmicTheme.STARLIGHT_GOLD, 0.9), 1.5, true)
		draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.08, Color(1, 1, 1, 0.6))


var _root: PanelContainer
var _stone_label: Label
var _grid: GridContainer
var _cards: Array[Button] = []
var _info: Label
var _quick: CheckButton
var _progress: ProgressBar
var _steady: ProgressBar
var _quality: ProgressBar
var _quality_label: Label
var _open: bool = false
var _last_stone: Rock3D = null
var _auto_opened: bool = false


func _ready() -> void:
	layer = 7
	var shell: Control = Control.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CosmicTheme.apply(shell)
	add_child(shell)
	_root = PanelContainer.new()
	_root.position = Vector2(CosmicTheme.GUTTER, 84)
	_root.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_root.add_theme_stylebox_override(&"panel", CosmicTheme.glass(CosmicTheme.PRISM_CYAN, 18, 2))
	CosmicTheme.frost(_root)
	_root.visible = false
	shell.add_child(_root)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	_root.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	col.add_child(head)
	var t: Label = CosmicTheme.title("◆  Faceting Station", 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close: Button = Button.new()
	close.text = "✕"
	close.tooltip_text = "Close (F)"
	close.custom_minimum_size = Vector2(40, 36)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	_stone_label = CosmicTheme.label("", 15, CosmicTheme.TEXT_DIM)
	_stone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stone_label.custom_minimum_size.x = PANEL_WIDTH - 40.0
	col.add_child(_stone_label)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override(&"h_separation", 6)
	_grid.add_theme_constant_override(&"v_separation", 6)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	for cut: int in range(1, RockMeshes.CUT_NAMES.size()):
		_grid.add_child(_make_card(cut))
	_info = CosmicTheme.label("", 15, CosmicTheme.TEXT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = PANEL_WIDTH - 40.0
	col.add_child(_info)
	_quick = CheckButton.new()
	_quick.text = "⚡ Quick-facet (mastered cuts: 4× faster, keeps your best form)"
	_quick.add_theme_font_size_override(&"font_size", 13)
	_quick.toggled.connect(func(on: bool) -> void:
		var f: LapidaryWheel3D = LapidaryWheel3D.faceter
		if f != null:
			f.quick_facet = on and LapidaryWheel3D.is_mastered(f.selected_cut)
			f._update_status())
	col.add_child(_quick)
	_progress = _meter(col, "Facets cut", CosmicTheme.PRISM_CYAN)
	_steady = _meter(col, "Steady hand", CosmicTheme.SUCCESS)
	_quality = _meter(col, "Projected clarity", CosmicTheme.STARLIGHT_GOLD)
	_quality_label = CosmicTheme.label("", 15, CosmicTheme.STARLIGHT_GOLD, CosmicTheme.mono_font())
	col.add_child(_quality_label)
	var hint: Label = CosmicTheme.label("Hold a polished gem on the running lap and keep it inside the ring.  [ / ] change cut  ·  F close", 14, CosmicTheme.TEXT_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = PANEL_WIDTH - 40.0
	col.add_child(hint)
	_connect_faceter.call_deferred()


func _connect_faceter() -> void:
	var f: LapidaryWheel3D = LapidaryWheel3D.faceter
	if f == null:
		return
	f.picker_requested.connect(func() -> void: set_open(not _open))
	f.cut_changed.connect(_refresh_cards)
	_refresh_cards()


func _meter(parent: Control, caption: String, color: Color) -> ProgressBar:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	parent.add_child(row)
	var l: Label = CosmicTheme.label(caption, 12, CosmicTheme.TEXT_DIM)
	l.custom_minimum_size.x = 120
	row.add_child(l)
	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override(&"fill", CosmicTheme.flat(color, Color(0, 0, 0, 0), 0, 5, 0))
	row.add_child(bar)
	return bar


func _make_card(cut: int) -> Button:
	var b: Button = Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(84, 92)
	b.tooltip_text = "%s: %s" % [RockMeshes.CUT_NAMES[cut], RockMeshes.CUT_INFO[cut]]
	b.add_theme_stylebox_override(&"normal", CosmicTheme.flat(Color(CosmicTheme.DEEP, 0.75), Color(CosmicTheme.VIOLET, 0.3), 1, 8, 4))
	b.add_theme_stylebox_override(&"pressed", CosmicTheme.rune_tab(true, CosmicTheme.PRISM_CYAN))
	b.add_theme_stylebox_override(&"hover_pressed", CosmicTheme.rune_tab(true, CosmicTheme.PRISM_CYAN))
	var v: VBoxContainer = VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override(&"separation", 0)
	b.add_child(v)
	var sil: CutSilhouette = CutSilhouette.new()
	sil.cut = cut
	sil.custom_minimum_size = Vector2(0, 48)
	sil.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sil)
	var name: Label = CosmicTheme.label(RockMeshes.CUT_NAMES[cut], 11, CosmicTheme.TEXT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name)
	var fit: Label = CosmicTheme.label("", 10, CosmicTheme.STARLIGHT_GOLD)
	fit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fit)
	b.set_meta(&"fit", fit)
	b.set_meta(&"sil", sil)
	b.pressed.connect(func() -> void:
		if LapidaryWheel3D.faceter != null:
			LapidaryWheel3D.faceter.select_cut(cut)
			AudioHaptics.tick())
	_cards.append(b)
	return b


func set_open(open: bool) -> void:
	_open = open
	_root.visible = open
	if open:
		_refresh_cards()
		_root.reset_size()
		CosmicTheme.reveal(_root, 0.2, 0.97)


## The stone the picker should rate: the one on the lap, else the one in hand.
func _stone() -> Rock3D:
	var f: LapidaryWheel3D = LapidaryWheel3D.faceter
	if f != null and f.work_target() != null:
		return f.work_target()
	if HudOverlay.instance != null and HudOverlay.instance.grabber != null:
		return HudOverlay.instance.grabber.held_body as Rock3D
	return null


func _refresh_cards() -> void:
	var f: LapidaryWheel3D = LapidaryWheel3D.faceter
	if f == null:
		return
	var stone: Rock3D = _stone()
	for i: int in _cards.size():
		var cut: int = i + 1
		var b: Button = _cards[i]
		b.set_pressed_no_signal(cut == f.selected_cut)
		var fit: Label = b.get_meta(&"fit") as Label
		var mastered: bool = LapidaryWheel3D.is_mastered(cut)
		var text: String = "✦ mastered" if mastered else ""
		var tint: Color = CosmicTheme.PRISM_CYAN
		if stone != null and stone.mineral != null:
			var suit: float = LapidaryWheel3D.cut_suitability(stone.mineral, cut)
			var stars: int = 3 if suit > 1.0 else (2 if suit >= 0.9 else (1 if suit >= 0.7 else 0))
			text = "★".repeat(stars) + "☆".repeat(3 - stars) + (" ✦" if mastered else "")
			tint = stone.mineral.color.lerp(CosmicTheme.PRISM_CYAN, 0.3)
		fit.text = text
		var sil: CutSilhouette = b.get_meta(&"sil") as CutSilhouette
		sil.tint = tint
		sil.queue_redraw()
	_info.text = "%s: %s" % [RockMeshes.CUT_NAMES[f.selected_cut], RockMeshes.CUT_INFO[f.selected_cut]]
	var can_quick: bool = LapidaryWheel3D.is_mastered(f.selected_cut)
	_quick.disabled = not can_quick
	_quick.set_pressed_no_signal(f.quick_facet)
	_quick.tooltip_text = "Available once you've cut this shape 3 times at 70%+ quality" if not can_quick else "Cut it 4× faster with your best recorded form"


func _process(_delta: float) -> void:
	var f: LapidaryWheel3D = LapidaryWheel3D.faceter
	var at_lab: bool = LabCamera3D.instance != null and LabCamera3D.instance.station == 1
	if f == null:
		return
	var stone: Rock3D = _stone()
	# Pop open the first time a stone meets the running lap.
	if at_lab and f.running and f.work_target() != null and not _open and not _auto_opened:
		_auto_opened = true
		set_open(true)
	if not at_lab and _open:
		set_open(false)
	if not _open:
		return
	if stone != _last_stone:
		_last_stone = stone
		_refresh_cards()
	if stone != null and stone.mineral != null:
		_stone_label.text = "%s   ·   polish %d%%   ·   %s" % [stone.describe_name(), int(stone.polish * 100.0),
			"ready to facet" if stone.mineral.can_facet and stone.polish >= 0.3 else ("polish it to 30% first" if stone.mineral.can_facet else "can't be faceted")]
	else:
		_stone_label.text = "Pick up a polished gem to see which cuts suit it (★★★ = perfect fit)."
	_progress.value = f.cut_progress()
	_steady.value = f.live_steadiness if f.work_target() != null else 0.0
	var q: float = f.projected_quality()
	_quality.value = q
	_quality_label.text = ("Clarity %d%%  %s" % [int(q * 100.0), "✧✧✧ flawless!" if q >= 0.9 else ("✧✧ brilliant" if q >= 0.7 else ("✧ good" if q >= 0.45 else "keep steady…"))]) if f.work_target() != null else ""


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if LabCamera3D.instance == null or LabCamera3D.instance.station != 1 or LapidaryWheel3D.faceter == null:
		return
	match key.keycode:
		KEY_F:
			set_open(not _open)
			get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT:
			LapidaryWheel3D.faceter.cycle_cut(-1)
			get_viewport().set_input_as_handled()
		KEY_BRACKETRIGHT:
			LapidaryWheel3D.faceter.cycle_cut(1)
			get_viewport().set_input_as_handled()
