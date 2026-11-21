class_name SatchelItemButton
extends Button
## One row of the Ethereal Satchel.
##   Click / Enter        place it on the bench
##   Shift-click / Shift+Enter   put it straight into your hand
##   Drag                 drop it exactly where you let go (with a target marker)
## Hovering shows a rich glass card: rarity, properties, hazards and uses.
## Presentation only: the panel decides what each gesture does.

signal drag_started(button: SatchelItemButton)
signal drag_moved(button: SatchelItemButton, screen: Vector2)
signal drag_released(button: SatchelItemButton, screen: Vector2)

const DRAG_THRESHOLD_PX: float = 12.0
const CARD_WIDTH: float = 380.0

var item: Dictionary = {}
var dragging: bool = false
var _press_pos: Vector2 = Vector2.INF


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press_pos = mb.global_position
		else:
			_press_pos = Vector2.INF
			if dragging:
				drag_released.emit(self, mb.global_position)
				# Cleared after BaseButton's own handling so `pressed` is ignored.
				set_deferred(&"dragging", false)
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm == null:
		return
	if dragging:
		drag_moved.emit(self, mm.global_position)
	elif _press_pos.is_finite() and not disabled and mm.global_position.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
		dragging = true
		drag_started.emit(self)
		drag_moved.emit(self, mm.global_position)


func _make_custom_tooltip(_for_text: String) -> Object:
	if has_meta(&"locked_text"):
		# Undiscovered: don't give the name away in the card.
		var plain: Label = CosmicTheme.label(String(get_meta(&"locked_text")), 15, CosmicTheme.TEXT)
		var box: PanelContainer = PanelContainer.new()
		box.add_child(plain)
		return box
	return build_card(item)


## The rich hover card for a satchel item (also used by tests).
static func build_card(it: Dictionary) -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	col.add_theme_constant_override(&"separation", 6)
	var mineral: MineralData = it.get("mineral") as MineralData
	var sub: SubstanceData = null
	var subs: Array = it.get("substances", [])
	var ratios: Array = it.get("ratios", [])
	# Describe the main ingredient of a mixed reagent (largest share).
	var best_share: float = -1.0
	for k: int in subs.size():
		var share: float = float(ratios[k]) if k < ratios.size() else 1.0
		var idx: int = SubstanceRegistry.index_of_id(StringName(subs[k]))
		if idx >= 0 and share > best_share and not (subs.size() > 1 and String(subs[k]) == "water"):
			sub = SubstanceRegistry.get_substance(idx)
			best_share = share
	if sub == null and it.has("juice"):
		sub = it["juice"] as SubstanceData

	# Header: orb + name + rarity / shelf.
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	col.add_child(head)
	var orb: TextureRect = TextureRect.new()
	orb.texture = CosmicTheme.orb_icon(it.get("color", Color.WHITE), mineral.rarity if mineral != null else 0, 44)
	orb.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	head.add_child(orb)
	var names: VBoxContainer = VBoxContainer.new()
	names.add_theme_constant_override(&"separation", 0)
	head.add_child(names)
	names.add_child(CosmicTheme.title(String(it.get("label", "")), 21, CosmicTheme.TEXT))
	var sub_line: String = String(it.get("shelf", ""))
	var sub_color: Color = CosmicTheme.TEXT_DIM
	if mineral != null:
		sub_line = "%s  %s %s" % ["★".repeat(mineral.rarity + 1), mineral.rarity_name(), ["rock", "sand", "mineral", "gemstone", "fossil"][int(mineral.kind)]]
		sub_color = CosmicTheme.rarity_aura(mineral.rarity)
	if sub_line != "":
		names.add_child(CosmicTheme.label(sub_line, 13, sub_color))

	var detail: Label = CosmicTheme.label(String(it.get("detail", "")), 13, CosmicTheme.PRISM_CYAN, CosmicTheme.mono_font())
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(detail)

	var blurb: String = String(it.get("tooltip", ""))
	if mineral != null:
		blurb = mineral.fun_fact
	elif blurb == "" and sub != null:
		blurb = sub.description
	if blurb != "":
		var b: Label = CosmicTheme.label(blurb, 14, CosmicTheme.TEXT)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(b)

	var props: PackedStringArray = PackedStringArray()
	var tags: Array[Array] = []
	if sub != null:
		props.append("ρ %.0f kg/m³   ·   melts %.0f °C   ·   boils %.0f °C" % [sub.density_kg_m3, sub.melting_point_kelvin - 273.15, sub.boiling_point_kelvin - 273.15])
		props.append("η %s Pa·s   ·   pKa %.1f%s" % [String.num(sub.viscosity_pas, 4), sub.pka_acidity,
			("   ·   %.0f thaum/mol" % sub.thaumic_density_thaums_mol) if sub.thaumic_density_thaums_mol > 0.0 else ""])
		for note: String in GrimoireBookUI.behaviour_notes(sub).slice(0, 2):
			props.append("•  " + note)
		var m: MixtureContainer = MixtureContainer.new()
		m.add_substance(SubstanceRegistry.index_of_id(sub.substance_id), 1.0, float(it.get("temp_k", SimConstants.AMBIENT_TEMP_KELVIN)))
		var sheet: Dictionary = SafetySheet.build(m, sub.display_name)
		var signal_word: String = String(sheet.get("signal", "NONE"))
		if signal_word != "NONE":
			var hazard_names: PackedStringArray = PackedStringArray()
			for pic: Variant in sheet.get("pictograms", []):
				hazard_names.append(SafetySheet.PICTOGRAM_NAMES[int(pic)])
			var warn_col: Color = Color("#FF6B6B") if signal_word == "DANGER" else (CosmicTheme.WARNING if signal_word == "WARNING" else Color("#B18CFF"))
			tags.append(["⚠ %s%s" % [signal_word, (": " + ", ".join(hazard_names)) if not hazard_names.is_empty() else ""], warn_col])
	elif mineral != null:
		props.append("Mohs %.1f   ·   SG %.2f   ·   worth about %d ◉" % [mineral.hardness_mohs, mineral.density_kg_m3 / 1000.0, mineral.value_coins])
		if mineral.phenomenon != MineralData.Phenomenon.NONE:
			tags.append(["✧ " + MineralData.PHENOMENON_NAMES[int(mineral.phenomenon)], CosmicTheme.PRISM_PINK])
		if mineral.can_facet:
			tags.append(["◆ Can be faceted", CosmicTheme.STARLIGHT_GOLD])
		if mineral.uses != "":
			props.append("Used for: " + mineral.uses)
	for line: String in props:
		var l: Label = CosmicTheme.label(line, 13, CosmicTheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	if not tags.is_empty():
		var flow: HFlowContainer = HFlowContainer.new()
		flow.add_theme_constant_override(&"h_separation", 6)
		col.add_child(flow)
		for t: Array in tags:
			var c: Color = t[1]
			var chip: Label = CosmicTheme.label(String(t[0]), 12, c.lightened(0.2))
			var sb: StyleBoxFlat = CosmicTheme.flat(Color(c, 0.14), Color(c, 0.6), 1, 10, 3)
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			chip.add_theme_stylebox_override(&"normal", sb)
			flow.add_child(chip)
	var count: int = int(it.get("count", -1))
	var hint: Label = CosmicTheme.label("%sClick: place on bench   ·   Shift-click: into your hand   ·   Drag: drop where you like" % ("" if count < 0 else "%d in storage   ·   " % count), 11, CosmicTheme.TEXT_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	# Autowrapped labels need a fixed width to measure their height correctly.
	for n: Node in col.get_children():
		if n is Label and (n as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			(n as Label).custom_minimum_size.x = CARD_WIDTH
	return col
