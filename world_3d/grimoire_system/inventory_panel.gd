extends CanvasLayer
## The Ethereal Satchel (Tab / I, or the satchel button for touch): a docked
## drawer that stays open beside whichever bench you're at, switching to the
## shelf that bench needs (Potion Bench -> Reagents, Mineral Lab -> Rocks,
## Science Bench -> Lab Chem). Rows support click (place), Shift-click (into
## your hand) and drag-and-drop onto the bench with a live target marker;
## hovering a row shows a rich card. Hold an item and press E to put it back.

const PANEL_WIDTH: float = 620.0
const COMPACT_WIDTH: float = 420.0
const TAB_NAMES: PackedStringArray = ["Reagents", "Berries", "Glass", "Tools", "Rocks", "Lab Chem", "Fun", "Recipes", "Codex"]
const ITEM_TABS: int = 7
## Default shelf for each station (index = LabCamera3D.station).
const STATION_TABS: PackedInt32Array = [0, 4, 5]
const MARKER_VALID: Color = Color("#F4D06F")
const MARKER_INVALID: Color = Color("#FF6B9D")

var _root: PanelContainer
var _tabs: TabContainer
var _grids: Array[VBoxContainer] = []
var _recipes_label: RichTextLabel
var _formulas_label: RichTextLabel
var _status: Label
var _toggle_button: Button
var _search: LineEdit
var _shell: Control
var _slide: Tween
var _compact: bool = false
var _width_button: Button
var _last_station: int = 0
var _ghost: PanelContainer
var _ghost_label: Label
var _ghost_orb: TextureRect
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _drop: Dictionary = {}


func _ready() -> void:
	layer = 5
	_shell = Control.new()
	_shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CosmicTheme.apply(_shell)
	add_child(_shell)
	_toggle_button = Button.new()
	_toggle_button.text = "✦  Satchel  [Tab]"
	_toggle_button.tooltip_text = "Open the Ethereal Satchel (Tab or I)"
	_toggle_button.custom_minimum_size = Vector2(150, CosmicTheme.TOUCH_MIN)
	_toggle_button.anchor_left = 1.0
	_toggle_button.anchor_right = 1.0
	_toggle_button.offset_left = -170
	_toggle_button.offset_right = -20
	_toggle_button.offset_top = 16
	_toggle_button.offset_bottom = 64
	_toggle_button.pressed.connect(toggle)
	_shell.add_child(_toggle_button)

	_root = PanelContainer.new()
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left = -_width() - 20.0
	_root.offset_right = -20.0
	_root.offset_top = 76.0
	_root.offset_bottom = -20.0
	_root.add_theme_stylebox_override(&"panel", CosmicTheme.glass(CosmicTheme.STARLIGHT_GOLD, 22, 2))
	CosmicTheme.frost(_root)
	_root.visible = false
	_shell.add_child(_root)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", CosmicTheme.GRID)
	_root.add_child(column)
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", 6)
	column.add_child(title_row)
	var title: Label = CosmicTheme.title("Ethereal Satchel", CosmicTheme.SIZE_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title_row.add_child(title)
	_width_button = _header_button("⇔", "Compact / wide drawer", func() -> void: set_compact(not _compact))
	title_row.add_child(_width_button)
	title_row.add_child(_header_button("»", "Tuck the satchel away (Tab)", toggle))
	var hint: Label = CosmicTheme.label("Click: place  ·  Shift-click: to hand  ·  Drag: drop anywhere  ·  E: return", CosmicTheme.SIZE_CAPTION, CosmicTheme.TEXT_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	_search = LineEdit.new()
	_search.placeholder_text = "Search (e.g. acid, slime, red flame, CAS 7647)..."
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, 40)
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	column.add_child(_search)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override(&"font_size", 15)
	column.add_child(_tabs)
	for i: int in ITEM_TABS:
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.name = TAB_NAMES[i]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var grid: VBoxContainer = VBoxContainer.new()
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)
		_tabs.add_child(scroll)
		_grids.append(grid)
	_recipes_label = _rich_tab(TAB_NAMES[ITEM_TABS])
	_formulas_label = _rich_tab(TAB_NAMES[ITEM_TABS + 1])
	_status = Label.new()
	_status.add_theme_color_override(&"font_color", CosmicTheme.PRISM_CYAN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_tabs.tab_changed.connect(func(_i: int) -> void:
		refresh()
		var page: Control = _tabs.get_current_tab_control()
		if page != null:
			page.modulate.a = 0.0
			page.create_tween().tween_property(page, "modulate:a", 1.0, 0.2))
	_build_drag_visuals()
	if InventoryStore.instance != null:
		InventoryStore.instance.changed.connect(refresh)
	if RecipeBook.instance != null:
		RecipeBook.instance.recipe_discovered.connect(func(_r: RecipeData, _v: Vessel3D) -> void: refresh())


func _exit_tree() -> void:
	if _marker != null and _marker.get_parent() == null:
		_marker.free()


func _header_button(text: String, tip: String, action: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(CosmicTheme.TOUCH_MIN, 40)
	b.pressed.connect(action)
	return b


func _width() -> float:
	return COMPACT_WIDTH if _compact else PANEL_WIDTH


func is_open() -> bool:
	return _root.visible


## Compact drawer shows just names (details live in the hover card), leaving
## more of the bench visible while you work.
func set_compact(compact: bool) -> void:
	_compact = compact
	if _slide != null and _slide.is_valid():
		_slide.kill()
	if _root.visible:
		_root.modulate.a = 1.0
		_root.offset_right = -20.0
	_slide = _root.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide.tween_property(_root, "offset_left", -_width() - 20.0, 0.2)
	refresh()


func _process(_delta: float) -> void:
	# Contextual shelf: follow the player to each bench.
	if LabCamera3D.instance != null and LabCamera3D.instance.station != _last_station:
		_last_station = LabCamera3D.instance.station
		if _last_station < STATION_TABS.size() and _search.text == "":
			_tabs.current_tab = STATION_TABS[_last_station]


func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if GrimoireBookUI.instance != null and GrimoireBookUI.instance.is_open():
		return
	if _search != null and _search.has_focus() and not (key != null and key.keycode == KEY_TAB):
		return
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_TAB or key.keycode == KEY_I):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()
	var open_x: float = -_width() - 20.0
	if not _root.visible:
		_root.visible = true
		if LabCamera3D.instance != null and _last_station < STATION_TABS.size():
			_last_station = LabCamera3D.instance.station
			_tabs.current_tab = STATION_TABS[_last_station]
		refresh()
		# Drawer glides in from the right edge with an ethereal fade.
		_root.offset_left = open_x + 60.0
		_root.offset_right = -20.0 + 60.0
		_root.modulate.a = 0.0
		_slide = _root.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_slide.tween_property(_root, "offset_left", open_x, 0.22)
		_slide.tween_property(_root, "offset_right", -20.0, 0.22)
		_slide.tween_property(_root, "modulate:a", 1.0, 0.22)
	else:
		_slide = _root.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_slide.tween_property(_root, "offset_left", open_x + 60.0, 0.16)
		_slide.tween_property(_root, "offset_right", 40.0, 0.16)
		_slide.tween_property(_root, "modulate:a", 0.0, 0.16)
		_slide.chain().tween_callback(func() -> void:
			_root.visible = false
			_root.offset_left = open_x
			_root.offset_right = -20.0)


func refresh() -> void:
	if not _root.visible:
		return
	var store: InventoryStore = InventoryStore.instance
	if store != null:
		for c: int in ITEM_TABS:
			_fill_grid(_grids[c], store.get_items(c as InventoryStore.Category))
		_status.text = store.last_message
	_recipes_label.text = _recipes_text()
	_formulas_label.text = _formulas_text()


func _fill_grid(grid: VBoxContainer, entries: Array[Dictionary]) -> void:
	for child: Node in grid.get_children():
		child.queue_free()
	var query: String = _search.text.strip_edges().to_lower() if _search != null else ""
	var last_shelf: String = ""
	for item: Dictionary in entries:
		if query != "" and not ("%s %s %s %s" % [item["label"], item["detail"], item.get("shelf", ""), item.get("tooltip", "")]).to_lower().contains(query):
			continue
		var shelf: String = item.get("shelf", "")
		if shelf != "" and shelf != last_shelf:
			last_shelf = shelf
			grid.add_child(CosmicTheme.title("✧  " + shelf, 17))
		var button: SatchelItemButton = SatchelItemButton.new()
		button.item = item
		button.tooltip_text = String(item["label"])  # non-empty so the rich card shows
		button.clip_text = true
		button.custom_minimum_size = Vector2(0, CosmicTheme.TOUCH_MIN if _compact else 52)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var count_text: String = "∞" if item["count"] < 0 else "×%d" % item["count"]
		if _compact:
			button.text = "%s   %s" % [item["label"], count_text if item["count"] >= 0 else ""]
		else:
			button.text = "%s   ·   %s   %s" % [item["label"], item["detail"], count_text]
		button.disabled = item["count"] == 0
		var mineral: MineralData = item.get("mineral") as MineralData
		var aura: int = mineral.rarity if mineral != null else 0
		button.icon = CosmicTheme.orb_icon(item["color"], aura, 30 if aura > 0 else 26)
		button.add_theme_constant_override(&"h_separation", 12)
		button.add_theme_stylebox_override(&"normal", _row_style(Color(CosmicTheme.DEEP, 0.7), Color(CosmicTheme.VIOLET, 0.25)))
		button.add_theme_stylebox_override(&"hover", _row_style(Color(CosmicTheme.NEBULA, 0.7), Color(CosmicTheme.rarity_aura(aura) if aura > 0 else CosmicTheme.STARLIGHT_GOLD, 0.8)))
		button.add_theme_stylebox_override(&"pressed", _row_style(Color(CosmicTheme.VIOLET, 0.7), CosmicTheme.STARLIGHT_GOLD))
		button.pressed.connect(_on_item_pressed.bind(button))
		button.drag_started.connect(_on_drag_started)
		button.drag_moved.connect(_on_drag_moved)
		button.drag_released.connect(_on_drag_released)
		grid.add_child(button)


# --- Gestures ----------------------------------------------------------------------------

func _on_item_pressed(button: SatchelItemButton) -> void:
	if button.dragging or InventoryStore.instance == null:
		return
	var id: String = button.item["id"]
	var body: RigidBody3D
	if Input.is_key_pressed(KEY_SHIFT):
		body = InventoryStore.instance.take_to_hand(id)
	else:
		body = InventoryStore.instance.take(id)
	if body == null:
		warn(InventoryStore.instance.last_message)


func _build_drag_visuals() -> void:
	_ghost = PanelContainer.new()
	_ghost.add_theme_stylebox_override(&"panel", CosmicTheme.glow(CosmicTheme.STARLIGHT_GOLD, 8, 8, Color(CosmicTheme.DEEP, 0.92), 0))
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.visible = false
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	_ghost.add_child(row)
	_ghost_orb = TextureRect.new()
	_ghost_orb.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(_ghost_orb)
	_ghost_label = CosmicTheme.label("", 15, CosmicTheme.TEXT)
	row.add_child(_ghost_label)
	_shell.add_child(_ghost)
	# 3D landing marker: a glowing ring that turns pink where you can't drop.
	_marker = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.04
	torus.outer_radius = 0.052
	torus.rings = 32
	torus.ring_segments = 8
	_marker.mesh = torus
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.no_depth_test = true
	_marker_mat.albedo_color = MARKER_VALID
	_marker.material_override = _marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false


func _on_drag_started(button: SatchelItemButton) -> void:
	TactileGrabber3D.input_captured = true
	_ghost_label.text = String(button.item["label"])
	var mineral: MineralData = button.item.get("mineral") as MineralData
	_ghost_orb.texture = CosmicTheme.orb_icon(button.item["color"], mineral.rarity if mineral != null else 0, 30)
	_ghost.reset_size()
	_ghost.visible = true
	_ghost.modulate.a = 0.0
	_ghost.create_tween().tween_property(_ghost, "modulate:a", 1.0, 0.12)
	if _marker.get_parent() == null:
		var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
		host.add_child(_marker)


func _on_drag_moved(_button: SatchelItemButton, screen: Vector2) -> void:
	_ghost.position = screen + Vector2(18.0, 14.0)
	var over_panel: bool = _root.get_global_rect().has_point(screen)
	_drop = {} if over_panel or InventoryStore.instance == null else InventoryStore.instance.drop_point(get_viewport().get_camera_3d(), screen)
	_marker.visible = not _drop.is_empty() and _drop["position"] != Vector3.ZERO
	if _marker.visible:
		var ok: bool = _drop["valid"]
		_marker.global_position = (_drop["position"] as Vector3) + Vector3(0.0, 0.004, 0.0)
		var pulse: float = 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.012)
		_marker.scale = Vector3(pulse, 1.0, pulse)
		_marker_mat.albedo_color = Color(MARKER_VALID if ok else MARKER_INVALID, 0.9)
	var accent: Color = CosmicTheme.TEXT_DIM if over_panel else (MARKER_VALID if not _drop.is_empty() and _drop["valid"] else MARKER_INVALID)
	(_ghost.get_theme_stylebox(&"panel") as CosmicStyleBox).border_color = accent
	(_ghost.get_theme_stylebox(&"panel") as CosmicStyleBox).glow_color = Color(accent, 0.35)
	_ghost.queue_redraw()


func _on_drag_released(button: SatchelItemButton, screen: Vector2) -> void:
	_on_drag_moved(button, screen)
	_ghost.visible = false
	_marker.visible = false
	TactileGrabber3D.input_captured = ChalkDrawing3D.active
	if _drop.is_empty():
		return  # Released over the satchel: cancelled.
	if not _drop["valid"]:
		warn(String(_drop["reason"]))
		return
	if InventoryStore.instance.take(String(button.item["id"]), _drop["position"]) == null:
		warn(InventoryStore.instance.last_message)


## Explain why something can't happen: a gentle shake plus a warning toast.
func warn(reason: String) -> void:
	if not _root.visible:
		return
	CosmicTheme.shake(_root)
	if GrimoireJournal.instance != null and reason != "":
		GrimoireJournal.instance.toast.emit(reason, &"warning")


func _recipes_text() -> String:
	var book: RecipeBook = RecipeBook.instance
	if book == null:
		return "No grimoire found."
	var lines: PackedStringArray = PackedStringArray()
	var found: int = 0
	for r: RecipeData in book.recipes:
		if book.is_discovered(r):
			found += 1
	lines.append("[color=#F4D06F]%d / %d recipes discovered[/color]  ·  [i]%s[/i]\n" % [found, book.recipes.size(), book.last_discovery_text])
	for cat: int in [3, 0, 1, 2]:
		lines.append("[b][color=#F4D06F]%s[/color][/b]" % ["Natural Philosophy", "Arcana", "Secret Recipes", "Fun & Silly"][cat])
		for r: RecipeData in book.recipes:
			if int(r.category) != cat:
				continue
			var known: bool = book.is_discovered(r)
			if r.category == RecipeData.Category.SECRET and not known:
				lines.append("  [color=#B18CFF]✧ ???[/color]  [i][color=#FF9DC0]“%s”[/color][/i]" % r.riddle)
				continue
			lines.append("  %s [b]%s[/b]" % ["[color=#7FE0A0]✓[/color]" if known else "[color=#7D77A3]○[/color]", r.title])
			lines.append("     [color=#5CE1E6]%s[/color]" % r.formula)
			lines.append("     [color=#B3ADD6]%s[/color]" % r.description)
			lines.append("     Ingredients: [color=#D9D3F5]%s[/color]" % ", ".join(r.ingredients))
			lines.append("     Method: [color=#D9D3F5]%s[/color]" % " → ".join(r.method_steps))
		lines.append("")
	return "\n".join(lines)


func _formulas_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for i: int in SubstanceRegistry.count():
		var s: SubstanceData = SubstanceRegistry.get_substance(i)
		var arcane: String = ""
		if s.thaumic_density_thaums_mol > 0.0:
			arcane = "  [color=#B18CFF]%.0f thaum/mol · polarity %+.2f · κ %.1f[/color]" % [s.thaumic_density_thaums_mol, s.polarity_charge, s.gravity_coupling]
		lines.append("[b]%s[/b]  [color=#5CE1E6]%s[/color]" % [s.display_name, s.chemical_formula])
		lines.append("   [color=#B3ADD6]M %.1f g/mol · ρ %.0f kg/m³ · η %s Pa·s · bp %.0f °C · pKa %.1f[/color]%s" % [
			s.molar_mass_kg_mol * 1000.0, s.density_kg_m3, String.num(s.viscosity_pas, 4), s.boiling_point_kelvin - 273.15, s.pka_acidity, arcane])
	return "\n".join(lines)


func _rich_tab(tab_name: String) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.name = tab_name
	label.bbcode_enabled = true
	label.scroll_active = true
	label.add_theme_font_size_override(&"normal_font_size", 15)
	label.add_theme_color_override(&"default_color", CosmicTheme.TEXT)
	label.add_theme_font_override(&"bold_font", CosmicTheme.display_font())
	_tabs.add_child(label)
	return label


func _row_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = CosmicTheme.flat(bg, border, 1, 8, 10)
	style.content_margin_left = 12
	if border.a > 0.6:
		style.shadow_color = Color(border, 0.25)
		style.shadow_size = 6
	return style
