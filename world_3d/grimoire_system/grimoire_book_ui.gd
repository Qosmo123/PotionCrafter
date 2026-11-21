class_name GrimoireBookUI
extends CanvasLayer
## The Grimoire: a leather-bound two-page spread (G, the book on the bench, or
## the HUD button). Ribbon tabs: Recipes · Formulas · Cellar · Commissions.
## Left page = organised index; right page = the selected entry, with formula,
## ingredients, method, property radar, thermal curve and the shareable hex-sigil.
## Arrow keys page through entries; Esc closes.

const PARCHMENT: Color = Color(0.93, 0.87, 0.72)
const INK: Color = Color(0.25, 0.14, 0.06)
const FADED_INK: Color = Color(0.45, 0.33, 0.2)
const ACCENT: Color = Color(0.55, 0.12, 0.08)
const TABS: PackedStringArray = ["Recipes", "Formulas", "Collection", "Cellar", "Commissions"]
const CATEGORY_TITLES: PackedStringArray = ["Natural Philosophy", "Arcana", "Secret Recipes", "Fun & Silly"]

static var instance: GrimoireBookUI = null

var _root: Control
var _book: PanelContainer
var _tab_buttons: Array[Button] = []
var _index_list: VBoxContainer
var _index_scroll: ScrollContainer
var _detail: VBoxContainer
var _detail_scroll: ScrollContainer
var _header: Label
var _tab: int = 0
var _entries: Array[Dictionary] = []
var _selected: int = 0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	_root.add_child(dim)

	_book = PanelContainer.new()
	_book.set_anchors_preset(Control.PRESET_CENTER)
	_book.add_theme_stylebox_override(&"panel", _box(Color(0.24, 0.12, 0.07), Color(0.78, 0.6, 0.28), 3, 14, 14))
	_root.add_child(_book)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 8)
	_book.add_child(outer)

	var top: HBoxContainer = HBoxContainer.new()
	outer.add_child(top)
	for i: int in TABS.size():
		var b: Button = Button.new()
		b.text = TABS[i]
		b.custom_minimum_size = Vector2(130, 40)
		b.toggle_mode = true
		b.add_theme_font_size_override(&"font_size", 17)
		var idx: int = i
		b.pressed.connect(func() -> void: _show_tab(idx))
		top.add_child(b)
		_tab_buttons.append(b)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_header = Label.new()
	_header.add_theme_color_override(&"font_color", Color(0.95, 0.82, 0.5))
	_header.add_theme_font_size_override(&"font_size", 16)
	top.add_child(_header)
	var close_button: Button = Button.new()
	close_button.text = "  ✕  "
	close_button.custom_minimum_size = Vector2(48, 40)
	close_button.pressed.connect(close)
	top.add_child(close_button)

	var spread: HBoxContainer = HBoxContainer.new()
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spread.add_theme_constant_override(&"separation", 0)
	outer.add_child(spread)
	var left: PanelContainer = _page(true)
	left.size_flags_stretch_ratio = 0.8
	spread.add_child(left)
	_index_scroll = ScrollContainer.new()
	_index_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(_index_scroll)
	_index_list = VBoxContainer.new()
	_index_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_index_scroll.add_child(_index_list)
	var spine: ColorRect = ColorRect.new()
	spine.color = Color(0.45, 0.32, 0.18)
	spine.custom_minimum_size = Vector2(6, 0)
	spread.add_child(spine)
	var right: PanelContainer = _page(false)
	right.size_flags_stretch_ratio = 1.2
	spread.add_child(right)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override(&"separation", 8)
	_detail_scroll.add_child(_detail)

	get_viewport().size_changed.connect(_layout)
	if GrimoireJournal.instance != null:
		GrimoireJournal.instance.changed.connect(func() -> void:
			if is_open():
				_show_tab(_tab, _selected))


func is_open() -> bool:
	return _root.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open(tab: int = -1) -> void:
	_root.visible = true
	TactileGrabber3D.input_captured = true
	_layout()
	_show_tab(_tab if tab < 0 else tab, _selected)


func close() -> void:
	_root.visible = false
	TactileGrabber3D.input_captured = ChalkDrawing3D.active


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_G:
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open():
		match key.keycode:
			KEY_ESCAPE:
				close()
			KEY_DOWN, KEY_RIGHT:
				_select(mini(_selected + 1, _entries.size() - 1))
			KEY_UP, KEY_LEFT:
				_select(maxi(_selected - 1, 0))
			KEY_TAB:
				_show_tab((_tab + 1) % TABS.size())
		get_viewport().set_input_as_handled()


func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var book_size: Vector2 = Vector2(minf(vp.x * 0.92, 1240.0), minf(vp.y * 0.88, 760.0))
	_book.size = book_size
	_book.position = (vp - book_size) * 0.5


# --- Tabs & index -------------------------------------------------------------------

func _show_tab(tab: int, keep_selection: int = 0) -> void:
	_tab = tab
	for i: int in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == tab
	_entries.clear()
	match tab:
		0: _collect_recipes()
		1: _collect_formulas()
		2: _collect_collection()
		3: _collect_cellar()
		4: _collect_commissions()
	var journal: GrimoireJournal = GrimoireJournal.instance
	var book: RecipeBook = RecipeBook.instance
	var learned: int = 0
	if book != null:
		for r: RecipeData in book.recipes:
			learned += 1 if book.is_discovered(r) else 0
	if tab != 2:
		_header.text = "%d / %d recipes learned   ◉ %d   " % [learned, book.recipes.size() if book != null else 0, journal.coins if journal != null else 0]
	_rebuild_index()
	_select(clampi(keep_selection, 0, maxi(_entries.size() - 1, 0)))


func _collect_recipes() -> void:
	var book: RecipeBook = RecipeBook.instance
	if book == null:
		return
	for cat: int in [3, 0, 1, 2]:
		_entries.append({"header": CATEGORY_TITLES[cat]})
		for r: RecipeData in book.recipes:
			if int(r.category) != cat:
				continue
			var known: bool = book.is_discovered(r)
			var label: String = r.title if known or r.category != RecipeData.Category.SECRET else "Sealed page"
			_entries.append({"kind": "recipe", "recipe": r, "known": known, "label": ("✓  " if known else ("✧  " if r.category == RecipeData.Category.SECRET else "○  ")) + label})


func _collect_formulas() -> void:
	var groups: Dictionary = {}
	for i: int in SubstanceRegistry.count():
		var s: SubstanceData = SubstanceRegistry.get_substance(i)
		var g: String = substance_group(s)
		if not groups.has(g):
			groups[g] = []
		groups[g].append(s)
	for g: String in ["Solvents & Spirits", "Acids, Bases & Salts", "Precipitates & Powders", "Oils & Metals", "Berry Juices", "Arcane Essences", "Gases & Products"]:
		if not groups.has(g):
			continue
		_entries.append({"header": g})
		for s: SubstanceData in groups[g]:
			_entries.append({"kind": "substance", "substance": s, "label": "%s   %s" % [s.display_name, s.chemical_formula]})


func _collect_collection() -> void:
	var journal: GrimoireJournal = GrimoireJournal.instance
	var all: Dictionary = Rock3D.registry()
	var found_count: int = 0
	for id: String in all:
		if journal != null and journal.collection.has(id):
			found_count += 1
	_header.text = "Collection %d / %d   ◉ %d   " % [found_count, all.size(), journal.coins if journal != null else 0]
	for kind: int in [MineralData.Kind.GEM, MineralData.Kind.MINERAL, MineralData.Kind.FOSSIL, MineralData.Kind.ROCK, MineralData.Kind.SAND]:
		var group: Array[MineralData] = []
		for id: String in all:
			var m: MineralData = all[id]
			if int(m.kind) == kind:
				group.append(m)
		group.sort_custom(func(a: MineralData, b: MineralData) -> bool: return a.rarity < b.rarity if a.rarity != b.rarity else a.display_name < b.display_name)
		_entries.append({"header": ["Rocks", "Sands", "Minerals", "Gemstones", "Fossils"][kind]})
		for m: MineralData in group:
			var found: bool = journal != null and journal.collection.has(String(m.mineral_id))
			# Rocks and sands are always in the crate, so they count as known.
			found = found or kind == MineralData.Kind.ROCK or kind == MineralData.Kind.SAND
			var stars: String = "★".repeat(m.rarity + 1)
			_entries.append({"kind": "mineral", "mineral": m, "found": found,
				"label": ("%s  %s" % [stars, m.display_name]) if found else ("%s  ??? (%s)" % [stars, m.rarity_name()])})


func _collect_cellar() -> void:
	var journal: GrimoireJournal = GrimoireJournal.instance
	_entries.append({"header": "Bottled potions (newest first)"})
	if journal == null or journal.cellar.is_empty():
		_entries.append({"kind": "empty", "label": "The cellar is empty. Hold a vessel and press B to cork and label it."})
		return
	for e: Dictionary in journal.cellar:
		_entries.append({"kind": "bottle", "bottle": e, "label": "[%s]  %s" % [e["grade"], String(e["name"]).get_slice(" [", 0)]})


func _collect_commissions() -> void:
	var journal: GrimoireJournal = GrimoireJournal.instance
	_entries.append({"header": "Open commissions"})
	if journal == null or journal.commissions.is_empty():
		_entries.append({"kind": "empty", "label": "No open orders."})
		return
	for o: Dictionary in journal.commissions:
		_entries.append({"kind": "commission", "order": o, "label": "%s  · grade %s+  · %d ◉" % [o["title"], o["min_grade"], o["reward"]]})


static func substance_group(s: SubstanceData) -> String:
	if String(s.substance_id).ends_with("_juice"):
		return "Berry Juices"
	if s.boiling_point_kelvin < 250.0 or String(s.substance_id) in ["spent_essence", "dissolved_salts"]:
		return "Gases & Products"
	if s.melting_point_kelvin > 300.0:
		return "Precipitates & Powders"
	if s.miscibility_group > 0:
		return "Oils & Metals"
	if s.thaumic_density_thaums_mol >= 10.0:
		return "Arcane Essences"
	if s.pka_acidity < 6.5 or (s.pka_acidity > 8.0 and s.pka_acidity < 14.0) or s.precipitant_charge != 0.0 or s.catalyst_strength > 0.0 or s.decomposition_rate_per_s > 0.0 or s.thermochromic_strength > 0.0:
		return "Acids, Bases & Salts"
	return "Solvents & Spirits"


func _rebuild_index() -> void:
	for child: Node in _index_list.get_children():
		child.queue_free()
	for i: int in _entries.size():
		var e: Dictionary = _entries[i]
		if e.has("header"):
			var h: Label = Label.new()
			h.text = e["header"]
			h.add_theme_color_override(&"font_color", ACCENT)
			h.add_theme_font_size_override(&"font_size", 18)
			_index_list.add_child(h)
			continue
		var b: Button = Button.new()
		b.text = e["label"]
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_color_override(&"font_color", INK if not (e.get("kind") == "recipe" and not e.get("known", true)) else FADED_INK)
		b.add_theme_color_override(&"font_hover_color", ACCENT)
		b.add_theme_font_size_override(&"font_size", 15)
		var idx: int = i
		b.pressed.connect(func() -> void: _select(idx))
		e["button"] = b
		_index_list.add_child(b)


func _select(index: int) -> void:
	if _entries.is_empty():
		return
	# Skip headers.
	var i: int = index
	while i < _entries.size() and _entries[i].has("header"):
		i += 1
	if i >= _entries.size():
		i = index
		while i > 0 and _entries[i].has("header"):
			i -= 1
	_selected = i
	for j: int in _entries.size():
		var b: Button = _entries[j].get("button") as Button
		if b != null:
			b.add_theme_stylebox_override(&"normal", _box(Color(0.55, 0.12, 0.08, 0.12), Color(0, 0, 0, 0), 0, 4, 4) if j == i else StyleBoxEmpty.new())
	_render_detail(_entries[i])


# --- Detail page ---------------------------------------------------------------------

func _render_detail(e: Dictionary) -> void:
	for child: Node in _detail.get_children():
		child.queue_free()
	match e.get("kind", ""):
		"recipe": _detail_recipe(e["recipe"], e["known"])
		"substance": _detail_substance(e["substance"])
		"bottle": _detail_bottle(e["bottle"])
		"mineral": _detail_mineral(e["mineral"], e["found"])
		"commission": _detail_commission(e["order"])
		_: _text(e.get("label", ""), 16, FADED_INK)
	# Page-turn: fade and slide the right page in.
	_detail.modulate.a = 0.0
	_detail.position.x = 24.0
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_detail, "modulate:a", 1.0, 0.22)
	tween.tween_property(_detail, "position:x", 0.0, 0.22)
	_detail_scroll.scroll_vertical = 0


func _detail_recipe(r: RecipeData, known: bool) -> void:
	if r.category == RecipeData.Category.SECRET and not known:
		_text("✧  A Sealed Page", 28, ACCENT)
		_text("The ink on this page only appears once the potion has been brewed.", 15, FADED_INK)
		_rule()
		_text("“%s”" % r.riddle, 22, INK, true)
		return
	var info: Dictionary = GrimoireJournal.instance.discovery_of(r.recipe_id) if GrimoireJournal.instance != null else {}
	_text(r.title, 28, INK)
	var sub: String = CATEGORY_TITLES[int(r.category)]
	if known and info.has("time"):
		sub += "   ·   learned %s   ·   first grade %s" % [Time.get_datetime_string_from_unix_time(int(info["time"]), true).substr(0, 16), info.get("grade", "?")]
	elif not known:
		sub += "   ·   not yet brewed"
	_text(sub, 13, FADED_INK)
	_rule()
	_text(r.formula, 19, ACCENT)
	_text(r.description, 16, INK)
	_text("Ingredients", 17, ACCENT)
	for ing: String in r.ingredients:
		_text("   •  " + ing, 15, INK)
	_text("Method", 17, ACCENT)
	for k: int in r.method_steps.size():
		_text("   %d.  %s" % [k + 1, r.method_steps[k]], 15, INK)
	_text("Signature", 17, ACCENT)
	_text("   " + _signature_text(r), 13, FADED_INK)
	_rule()
	var charts: HBoxContainer = HBoxContainer.new()
	charts.add_theme_constant_override(&"separation", 12)
	_detail.add_child(charts)
	var radar: RadarChart = RadarChart.new()
	radar.custom_minimum_size = Vector2(280, 250)
	charts.add_child(radar)
	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	charts.add_child(right_col)
	var curve: CurveChart = CurveChart.new()
	curve.custom_minimum_size = Vector2(240, 110)
	right_col.add_child(curve)
	var sigil: HexSigilView = HexSigilView.new()
	sigil.custom_minimum_size = Vector2(240, 140)
	right_col.add_child(sigil)
	if known and info.has("traits"):
		var values: PackedFloat32Array = info["traits"]
		radar.set_values(values)
		curve.set_samples(info.get("curve", PackedFloat32Array()))
		sigil.set_seed(GrimoireJournal.sigil_seed(values))
	else:
		radar.set_values(PackedFloat32Array())


func _signature_text(r: RecipeData) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in mini(r.condition_traits.size(), r.condition_min.size()):
		var lo: float = r.condition_min[i]
		var hi: float = r.condition_max[i]
		var name: String = r.condition_traits[i].replace("fraction:", "share of ").replace("_", " ")
		if hi >= 1e8:
			parts.append("%s ≥ %s" % [name, String.num(lo, 3)])
		elif lo <= -1e8 or (lo <= 0.0 and r.condition_traits[i] != "ph"):
			parts.append("%s ≤ %s" % [name, String.num(hi, 3)])
		else:
			parts.append("%s %s–%s" % [name, String.num(lo, 3), String.num(hi, 3)])
	return ";  ".join(parts)


func _detail_substance(s: SubstanceData) -> void:
	_text(s.display_name, 28, INK)
	_text(s.chemical_formula, 22, ACCENT)
	_text(substance_group(s), 13, FADED_INK)
	_rule()
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 18)
	_detail.add_child(grid)
	var rows: Array = [
		["Molar mass", "%.1f g/mol" % (s.molar_mass_kg_mol * 1000.0)], ["Density", "%.0f kg/m³" % s.density_kg_m3],
		["Melts", "%.0f °C" % (s.melting_point_kelvin - 273.15)], ["Boils", "%.0f °C" % (s.boiling_point_kelvin - 273.15)],
		["Viscosity", "%s Pa·s" % String.num(s.viscosity_pas, 4)], ["pKa", "%.1f" % s.pka_acidity],
		["Heat capacity", "%.0f J/kg·K" % s.specific_heat_j_kg_k], ["Flammability", "%.0f %%" % (s.flammability * 100.0)],
	]
	if s.thaumic_density_thaums_mol > 0.0:
		rows.append_array([["Thaums", "%.0f /mol" % s.thaumic_density_thaums_mol], ["Polarity", "%+.2f" % s.polarity_charge],
			["Gravity coupling", "%.2f" % s.gravity_coupling], ["Vitality", "%.2f" % s.vitality_resonance]])
	for row: Array in rows:
		var k: Label = Label.new()
		k.text = row[0]
		k.add_theme_color_override(&"font_color", FADED_INK)
		k.add_theme_font_size_override(&"font_size", 14)
		grid.add_child(k)
		var v: Label = Label.new()
		v.text = row[1]
		v.add_theme_color_override(&"font_color", INK)
		v.add_theme_font_size_override(&"font_size", 14)
		grid.add_child(v)
	_text("How it behaves", 17, ACCENT)
	for line: String in behaviour_notes(s):
		_text("   •  " + line, 15, INK)
	if not s.reaction_products.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for p: Resource in s.reaction_products:
			names.append((p as SubstanceData).chemical_formula)
		_text("When consumed it becomes:  " + "  +  ".join(names), 15, ACCENT)
	var swatch: ColorRect = ColorRect.new()
	swatch.color = Color(s.base_albedo_rgba, 1.0)
	swatch.custom_minimum_size = Vector2(0, 14)
	_detail.add_child(swatch)
	if s.cas_number != "" or s.description != "":
		_text(("CAS %s   ·   " % s.cas_number if s.cas_number != "" else "") + s.description, 14, FADED_INK, true)
	_sds_button(func() -> void: SafetySheetUI.instance.open_for_substance(s))


## Plain-language notes derived from the property vector (no per-substance text).
static func behaviour_notes(s: SubstanceData) -> PackedStringArray:
	var notes: PackedStringArray = PackedStringArray()
	if s.pka_acidity < 6.5:
		notes.append("Acid: neutralises any base, fizzing with carbonates.")
	elif s.pka_acidity > 8.0 and s.pka_acidity < 14.0:
		notes.append("Base: neutralises acids%s." % (" and releases gas" if s.proton_transfer_enthalpy_j_mol > 0.0 else ""))
	if s.precipitant_charge > 0.0:
		notes.append("Dissolved metal: drops an insoluble precipitate with any precipitating anion.")
	elif s.precipitant_charge < 0.0:
		notes.append("Precipitating anion: clouds any dissolved metal salt.")
	if s.decomposition_rate_per_s > 0.0:
		notes.append("Unstable: slowly breaks down on its own; a catalyst makes it violent.")
	if s.catalyst_strength > 0.0:
		notes.append("Catalyst: speeds up decomposition without being used up.")
	if s.combustion_enthalpy_j_kg < 0.0:
		notes.append("Flammable: lights from a flame above about %.0f °C." % (s.boiling_point_kelvin - 70.0 * s.flammability - 273.15))
	if s.crosslink_sites > 0.0:
		notes.append("Polymer: gels into slime with a crosslinker.")
	if s.crosslinker_strength > 0.0:
		notes.append("Crosslinker: ties polymer chains into a gel.")
	if s.foaming > 0.0:
		notes.append("Surfactant: foams when agitated; emulsifies oil and water.")
	if s.foam_stability > 0.0:
		notes.append("Stabiliser: keeps foam and bubbles alive.")
	if s.indicator_strength > 0.0:
		notes.append("Indicator: red in acid, green in alkali.")
	if s.thermochromic_strength > 0.0:
		notes.append("Thermochromic: blue when cold, crimson when hot.")
	if s.miscibility_group == 1:
		notes.append("Oily: floats on water in its own layer.")
	elif s.miscibility_group == 2:
		notes.append("Liquid metal: sinks below everything else.")
	if s.polarity_charge != 0.0:
		notes.append("Arcane polarity %+.2f: flares with any opposite polarity." % s.polarity_charge)
	if s.gravity_coupling < 1.0:
		notes.append("Lightens whatever holds it (gravity coupling %.1f)." % s.gravity_coupling)
	if s.transmutation_valence > 0.0:
		notes.append("Transmutable in hot, thaum-rich baths.")
	if notes.is_empty():
		notes.append("Stable and inert: a good solvent or base liquid.")
	return notes


func _detail_mineral(m: MineralData, found: bool) -> void:
	if not found:
		_text("???", 30, FADED_INK)
		_text("%s %s, not yet found" % [m.rarity_name(), ["rock", "sand", "mineral", "gemstone", "fossil"][int(m.kind)]], 15, FADED_INK)
		_rule()
		_text("Where to look:  " + _where_found(m), 16, INK)
		return
	_text(m.display_name, 28, INK)
	_text(m.formula, 20, ACCENT)
	var rarity_label: Label = Label.new()
	rarity_label.text = "%s  %s" % ["★".repeat(m.rarity + 1), m.rarity_name()]
	rarity_label.add_theme_color_override(&"font_color", m.rarity_color().darkened(0.35))
	rarity_label.add_theme_font_size_override(&"font_size", 18)
	_detail.add_child(rarity_label)
	_rule()
	_text("Mohs hardness  %.1f / 10" % m.hardness_mohs, 15, INK)
	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = 10.0
	bar.value = m.hardness_mohs
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	_detail.add_child(bar)
	_text("Specific gravity %.2f   ·   %s luster   ·   worth about %d ◉" % [m.density_kg_m3 / 1000.0, LUSTER_NAMES[clampi(int(m.luster), 0, LUSTER_NAMES.size() - 1)], m.value_coins], 15, INK)
	var swatches: HBoxContainer = HBoxContainer.new()
	swatches.add_theme_constant_override(&"separation", 8)
	_detail.add_child(swatches)
	for pair: Array in [["colour", m.color], ["streak", m.streak_color], ["alt.", m.color_alt]]:
		var c: Color = pair[1]
		if c.a <= 0.0 or (pair[0] == "streak" and m.streak_name == ""):
			continue
		var chip: ColorRect = ColorRect.new()
		chip.color = Color(c, 1.0)
		chip.custom_minimum_size = Vector2(70, 18)
		chip.tooltip_text = pair[0]
		swatches.add_child(chip)
	if m.crystal_system != "":
		_text("Field guide", 18, ACCENT)
		var grid: GridContainer = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override(&"h_separation", 18)
		_detail.add_child(grid)
		var rows: Array = [["Class", m.mineral_class], ["Crystal system", m.crystal_system],
			["Streak", m.streak_name], ["Cleavage", MineralData.CLEAVAGE_NAMES[int(m.cleavage)]], ["Fracture", m.fracture],
			["Transparency", ["transparent", "translucent", "opaque"][int(m.diaphaneity)]]]
		if m.refractive_index > 0.0:
			rows.append(["Refractive index", "%.2f%s" % [m.refractive_index, ("   ·   dispersion %.3f%s" % [m.dispersion, " (fiery!)" if m.dispersion >= 0.035 else ""]) if m.dispersion > 0.0 else ""]])
		if m.phenomenon != MineralData.Phenomenon.NONE:
			rows.append(["Optical effect", MineralData.PHENOMENON_NAMES[int(m.phenomenon)]])
		rows.append_array([["Colours", m.colors_text], ["Found at", m.localities], ["Used for", m.uses]])
		if m.birthstone != "":
			rows.append(["Birthstone", m.birthstone])
		for row: Array in rows:
			if String(row[1]) == "":
				continue
			var k: Label = Label.new()
			k.text = row[0]
			k.add_theme_color_override(&"font_color", FADED_INK)
			k.add_theme_font_size_override(&"font_size", 14)
			grid.add_child(k)
			var v: Label = Label.new()
			v.text = row[1]
			v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.custom_minimum_size = Vector2(380, 0)
			v.add_theme_color_override(&"font_color", INK)
			v.add_theme_font_size_override(&"font_size", 14)
			grid.add_child(v)
	_text("Did you know?", 18, ACCENT)
	_text(m.fun_fact, 17, INK, true)
	if not m.crush_products.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for p: Resource in m.crush_products:
			names.append((p as SubstanceData).display_name)
		_text("Crushes into:  " + ", ".join(names), 15, INK)
	if not m.inclusions.is_empty():
		var inside: PackedStringArray = PackedStringArray()
		for k: int in mini(m.inclusions.size(), m.inclusion_chances.size()):
			inside.append("%s (%d%%)" % [(m.inclusions[k] as MineralData).display_name, int(m.inclusion_chances[k] * 100.0)])
		_text("May hide:  " + ", ".join(inside), 15, INK)
	var where: String = _where_found(m)
	if where != "":
		_text("Found in:  " + where, 15, INK)
	var journal: GrimoireJournal = GrimoireJournal.instance
	var entry: Dictionary = journal.collection.get(String(m.mineral_id), {}) if journal != null else {}
	if not entry.is_empty():
		_text("Found %d×   ·   best specimen: %s (%d ◉)" % [int(entry["count"]), entry["best_name"], int(entry["best_value"])], 15, ACCENT)
	if m.can_facet:
		_text("Tip: polish it, then facet it for a sparkling, valuable gem.", 14, FADED_INK)


const LUSTER_NAMES: PackedStringArray = ["earthy", "vitreous", "metallic", "waxy", "pearly", "glowing", "adamantine", "silky", "resinous"]


static func _where_found(m: MineralData) -> String:
	var sources: PackedStringArray = PackedStringArray()
	if m.kind in [MineralData.Kind.MINERAL, MineralData.Kind.GEM, MineralData.Kind.FOSSIL]:
		sources.append("the Specimen Crate (%s)" % m.rarity_name().to_lower())
	var all: Dictionary = Rock3D.registry()
	for id: String in all:
		var host: MineralData = all[id]
		for inc: Resource in host.inclusions:
			if inc == m:
				sources.append(host.display_name.replace(" Bag", ""))
	return ", ".join(sources)


func _sds_button(action: Callable) -> void:
	if SafetySheetUI.instance == null:
		return
	var b: Button = Button.new()
	b.text = "⚠  Open safety data sheet (WHMIS)"
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(action)
	_detail.add_child(b)


func _detail_bottle(e: Dictionary) -> void:
	_text(String(e["name"]), 26, INK)
	if e.has("composition"):
		_sds_button(func() -> void: SafetySheetUI.instance.open_for_mixture(GrimoireJournal.mixture_from(e), String(e["name"]), 0.0, e.get("assay", {})))
	_text("Bottled %s   ·   %.0f mL" % [Time.get_datetime_string_from_unix_time(int(e["time"]), true).substr(0, 16), float(e.get("volume_ml", 0.0))], 13, FADED_INK)
	_rule()
	_text("Grade  " + String(e["grade"]), 24, ACCENT)
	_text(String(e["formula"]), 16, INK)
	var swatch: ColorRect = ColorRect.new()
	swatch.color = Color.from_string(String(e.get("color", "#ffffff")), Color.WHITE)
	swatch.color.a = 1.0
	swatch.custom_minimum_size = Vector2(0, 26)
	_detail.add_child(swatch)
	var rid: String = String(e.get("recipe_id", ""))
	_text("Matches recipe: " + (rid.replace("_", " ").capitalize() if rid != "" else "none (an original concoction)"), 15, INK)


func _detail_commission(o: Dictionary) -> void:
	_text(String(o["title"]), 26, INK)
	_text("Requested by %s" % o.get("client", "a stranger"), 14, FADED_INK)
	_rule()
	_text("“Kindly prepare a %s of grade %s or better. Bottle it, label it, and the coin is yours.”" % [o["title"], o["min_grade"]], 18, INK, true)
	_text("Reward:  %d ◉" % o["reward"], 20, ACCENT)
	var recipe: RecipeData = null
	if RecipeBook.instance != null:
		for r: RecipeData in RecipeBook.instance.recipes:
			if String(r.recipe_id) == o["recipe_id"]:
				recipe = r
	if recipe != null:
		_text(recipe.formula, 16, ACCENT)
		_text("Ingredients:  " + ", ".join(recipe.ingredients), 15, INK)
		_text("Hold the finished vessel and press B to bottle it.", 14, FADED_INK)


# --- Helpers -------------------------------------------------------------------------

func _text(content: String, font_size: int, color: Color, italic: bool = false) -> void:
	var l: Label = Label.new()
	l.text = content
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_font_size_override(&"font_size", font_size)
	if italic:
		l.add_theme_constant_override(&"line_spacing", 4)
	_detail.add_child(l)


func _rule() -> void:
	var r: ColorRect = ColorRect.new()
	r.color = Color(INK, 0.25)
	r.custom_minimum_size = Vector2(0, 1)
	_detail.add_child(r)


func _page(left: bool) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = _box(PARCHMENT, Color(0.7, 0.58, 0.38), 1, 6, 22)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	style.shadow_size = 4
	if left:
		style.corner_radius_top_right = 0
		style.corner_radius_bottom_right = 0
	else:
		style.corner_radius_top_left = 0
		style.corner_radius_bottom_left = 0
	p.add_theme_stylebox_override(&"panel", style)
	return p


static func _box(bg: Color, border: Color, border_w: int, radius: int, margin: int) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s
