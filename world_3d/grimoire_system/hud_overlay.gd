class_name HudOverlay
extends CanvasLayer
## Player-facing HUD: hover inspector tooltip, toast banners, help overlay (H),
## corner buttons (Grimoire, Help) with the coin purse, and bottling (B).

const TOAST_SECONDS: float = 3.2
const KIND_COLORS: Dictionary = {
	&"discovery": Color(0.95, 0.78, 0.35), &"secret": Color(0.78, 0.6, 1.0), &"bottle": Color(0.7, 0.9, 0.7),
	&"coins": Color(1.0, 0.85, 0.3), &"info": Color(0.85, 0.85, 0.85),
}
const HELP_TEXT: String = """[b][color=#e8c070]Hands[/color][/b]
  Drag  ·  pick up and move anything
  Wheel / right-drag while holding  ·  tilt and pour
  Wheel when empty-handed  ·  zoom      ·  Two fingers: twist to tilt, pinch to zoom
  E  ·  put the held item back in the satchel

[b][color=#e8c070]Brewing[/color][/b]
  Pour vessels into each other  ·  stir with rods, spoons, whisks and the wand
  Hot plate heats  ·  M cycles the magnetic stirrer  ·  the candle lights spirits
  Drop berries into vessels to burst them
  B  ·  cork and label the held vessel (bottle it) for the cellar and commissions

[b][color=#e8c070]Magic[/color][/b]
  C  ·  pick up chalk, draw a closed shape on the bench  ·  X wipes sigils
  ○ ward   △ heat   □ chill   ⬠ levitate   ⬡ stir   ⯃ catalyse

[b][color=#e8c070]Mineral Lab  (press 2)[/color][/b]
  Hammer + Space  ·  crack rocks open on the anvil to find minerals, gems and fossils
  Rock crusher  ·  drop a rock in the hopper, drag the crank handle in circles
  Sand sifter  ·  drop a sand bag in, drag the shaker handle side to side
  Polisher / faceting machine  ·  click the brass switch, hold a stone on the wheel
  Faceting: click the grey dial to choose a cut; keep your hand steady!

[b][color=#e8c070]Books & storage[/color][/b]
  Tab / I  ·  Satchel (reagents, berries, glass, tools)
  G  ·  Grimoire (learned recipes, formulas, cellar, commissions)

[b][color=#e8c070]View[/color][/b]
  F5 graphics preset  ·  F11 fullscreen  ·  F3 lab readout  ·  H this help"""

@export var grabber: TactileGrabber3D
@export var camera: Camera3D

var _inspector: PanelContainer
var _inspector_label: RichTextLabel
var _toasts: VBoxContainer
var _help: PanelContainer
var _coins: Label
var _strike: Button
var _station_buttons: Array[Button] = []


func _ready() -> void:
	layer = 6
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.offset_left = -300
	_toasts.offset_right = 300
	_toasts.offset_top = 18
	_toasts.add_theme_constant_override(&"separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)

	_corner_button("Grimoire  [G]", -340, func() -> void:
		if GrimoireBookUI.instance != null:
			GrimoireBookUI.instance.toggle())
	_corner_button("Help  [H]", -470, toggle_help, 120)
	var station_titles: PackedStringArray = ["1  Potion Bench", "2  Mineral Lab", "3  Science Bench"]
	for i: int in station_titles.size():
		var idx: int = i
		var sb: Button = Button.new()
		sb.text = station_titles[i]
		sb.toggle_mode = true
		sb.button_pressed = i == 0
		sb.position = Vector2(16 + 170 * i, 16)
		sb.custom_minimum_size = Vector2(160, 48)
		sb.add_theme_stylebox_override(&"normal", GrimoireBookUI._box(Color(0.1, 0.07, 0.05, 0.85), Color(0.75, 0.6, 0.3, 0.55), 1, 6, 8))
		sb.add_theme_stylebox_override(&"pressed", GrimoireBookUI._box(Color(0.3, 0.2, 0.1, 0.92), Color(0.95, 0.8, 0.4, 0.9), 2, 6, 8))
		sb.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.6))
		sb.pressed.connect(func() -> void:
			if LabCamera3D.instance != null:
				LabCamera3D.instance.go_to_station(idx))
		add_child(sb)
		_station_buttons.append(sb)
	_strike = Button.new()
	_strike.text = "STRIKE  [Space]"
	_strike.anchor_left = 0.5
	_strike.anchor_right = 0.5
	_strike.anchor_top = 1.0
	_strike.anchor_bottom = 1.0
	_strike.offset_left = -110
	_strike.offset_right = 110
	_strike.offset_top = -96
	_strike.offset_bottom = -32
	_strike.add_theme_font_size_override(&"font_size", 22)
	_strike.add_theme_stylebox_override(&"normal", GrimoireBookUI._box(Color(0.45, 0.12, 0.06, 0.9), Color(1.0, 0.75, 0.3), 2, 10, 10))
	_strike.add_theme_color_override(&"font_color", Color(1.0, 0.92, 0.75))
	_strike.visible = false
	_strike.pressed.connect(_slam_held)
	add_child(_strike)
	_coins = Label.new()
	_coins.anchor_left = 1.0
	_coins.anchor_right = 1.0
	_coins.offset_left = -200
	_coins.offset_right = -24
	_coins.offset_top = 70
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.35))
	_coins.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_coins.add_theme_font_size_override(&"font_size", 18)
	add_child(_coins)

	_inspector = PanelContainer.new()
	_inspector.add_theme_stylebox_override(&"panel", GrimoireBookUI._box(Color(0.07, 0.05, 0.035, 0.88), Color(0.75, 0.6, 0.3, 0.6), 1, 6, 10))
	_inspector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspector.visible = false
	add_child(_inspector)
	_inspector_label = RichTextLabel.new()
	_inspector_label.bbcode_enabled = true
	_inspector_label.fit_content = true
	_inspector_label.scroll_active = false
	_inspector_label.custom_minimum_size = Vector2(340, 0)
	_inspector_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspector_label.add_theme_font_size_override(&"normal_font_size", 15)
	_inspector_label.add_theme_color_override(&"default_color", Color(0.95, 0.9, 0.78))
	_inspector.add_child(_inspector_label)

	_help = PanelContainer.new()
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.add_theme_stylebox_override(&"panel", GrimoireBookUI._box(Color(0.07, 0.05, 0.035, 0.94), Color(0.78, 0.6, 0.28), 2, 10, 22))
	_help.visible = false
	var help_label: RichTextLabel = RichTextLabel.new()
	help_label.bbcode_enabled = true
	help_label.fit_content = true
	help_label.custom_minimum_size = Vector2(700, 0)
	help_label.add_theme_font_size_override(&"normal_font_size", 16)
	help_label.add_theme_color_override(&"default_color", Color(0.95, 0.9, 0.78))
	help_label.text = HELP_TEXT
	_help.add_child(help_label)
	add_child(_help)

	var journal: GrimoireJournal = GrimoireJournal.instance
	if journal != null:
		journal.toast.connect(show_toast)
	show_toast.call_deferred("Welcome to the lab. Press H for controls, G for your Grimoire.", &"info")


func _corner_button(text: String, offset_left: float, action: Callable, width: float = 150.0) -> void:
	var b: Button = Button.new()
	b.text = text
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = offset_left
	b.offset_right = offset_left + width
	b.offset_top = 16
	b.offset_bottom = 64
	b.add_theme_stylebox_override(&"normal", GrimoireBookUI._box(Color(0.1, 0.07, 0.05, 0.85), Color(0.75, 0.6, 0.3, 0.55), 1, 6, 8))
	b.add_theme_stylebox_override(&"hover", GrimoireBookUI._box(Color(0.2, 0.14, 0.08, 0.9), Color(0.85, 0.7, 0.35, 0.8), 1, 6, 8))
	b.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.6))
	b.pressed.connect(action)
	add_child(b)


func toggle_help() -> void:
	_help.visible = not _help.visible
	if _help.visible:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		_help.position = (vp - _help.size) * 0.5


func show_toast(text: String, kind: StringName = &"info") -> void:
	var panel: PanelContainer = PanelContainer.new()
	var accent: Color = KIND_COLORS.get(kind, Color.WHITE)
	panel.add_theme_stylebox_override(&"panel", GrimoireBookUI._box(Color(0.08, 0.05, 0.03, 0.9), accent, 2, 8, 12))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = Label.new()
	label.text = ("✦  " if kind == &"discovery" or kind == &"secret" else "") + text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", accent)
	label.add_theme_font_size_override(&"font_size", 18)
	panel.add_child(label)
	_toasts.add_child(panel)
	while _toasts.get_child_count() > 4:
		var oldest: Node = _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()
	panel.modulate.a = 0.0
	var tween: Tween = panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.25)
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_H:
		toggle_help()
	elif key.keycode == KEY_SPACE:
		_slam_held()
	elif key.keycode == KEY_B and grabber != null and grabber.held_body is Vessel3D:
		bottle(grabber.held_body as Vessel3D)
	elif key.keycode == KEY_S and SafetySheetUI.instance != null and not SafetySheetUI.instance.is_open():
		var target: Object = grabber.held_body if grabber != null and grabber.held_body != null else (_pick(get_viewport().get_mouse_position()) if camera != null else null)
		if target is Vessel3D and (target as Vessel3D).mixture != null and (target as Vessel3D).mixture.get_total_mass_kg() > 1e-6:
			SafetySheetUI.instance.open_for_vessel(target as Vessel3D)
		else:
			show_toast("Hold or point at a filled vessel, then press S for its safety data sheet", &"info")


func _slam_held() -> void:
	if grabber != null and grabber.held_body != null and grabber.held_body.has_method(&"slam"):
		grabber.held_body.call(&"slam")


## Cork + label the vessel and record it, or uncork it if already sealed.
func bottle(vessel: Vessel3D) -> void:
	if vessel.sealed:
		vessel.toggle_seal()
		show_toast("Uncorked", &"info")
	elif vessel.toggle_seal():
		if GrimoireJournal.instance != null:
			GrimoireJournal.instance.record_bottle(vessel)
	else:
		show_toast("Nothing to bottle: the vessel is empty", &"info")


func _process(_delta: float) -> void:
	if GrimoireJournal.instance != null:
		_coins.text = "◉ %d" % GrimoireJournal.instance.coins
	_strike.visible = grabber != null and grabber.held_body is Hammer3D
	if LabCamera3D.instance != null:
		for i: int in _station_buttons.size():
			_station_buttons[i].button_pressed = LabCamera3D.instance.station == i
	var book_open: bool = (GrimoireBookUI.instance != null and GrimoireBookUI.instance.is_open()) or (SafetySheetUI.instance != null and SafetySheetUI.instance.is_open())
	if book_open or _help.visible or camera == null:
		_inspector.visible = false
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var target: Object = grabber.held_body if grabber != null and grabber.held_body != null else _pick(mouse)
	var text: String = describe(target)
	_inspector.visible = text != ""
	if _inspector.visible:
		_inspector_label.text = text
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var pos: Vector2 = mouse + Vector2(22.0, 18.0)
		pos.x = minf(pos.x, vp.x - _inspector.size.x - 8.0)
		pos.y = minf(pos.y, vp.y - _inspector.size.y - 8.0)
		_inspector.position = pos


func _pick(screen: Vector2) -> Object:
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var origin: Vector3 = camera.project_ray_origin(screen)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 6.0,
		SimConstants.LAYER_RIGID_VESSEL | SimConstants.LAYER_SOLID_REAGENT | SimConstants.LAYER_TACTILE_TOOL)
	var hit: Dictionary = space.intersect_ray(query)
	return hit.get("collider", null)


static func describe(target: Object) -> String:
	if target is Vessel3D:
		var v: Vessel3D = target as Vessel3D
		var m: MixtureContainer = v.mixture
		if m == null or m.get_liquid_volume_m3() * 1e6 < 0.5:
			return "[b]Empty %s[/b]\n[color=#a89a80]Pour something in, or take reagents from the satchel.[/color]" % _vessel_kind(v)
		var flags: PackedStringArray = PackedStringArray()
		if m.burning:
			flags.append("[color=#ff8a3a]burning[/color]")
		if v.is_boiling:
			flags.append("[color=#9fd0ff]boiling[/color]")
		if v.sealed:
			flags.append("[color=#c9a35a]corked[/color]")
		if m.gas_generation_mol_s > 0.002:
			flags.append("fizzing")
		if m.precipitation_rate_mol_s > 0.0 or v.suspension_level > 0.05:
			flags.append("precipitating")
		if m.transmutation_rate_mol_s > 0.0:
			flags.append("[color=#ffd36e]transmuting[/color]")
		return "[b]%s[/b]\n[color=#9fb7c9]%.1f °C  ·  %.0f mL  ·  pH %.1f  ·  %s[/color]\n[color=#a89a80]%s[/color]%s" % [
			PotionNamer.name_for(m, v.foam_height_meters), m.temperature_kelvin - 273.15, m.get_liquid_volume_m3() * 1e6, m.get_ph(),
			_vessel_kind(v), PotionNamer.formula_for(m), ("\n" + "  ·  ".join(flags)) if not flags.is_empty() else ""]
	if target is Rock3D:
		var rock: Rock3D = target as Rock3D
		var m: MineralData = rock.mineral
		var hint: String = "Hammer it (Space) to crack it open, or crush it into powder"
		match m.kind:
			MineralData.Kind.SAND: hint = "Drop it into the sand sifter and shake"
			MineralData.Kind.GEM, MineralData.Kind.MINERAL, MineralData.Kind.FOSSIL:
				hint = ("Facet it on the faceting machine" if m.can_facet and rock.polish >= 0.3 else "Polish it on the gem polisher") if rock.cut == RockMeshes.Cut.NONE else "A finished gem! Worth %d ◉" % rock.value()
		return "[b]%s[/b]   [color=#%s]%s %s[/color]\n[color=#9fb7c9]%s  ·  Mohs %.1f  ·  %.0f g  ·  %d ◉[/color]\n[color=#cfc3a6][i]%s[/i][/color]\n[color=#a89a80]%s[/color]" % [
			rock.describe_name(), m.rarity_color().to_html(false), "★".repeat(m.rarity + 1), m.rarity_name(), m.formula, m.hardness_mohs,
			rock.mass_kg * 1000.0, rock.value(), m.fun_fact.get_slice(".", 0) + ".", hint]
	if target is Hammer3D:
		return "[b]Geologist's Hammer[/b]\n[color=#a89a80]Hold it over a rock and press Space (or Strike) to smash it open.[/color]"
	if target is MachineHandle3D:
		return "[b]Handle[/b]\n[color=#a89a80]Grab and drag it to work the machine.[/color]"
	if target is StirTool3D:
		var tool: StirTool3D = target as StirTool3D
		var hint: String = "spins liquids the opposite way" if tool.chirality_bias_rad_s > 0.0 and tool.chirality_sign < 0.0 else ("whips up foam" if tool.agitation_gain > 1.5 else "drag it through a liquid to stir")
		return "[b]%s[/b]\n[color=#a89a80]%s[/color]" % [String(tool.name).capitalize(), hint]
	if target is Berry3D:
		var berry: Berry3D = target as Berry3D
		return "[b]%s[/b]  [color=#e8b04a]%s[/color]\n[color=#a89a80]Drop it into a vessel to burst it.[/color]" % [berry.juice.display_name.replace(" Juice", ""), berry.juice.chemical_formula]
	return ""


static func _vessel_kind(v: Vessel3D) -> String:
	return v.profile.vessel_name.replace("_", " ") if v.profile != null else "vessel"
