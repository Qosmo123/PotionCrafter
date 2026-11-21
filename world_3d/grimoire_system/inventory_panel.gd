extends CanvasLayer
## Quick inventory (Tab / I, or the satchel button for touch): category tabs
## for Reagents, Berries, Glassware, Tools, the Recipe grimoire (with secret
## riddles) and a Formulas codex of every substance. Click an item to place it
## on the bench; hold an item and press E to put it back.

const PANEL_WIDTH: float = 600.0
const TAB_NAMES: PackedStringArray = ["Reagents", "Berries", "Glass", "Tools", "Rocks", "Lab Chem", "Fun", "Recipes", "Codex"]
const ITEM_TABS: int = 7

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
	_toggle_button.custom_minimum_size = Vector2(150, 48)  # >= 48 dp touch target
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
	_root.offset_left = -PANEL_WIDTH - 20.0
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
	column.add_child(title_row)
	title_row.add_child(CosmicTheme.title("Ethereal Satchel", CosmicTheme.SIZE_TITLE))
	var subtitle: Label = CosmicTheme.label("   click to place on the bench  ·  hold + E to return", CosmicTheme.SIZE_CAPTION, CosmicTheme.TEXT_FAINT)
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(subtitle)
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
	if InventoryStore.instance != null:
		InventoryStore.instance.changed.connect(refresh)
	if RecipeBook.instance != null:
		RecipeBook.instance.recipe_discovered.connect(func(_r: RecipeData, _v: Vessel3D) -> void: refresh())


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
	var open_x: float = -PANEL_WIDTH - 20.0
	if not _root.visible:
		_root.visible = true
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
			var header: Label = CosmicTheme.title("✧  " + shelf, 17)
			grid.add_child(header)
		var button: Button = Button.new()
		button.tooltip_text = item.get("tooltip", "")
		button.clip_text = true
		button.custom_minimum_size = Vector2(0, 52)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var count_text: String = "∞" if item["count"] < 0 else "×%d" % item["count"]
		button.text = "%s   ·   %s   %s" % [item["label"], item["detail"], count_text]
		button.disabled = item["count"] == 0
		var mineral: MineralData = item.get("mineral") as MineralData
		var aura: int = mineral.rarity if mineral != null else 0
		button.icon = CosmicTheme.orb_icon(item["color"], aura, 30 if aura > 0 else 26)
		button.add_theme_constant_override(&"h_separation", 12)
		button.add_theme_stylebox_override(&"normal", _row_style(Color(CosmicTheme.DEEP, 0.7), Color(CosmicTheme.VIOLET, 0.25)))
		button.add_theme_stylebox_override(&"hover", _row_style(Color(CosmicTheme.NEBULA, 0.7), Color(CosmicTheme.rarity_aura(aura) if aura > 0 else CosmicTheme.STARLIGHT_GOLD, 0.8)))
		button.add_theme_stylebox_override(&"pressed", _row_style(Color(CosmicTheme.VIOLET, 0.7), CosmicTheme.STARLIGHT_GOLD))
		var id: String = item["id"]
		button.pressed.connect(func() -> void: InventoryStore.instance.take(id))
		grid.add_child(button)


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
