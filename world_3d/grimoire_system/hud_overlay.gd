class_name HudOverlay
extends CanvasLayer
## Player-facing HUD: hover inspector tooltip, toast banners, help overlay (H),
## corner buttons (Grimoire, Help) with the coin purse, and bottling (B).

var _volume_sliders: Dictionary = {}
var _assist_hint: Label
var _inspect_target: Object = null
var _inspect_wait: float = 0.0
var _syncing_volumes: bool = false

const TOAST_SECONDS: float = 3.2
const STATION_RUNES: PackedStringArray = ["☿", "◆", "⊕"]  # alchemical glyphs with no emoji form
const STATION_NAMES: PackedStringArray = ["Potion Bench", "Mineral Lab", "Science Bench"]
const HELP_TEXT: String = """[b][color=#F4D06F]Hands[/color][/b]
  Click  ·  pick something up, move the mouse, click again to put it down (dragging works too)
  Pour  ·  hold a vessel over another one (it glows), click to pour (wheel: faster/slower; click or move away to stop)
  Info  ·  rest the cursor on something for its name; hold Alt for the full card
  Stir  ·  hold a rod, spoon or whisk over a vessel, then wiggle or circle the mouse (or hold S)
  Swirl  ·  holding a glass, circle the mouse (or hold S) to swish it round
  Put down  ·  click again: vials glide into the rack, round flasks onto cork rings, glass onto the stove, burner or tap tray
  Water  ·  hold a glass under the tap (or set it on the tray): it fills itself and stops when nearly full
  Heat  ·  click the stove's knob for off / low / medium / high  ·  click the burner for more flame
  Shift while moving  ·  slow, precise placement    ·    Wheel while holding  ·  tilt by hand
  Wheel when empty-handed  ·  zoom    ·    Right-drag  ·  move the view, also while carrying (station key re-centres)
  Two fingers  ·  twist to tilt, pinch to zoom
  Put away  ·  the "Put in satchel" tab on the right edge, or E (gems go to Finds; a vessel's contents to Materials)
  Lens  ·  pick up the magnifying glass, hold it over a vessel for a quick reading

[b][color=#F4D06F]Brewing[/color][/b]
  Pour vessels into each other  ·  stir with rods, spoons, whisks and the wand
  Hot plate heats  ·  click the magnetic stirrer (or M) for its speed  ·  the candle lights spirits
  Drop berries into vessels to burst them
  Bottle  ·  set a filled vessel in the cork & wax dish (or B while holding it): corked, sealed, labelled
  A golden shimmer means you're getting warm; hover the vessel for a hint
  Distil  ·  fit the still head on a flask (hold it over the flask, click), set an empty glass under its arm, heat the flask: what boils first comes over first  ·  click the head to lift it off
  Grind  ·  drop a small rock in the mortar, hold the pestle over it and circle the mouse (or S); wheel or Space pounds  ·  finer powder reacts faster

[b][color=#F4D06F]Magic[/color][/b]
  Chalk  ·  click the chalk stick (or C), draw a closed shape on the bench  ·  click the sponge (or X) to wipe
  ○ ward   △ heat   □ chill   ⬠ levitate   ⬡ stir   ⯃ catalyse

[b][color=#F4D06F]Mineral Lab  (press 2)[/color][/b]
  Hammer  ·  hold it over a rock and click (or Space); hit the glowing seam to split it in one blow
  Next rock  ·  click the rock crate (or R) to toss the next rock onto the anvil
  Rock crusher  ·  drop a rock in the hopper, give the crank a good turn: the flywheel keeps it going
  Sand sifter  ·  drop a sand bag in, shake the handle: it keeps rocking for a while
  Storage cabinet  ·  drop finds on its tray, set a beaker of powder on its pan
  Discover  ·  crushed powders dissolved or soaked in your liquids become new ingredients ("???" in the satchel shows a hint)
  Polisher / faceting machine  ·  click the brass switch, hold a stone on the wheel
  Faceting: click the grey dial to choose a cut; keep your hand steady!

[b][color=#F4D06F]Books & storage[/color][/b]
  Tab / I  ·  Satchel (reagents, berries, glass, tools)
  G  ·  Grimoire (learned recipes, formulas, cellar, commissions)
  S  ·  empty-handed, point at a vessel: its safety data sheet (with something in hand, S swirls, stirs or grinds)

[b][color=#F4D06F]View[/color][/b]
  F5 graphics preset  ·  F11 fullscreen  ·  F3 lab readout  ·  T a tip  ·  H this help"""

@export var grabber: TactileGrabber3D
@export var camera: Camera3D

var _inspector: PanelContainer
var _inspector_label: RichTextLabel
var _toasts: VBoxContainer
var _help: PanelContainer
var _coins: Label
var _discoveries: Label
var _found_box: VBoxContainer
var _found_key: String = ""
var _strike: Button
var _station_buttons: Array[Button] = []
var _shell: Control
var _pin_card: PanelContainer
var _pin_body: VBoxContainer
var _pin_shown: String = "?"
var _pin_checks: Array[Label] = []
var _pin_target_label: Label
var _pin_vessel: Vessel3D = null
var _pin_timer: float = 0.0
var _pin_base_y: float = 84.0
var _charge_bar: ProgressBar
var _load_rock: Button
var _reveal_panel: PanelContainer

static var instance: HudOverlay = null


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	layer = 6
	AudioDirector.ensure()
	var shell: Control = Control.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CosmicTheme.apply(shell)
	add_child(shell)
	_shell = shell
	# Notifications stack in the bottom-right corner (newest at the bottom),
	# leaving the top of the screen to the bench, prompts and hover labels.
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 1.0
	_toasts.anchor_right = 1.0
	_toasts.anchor_top = 1.0
	_toasts.anchor_bottom = 1.0
	_toasts.offset_left = -TOAST_WIDTH - 24.0
	_toasts.offset_right = -24.0
	_toasts.offset_bottom = -28.0
	_toasts.offset_top = -28.0
	_toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.add_theme_constant_override(&"separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shell.add_child(_toasts)

	_corner_button("Grimoire  [G]", -340, func() -> void:
		if GrimoireBookUI.instance != null:
			GrimoireBookUI.instance.toggle())
	_corner_button("Help  [H]", -470, toggle_help, 120)
	_build_satchel_tab()
	_build_lens_panel()
	# Navigation bar: one glass strip of glowing rune tabs, one per station.
	var nav: PanelContainer = PanelContainer.new()
	nav.position = Vector2(CosmicTheme.GUTTER, CosmicTheme.GUTTER - 4)
	nav.add_theme_stylebox_override(&"panel", CosmicTheme.glass(CosmicTheme.STARLIGHT_GOLD, 6, 1))
	CosmicTheme.frost(nav)
	_shell.add_child(nav)
	var nav_row: HBoxContainer = HBoxContainer.new()
	nav_row.add_theme_constant_override(&"separation", 6)
	nav.add_child(nav_row)
	for i: int in STATION_NAMES.size():
		var idx: int = i
		var sb: Button = Button.new()
		sb.text = "%s  %s   %d" % [STATION_RUNES[i], STATION_NAMES[i], i + 1]
		sb.tooltip_text = "Go to the %s (key %d)" % [STATION_NAMES[i], i + 1]
		sb.toggle_mode = true
		sb.button_pressed = i == 0
		sb.custom_minimum_size = Vector2(176, CosmicTheme.TOUCH_MIN)
		sb.add_theme_stylebox_override(&"normal", CosmicTheme.rune_tab(false))
		sb.add_theme_stylebox_override(&"pressed", CosmicTheme.rune_tab(true))
		sb.add_theme_stylebox_override(&"hover_pressed", CosmicTheme.rune_tab(true))
		sb.pressed.connect(func() -> void:
			if LabCamera3D.instance != null:
				LabCamera3D.instance.go_to_station(idx))
		nav_row.add_child(sb)
		_station_buttons.append(sb)
	# What the hands are doing (pouring, stirring, swirling) and how to do more.
	_assist_hint = Label.new()
	_assist_hint.anchor_left = 0.5
	_assist_hint.anchor_right = 0.5
	_assist_hint.anchor_top = 1.0
	_assist_hint.anchor_bottom = 1.0
	_assist_hint.offset_left = -420
	_assist_hint.offset_right = 420
	_assist_hint.offset_top = -132
	_assist_hint.offset_bottom = -104
	_assist_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_assist_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_assist_hint.add_theme_font_size_override(&"font_size", 18)
	_assist_hint.add_theme_color_override(&"font_color", CosmicTheme.TEXT)
	_assist_hint.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_assist_hint.add_theme_constant_override(&"outline_size", 6)
	_shell.add_child(_assist_hint)
	_strike = Button.new()
	_strike.text = "STRIKE  [Space]"
	_strike.tooltip_text = "Tap to strike. Hold to wind up a bigger swing, release to smash."
	_strike.anchor_left = 0.5
	_strike.anchor_right = 0.5
	_strike.anchor_top = 1.0
	_strike.anchor_bottom = 1.0
	_strike.offset_left = -110
	_strike.offset_right = 110
	_strike.offset_top = -96
	_strike.offset_bottom = -32
	_strike.add_theme_font_size_override(&"font_size", 22)
	_strike.add_theme_font_override(&"font", CosmicTheme.display_font())
	CosmicTheme.style_button(_strike, CosmicTheme.PRISM_PINK, true)
	_strike.add_theme_stylebox_override(&"normal", CosmicTheme.glow(CosmicTheme.PRISM_PINK, 10, 12, Color(CosmicTheme.NEBULA, 0.85), 0))
	_strike.visible = false
	_strike.button_down.connect(_begin_strike)
	_strike.button_up.connect(_end_strike)
	_shell.add_child(_strike)
	# Wind-up meter under the Strike button.
	_charge_bar = ProgressBar.new()
	_charge_bar.show_percentage = false
	_charge_bar.max_value = 1.0
	_charge_bar.anchor_left = 0.5
	_charge_bar.anchor_right = 0.5
	_charge_bar.anchor_top = 1.0
	_charge_bar.anchor_bottom = 1.0
	_charge_bar.offset_left = -110
	_charge_bar.offset_right = 110
	_charge_bar.offset_top = -26
	_charge_bar.offset_bottom = -16
	_charge_bar.add_theme_stylebox_override(&"fill", CosmicTheme.flat(CosmicTheme.PRISM_PINK, Color(0, 0, 0, 0), 0, 5, 0))
	_charge_bar.visible = false
	_shell.add_child(_charge_bar)
	# Chain cracking: lob the next rock onto the anvil (Mineral Lab only).
	_load_rock = Button.new()
	_load_rock.text = "↻  Load Next Rock  [R]"
	_load_rock.tooltip_text = "Toss the next rock from the crate onto the anvil"
	_load_rock.anchor_left = 0.5
	_load_rock.anchor_right = 0.5
	_load_rock.anchor_top = 1.0
	_load_rock.anchor_bottom = 1.0
	_load_rock.offset_left = -360
	_load_rock.offset_right = -126
	_load_rock.offset_top = -92
	_load_rock.offset_bottom = -36
	CosmicTheme.style_button(_load_rock, CosmicTheme.PRISM_CYAN)
	_load_rock.visible = false
	_load_rock.pressed.connect(load_next_rock)
	_shell.add_child(_load_rock)
	_coins = Label.new()
	# Coin purse sits in the top bar, left of the Help button.
	_coins.anchor_left = 1.0
	_coins.anchor_right = 1.0
	_coins.offset_left = -620
	_coins.offset_right = -484
	_coins.offset_top = 16
	_coins.offset_bottom = 64
	_coins.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coins.add_theme_color_override(&"font_color", CosmicTheme.STARLIGHT_GOLD)
	_coins.add_theme_color_override(&"font_shadow_color", Color(CosmicTheme.STARLIGHT_GOLD, 0.45))
	_coins.add_theme_constant_override(&"shadow_outline_size", 8)
	_coins.add_theme_constant_override(&"shadow_offset_y", 0)
	_coins.add_theme_font_override(&"font", CosmicTheme.mono_font())
	_coins.add_theme_font_size_override(&"font_size", 20)
	var purse: StyleBoxFlat = CosmicTheme.flat(Color(CosmicTheme.DEEP, 0.82), Color(CosmicTheme.STARLIGHT_GOLD, 0.45), 1, 16, 6)
	purse.content_margin_left = 14
	purse.content_margin_right = 14
	_coins.add_theme_stylebox_override(&"normal", purse)
	_coins.tooltip_text = "Coins earned from commissions and specimens"
	_coins.mouse_filter = Control.MOUSE_FILTER_PASS
	_shell.add_child(_coins)
	# Discovery tally, left of the purse (only in discovery mode).
	_discoveries = _coins.duplicate() as Label
	_discoveries.offset_left = -930
	_discoveries.offset_right = -632
	_discoveries.add_theme_color_override(&"font_color", CosmicTheme.PRISM_CYAN)
	_discoveries.add_theme_color_override(&"font_shadow_color", Color(CosmicTheme.PRISM_CYAN, 0.4))
	_discoveries.add_theme_font_override(&"font", CosmicTheme.body_font())
	_discoveries.add_theme_font_size_override(&"font_size", 17)
	var tally: StyleBoxFlat = purse.duplicate() as StyleBoxFlat
	tally.border_color = Color(CosmicTheme.PRISM_CYAN, 0.45)
	_discoveries.add_theme_stylebox_override(&"normal", tally)
	_discoveries.clip_text = true
	_discoveries.visible = false
	_discoveries.mouse_filter = Control.MOUSE_FILTER_STOP
	_discoveries.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_discoveries.gui_input.connect(func(event: InputEvent) -> void:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			toggle_leads())
	_shell.add_child(_discoveries)

	_inspector = PanelContainer.new()
	# Slim pill: one line by default (hold Alt for the full card).
	var pill: StyleBoxFlat = StyleBoxFlat.new()
	pill.bg_color = Color(CosmicTheme.DEEP, 0.78)
	pill.set_corner_radius_all(8)
	pill.content_margin_left = 9
	pill.content_margin_right = 9
	pill.content_margin_top = 4
	pill.content_margin_bottom = 4
	pill.border_color = Color(CosmicTheme.PRISM_CYAN, 0.35)
	pill.set_border_width_all(1)
	_inspector.add_theme_stylebox_override(&"panel", pill)
	_inspector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspector.visible = false
	_shell.add_child(_inspector)
	_inspector_label = RichTextLabel.new()
	_inspector_label.bbcode_enabled = true
	_inspector_label.fit_content = true
	_inspector_label.scroll_active = false
	_inspector_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_inspector_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspector_label.add_theme_font_size_override(&"normal_font_size", 15)
	_inspector_label.add_theme_color_override(&"default_color", CosmicTheme.TEXT)
	_inspector_label.add_theme_font_override(&"bold_font", CosmicTheme.display_font())
	_inspector_label.add_theme_font_size_override(&"bold_font_size", 16)
	_inspector.add_child(_inspector_label)

	_help = PanelContainer.new()
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.add_theme_stylebox_override(&"panel", CosmicTheme.glass(CosmicTheme.STARLIGHT_GOLD, 28, 2, Color(CosmicTheme.DEEP, 0.93)))
	CosmicTheme.frost(_help)
	_help.visible = false
	var help_label: RichTextLabel = RichTextLabel.new()
	help_label.bbcode_enabled = true
	help_label.fit_content = true
	help_label.custom_minimum_size = Vector2(700, 0)
	help_label.add_theme_font_size_override(&"normal_font_size", 16)
	help_label.add_theme_color_override(&"default_color", CosmicTheme.TEXT)
	help_label.add_theme_font_override(&"bold_font", CosmicTheme.display_font())
	help_label.add_theme_font_size_override(&"bold_font_size", 19)
	help_label.text = HELP_TEXT
	var help_box: VBoxContainer = VBoxContainer.new()
	help_box.add_theme_constant_override(&"separation", 14)
	help_box.add_child(help_label)
	help_box.add_child(_build_sound_settings())
	_help.add_child(help_box)
	_shell.add_child(_help)

	_pin_card = PanelContainer.new()
	_pin_card.position = Vector2(CosmicTheme.GUTTER, 84)
	_pin_card.custom_minimum_size = Vector2(340, 0)
	_pin_card.size = Vector2(340, 0)
	# Ghostly parchment: warm, translucent vellum with a violet aura.
	var vellum: CosmicStyleBox = CosmicTheme.glass(Color("#F6E7C1"), 16, 2, Color(0.16, 0.11, 0.21, 0.84))
	vellum.glow_color = Color(CosmicTheme.VIOLET, 0.35)
	vellum.glow_size = 14
	_pin_card.add_theme_stylebox_override(&"panel", vellum)
	CosmicTheme.frost(_pin_card)
	_pin_card.visible = false
	_shell.add_child(_pin_card)
	_pin_body = VBoxContainer.new()
	_pin_body.add_theme_constant_override(&"separation", 4)
	_pin_card.add_child(_pin_body)

	var journal: GrimoireJournal = GrimoireJournal.instance
	if journal != null:
		journal.toast.connect(show_toast)
		journal.changed.connect(_refresh_pin)
		_refresh_pin.call_deferred()
	show_toast.call_deferred("Welcome to the lab. Press H for controls, G for your Grimoire, T for a tip.", &"info")
	var tips: LabTips = LabTips.new()
	tips.name = &"LabTips"
	tips.hud = self
	add_child(tips)


func _corner_button(text: String, offset_left: float, action: Callable, width: float = 150.0) -> void:
	var b: Button = Button.new()
	b.text = text
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = offset_left
	b.offset_right = offset_left + width
	b.offset_top = 16
	b.offset_bottom = 64
	b.pressed.connect(action)
	_shell.add_child(b)


## The pinned formula as a ghostly parchment floating beside the bench: the
## recipe, its steps, and a live signature check for the vessel in hand
## (each condition the grimoire listens for, ✓ when met). Once a recipe has
## been discovered, "Brew Pinned Formula" pours its ingredients into that
## vessel; heating, stirring and the chemistry itself are still up to you.
func _refresh_pin() -> void:
	var journal: GrimoireJournal = GrimoireJournal.instance
	var r: RecipeData = journal.pinned() if journal != null else null
	var id: String = String(r.recipe_id) if r != null else ""
	if id == _pin_shown:
		return
	_pin_shown = id
	_pin_checks.clear()
	for c: Node in _pin_body.get_children():
		c.queue_free()
	_pin_card.visible = r != null
	if r == null:
		return
	var ink: Color = Color("#F6E7C1")
	var head: HBoxContainer = HBoxContainer.new()
	_pin_body.add_child(head)
	var t: Label = CosmicTheme.title("✦ " + r.title, 19, CosmicTheme.STARLIGHT_GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(250, 0)
	head.add_child(t)
	var unpin: Button = Button.new()
	unpin.text = "✕"
	unpin.tooltip_text = "Unpin"
	unpin.flat = true
	unpin.custom_minimum_size = Vector2(36, 32)
	unpin.pressed.connect(func() -> void: journal.pin(id))
	head.add_child(unpin)
	var f: Label = CosmicTheme.label(r.formula, 15, CosmicTheme.PRISM_CYAN, CosmicTheme.mono_font())
	f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pin_body.add_child(f)
	var ing: Label = CosmicTheme.label("Ingredients:  " + ", ".join(r.ingredients), 15, ink)
	ing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pin_body.add_child(ing)
	for k: int in r.method_steps.size():
		var step: Label = CosmicTheme.label("%d.  %s" % [k + 1, r.method_steps[k]], 15, Color(ink, 0.8))
		step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_pin_body.add_child(step)
	_pin_body.add_child(CosmicTheme.label("Signature check", 12, CosmicTheme.TEXT_DIM, CosmicTheme.display_font()))
	for i: int in mini(r.condition_traits.size(), mini(r.condition_min.size(), r.condition_max.size())):
		var row: Label = CosmicTheme.label("", 12, CosmicTheme.TEXT_FAINT, CosmicTheme.mono_font())
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_pin_body.add_child(row)
		_pin_checks.append(row)
	_pin_target_label = CosmicTheme.label("", 11, CosmicTheme.TEXT_FAINT)
	_pin_body.add_child(_pin_target_label)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 6)
	_pin_body.add_child(actions)
	var gather: Button = Button.new()
	gather.text = "☿ Gather"
	gather.tooltip_text = "Set every ingredient you have in storage on the bench"
	gather.custom_minimum_size = Vector2(0, 36)
	CosmicTheme.style_button(gather, CosmicTheme.PRISM_CYAN)
	gather.pressed.connect(func() -> void:
		if InventoryStore.instance == null:
			return
		var missing: PackedStringArray = InventoryStore.instance.gather(r)
		if missing.size() == r.ingredients.size():
			CosmicTheme.shake(_pin_card)
		show_toast(InventoryStore.instance.last_message, &"info" if missing.is_empty() else &"warning"))
	actions.add_child(gather)
	var known: bool = RecipeBook.instance != null and RecipeBook.instance.is_discovered(r)
	var brew: Button = Button.new()
	brew.text = "✧ Brew Pinned Formula" if known else "✧ Brew (discover it first)"
	brew.tooltip_text = "Pour the ingredients straight into the vessel in your hand (or the one you point at)" if known else "Brew this by hand once; after that the shortcut unlocks"
	brew.disabled = not known
	brew.custom_minimum_size = Vector2(0, 36)
	CosmicTheme.style_button(brew, CosmicTheme.PRISM_PINK, true)
	brew.pressed.connect(func() -> void: _brew_pinned(r, brew))
	actions.add_child(brew)
	for n: Node in _pin_body.get_children():
		if n is Label:
			(n as Label).custom_minimum_size.x = 320.0
	_pin_card.reset_size.call_deferred()
	CosmicTheme.reveal(_pin_card)


func _brew_pinned(r: RecipeData, button: Control) -> void:
	var v: Vessel3D = _pin_vessel if is_instance_valid(_pin_vessel) else null
	if v == null or InventoryStore.instance == null:
		CosmicTheme.shake(button)
		show_toast("Hold or point at an open vessel first, then brew the pinned formula into it", &"warning")
		return
	var missing: PackedStringArray = InventoryStore.instance.dispense_into(r, v)
	if missing.size() == r.ingredients.size():
		CosmicTheme.shake(button)
		show_toast(InventoryStore.instance.last_message, &"warning")
		return
	show_toast(InventoryStore.instance.last_message + "   ·   now: " + " → ".join(r.method_steps), &"discovery")


## Live signature check against the vessel in hand (or under the pointer).
func _update_pin_checks() -> void:
	var r: RecipeData = GrimoireJournal.instance.pinned() if GrimoireJournal.instance != null else null
	if r == null or _pin_checks.is_empty():
		return
	var traits: Dictionary = {}
	if is_instance_valid(_pin_vessel) and _pin_vessel.mixture != null and _pin_vessel.mixture.get_liquid_volume_m3() > 1e-7:
		traits = RecipeBook.measure(_pin_vessel)
		_pin_target_label.text = "checking: %s" % PotionNamer.name_for(_pin_vessel.mixture, _pin_vessel.foam_height_meters)
	else:
		_pin_target_label.text = "hold or point at a vessel to check it"
	for i: int in _pin_checks.size():
		var trait_name: String = r.condition_traits[i]
		var lo: float = r.condition_min[i]
		var hi: float = r.condition_max[i]
		var nice: String = trait_name.replace("fraction:", "share of ").replace("_", " ")
		var want: String = ("≥ %s" % String.num(lo, 2)) if hi >= 1e8 else (("≤ %s" % String.num(hi, 2)) if lo <= -1e8 or (lo <= 0.0 and trait_name != "ph") else "%s–%s" % [String.num(lo, 2), String.num(hi, 2)])
		if traits.is_empty():
			_pin_checks[i].text = "○ %s %s" % [nice, want]
			_pin_checks[i].add_theme_color_override(&"font_color", CosmicTheme.TEXT_FAINT)
			continue
		var value: float = traits.get(trait_name, 0.0)
		var ok: bool = value >= lo and value <= hi
		_pin_checks[i].text = "%s %s %s   (now %s)" % ["✓" if ok else "○", nice, want, String.num(value, 2)]
		_pin_checks[i].add_theme_color_override(&"font_color", CosmicTheme.SUCCESS if ok else CosmicTheme.TEXT_DIM)


## Volume sliders (overall, effects, ambience, interface), saved as they move.
func _build_sound_settings() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	var title: Label = Label.new()
	title.text = "Sound"
	title.add_theme_font_override(&"font", CosmicTheme.display_font())
	title.add_theme_font_size_override(&"font_size", 19)
	title.add_theme_color_override(&"font_color", CosmicTheme.STARLIGHT_GOLD)
	box.add_child(title)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 14)
	var names: Dictionary = {"Master": "Overall", "SFX": "Effects", "Ambience": "Ambience", "UI": "Interface"}
	for bus: String in AudioDirector.BUSES:
		var label: Label = Label.new()
		label.text = names[bus]
		label.add_theme_color_override(&"font_color", CosmicTheme.TEXT)
		grid.add_child(label)
		var slider: HSlider = HSlider.new()
		slider.name = "Volume" + bus
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(210, 24)
		slider.value = float(AudioDirector.DEFAULT_VOLUMES[bus])
		slider.value_changed.connect(_on_volume_changed.bind(bus))
		grid.add_child(slider)
		_volume_sliders[bus] = slider
	box.add_child(grid)
	return box


func _on_volume_changed(value: float, bus: String) -> void:
	if _syncing_volumes:
		return
	AudioDirector.set_volume(bus, value)
	if bus != "UI":
		AudioDirector.play_ui(&"ui_click", -10.0)


func toggle_help() -> void:
	_help.visible = not _help.visible
	AudioDirector.play_ui(&"ui_open" if _help.visible else &"ui_close", -10.0)
	if _help.visible:
		# Show the volumes as they are now (loaded from the saved settings).
		_syncing_volumes = true
		for bus: String in _volume_sliders:
			(_volume_sliders[bus] as HSlider).value = AudioDirector.get_volume(bus)
		_syncing_volumes = false
		var vp: Vector2 = get_viewport().get_visible_rect().size
		_help.reset_size()
		_help.position = (vp - _help.size) * 0.5
		CosmicTheme.reveal(_help)


const TOAST_WIDTH: float = 380.0


func show_toast(text: String, kind: StringName = &"info") -> void:
	var slot: MarginContainer = MarginContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = PanelContainer.new()
	var accent: Color = CosmicTheme.toast_color(kind)
	panel.add_theme_stylebox_override(&"panel", CosmicTheme.glow(accent, 12, 8 if kind != &"info" else 0, Color(CosmicTheme.DEEP, 0.9), 0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = Label.new()
	label.text = ("✦  " if kind == &"discovery" or kind == &"secret" else "") + text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(TOAST_WIDTH - 40.0, 0.0)
	label.add_theme_color_override(&"font_color", accent.lerp(CosmicTheme.TEXT, 0.25))
	label.add_theme_font_size_override(&"font_size", 16)
	if kind != &"info":
		label.add_theme_font_override(&"font", CosmicTheme.display_font())
	panel.add_child(label)
	slot.add_child(panel)
	_toasts.add_child(slot)
	while _toasts.get_child_count() > 4:
		var oldest: Node = _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()
	# Slide in from the right edge and fade; fade out at the end.
	slot.modulate.a = 0.0
	slot.add_theme_constant_override(&"margin_left", 60)
	var tween: Tween = slot.create_tween()
	tween.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot, "modulate:a", 1.0, 0.25)
	tween.tween_method(func(m: int) -> void: slot.add_theme_constant_override(&"margin_left", m), 60, 0, 0.3 if not CosmicTheme.reduced_motion else 0.01)
	tween.chain().tween_interval(TOAST_SECONDS)
	tween.chain().tween_property(slot, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(slot.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or key.echo:
		return
	if key.keycode == KEY_SPACE:
		if key.pressed:
			_begin_strike()
		else:
			_end_strike()
		return
	if not key.pressed:
		return
	if key.keycode == KEY_H:
		toggle_help()
	elif key.keycode == KEY_T and LabTips.instance != null:
		LabTips.instance.show_next()
	elif key.keycode == KEY_R and LabCamera3D.instance != null and LabCamera3D.instance.station == 1:
		load_next_rock()
	elif key.keycode == KEY_B and grabber != null and grabber.held_body is Vessel3D:
		bottle(grabber.held_body as Vessel3D)
	elif key.keycode == KEY_B:
		show_toast("Pick up a vessel first, then press B to cork and label it", &"warning")
	elif key.keycode == KEY_S and grabber != null and grabber.held_body != null:
		pass  # with something in hand, S swirls, stirs or grinds (the grabber reads it)
	elif key.keycode == KEY_S and SafetySheetUI.instance != null and not SafetySheetUI.instance.is_open():
		var at: Vector2 = grabber.pointer_screen() if grabber != null else get_viewport().get_mouse_position()
		var target: Object = _pick(at) if camera != null else null
		if target is Vessel3D and (target as Vessel3D).mixture != null and (target as Vessel3D).mixture.get_total_mass_kg() > 1e-6:
			SafetySheetUI.instance.open_for_vessel(target as Vessel3D)
		else:
			show_toast("Point at a filled vessel with an empty hand, then press S for its safety data sheet", &"warning")


func _slam_held() -> void:
	if grabber != null and grabber.held_body != null and grabber.held_body.has_method(&"slam"):
		grabber.held_body.call(&"slam")
	elif _strike.visible:
		CosmicTheme.shake(_strike)


func _begin_strike() -> void:
	var hammer: Hammer3D = grabber.held_body as Hammer3D if grabber != null else null
	if hammer != null:
		hammer.begin_charge()
	elif grabber != null and grabber.held_body != null and grabber.held_body.has_method(&"slam"):
		grabber.held_body.call(&"slam")
	elif LabCamera3D.instance != null and LabCamera3D.instance.station == 1:
		show_toast("Pick up the hammer first, then hold Space over a rock on the anvil", &"warning")


func _end_strike() -> void:
	var hammer: Hammer3D = grabber.held_body as Hammer3D if grabber != null else null
	if hammer != null:
		hammer.release_charge()


func load_next_rock() -> void:
	var problem: String = AnvilLoader.load_next(self)
	if problem != "":
		CosmicTheme.shake(_load_rock)
		show_toast(problem, &"warning")


## Dramatic banner for a rare find (paired with the pillar of light in 3D).
func show_reveal(m: MineralData) -> void:
	if _reveal_panel != null and is_instance_valid(_reveal_panel):
		_reveal_panel.queue_free()
	var aura: Color = CosmicTheme.rarity_aura(m.rarity)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", CosmicTheme.glow(aura, 22, 22, Color(CosmicTheme.DEEP, 0.9), 2))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	var kicker: Label = CosmicTheme.label("✦  %s FIND  ✦" % m.rarity_name().to_upper(), 15, aura.lightened(0.2), CosmicTheme.display_font())
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(kicker)
	var head: HBoxContainer = HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override(&"separation", 14)
	col.add_child(head)
	var orb: TextureRect = TextureRect.new()
	orb.texture = CosmicTheme.orb_icon(m.color, m.rarity, 64)
	orb.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	head.add_child(orb)
	head.add_child(CosmicTheme.title(m.display_name, CosmicTheme.SIZE_HERO + 6, CosmicTheme.TEXT))
	var stars: Label = CosmicTheme.label("%s   ·   Mohs %.1f   ·   worth about %d ◉" % ["★".repeat(m.rarity + 1), m.hardness_mohs, m.value_coins], 15, CosmicTheme.STARLIGHT_GOLD)
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(stars)
	_shell.add_child(panel)
	_reveal_panel = panel
	panel.reset_size()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	panel.position = Vector2((vp.x - panel.size.x) * 0.5, vp.y * 0.22)
	if CosmicTheme.reduced_motion:
		panel.modulate.a = 1.0
	else:
		CosmicTheme.reveal(panel, 0.35, 0.8)
	var tw: Tween = panel.create_tween()
	tw.tween_interval(2.8)
	tw.tween_property(panel, "modulate:a", 0.0, 0.6)
	tw.tween_callback(panel.queue_free)


## Cork + label the vessel and record it, or uncork it if already sealed.
func bottle(vessel: Vessel3D) -> void:
	if vessel.sealed:
		vessel.toggle_seal()
		show_toast("Uncorked", &"info")
	elif vessel.toggle_seal():
		if GrimoireJournal.instance != null:
			GrimoireJournal.instance.record_bottle(vessel)
	else:
		show_toast("Nothing to bottle: the vessel is empty", &"warning")
		AudioDirector.play_ui(&"ui_error", -8.0)


# --- Things to try next --------------------------------------------------------------

var _leads_panel: PanelContainer
var _leads_box: VBoxContainer
var _leads_count: int = -1


## Open or close the list of leads under the discovery tally.
func toggle_leads() -> void:
	if _leads_panel == null:
		_leads_panel = PanelContainer.new()
		_leads_panel.anchor_left = 1.0
		_leads_panel.anchor_right = 1.0
		_leads_panel.offset_left = -1050
		_leads_panel.offset_right = -632
		_leads_panel.offset_top = 70
		_leads_panel.grow_vertical = Control.GROW_DIRECTION_END
		_leads_panel.add_theme_stylebox_override(&"panel", CosmicTheme.flat(Color(CosmicTheme.DEEP, 0.94), Color(CosmicTheme.PRISM_CYAN, 0.55), 1, 14, 14))
		_leads_box = VBoxContainer.new()
		_leads_box.add_theme_constant_override(&"separation", 6)
		_leads_panel.add_child(_leads_box)
		_leads_panel.visible = false
		_shell.add_child(_leads_panel)
	_leads_panel.visible = not _leads_panel.visible
	if _leads_panel.visible:
		_fill_leads()
		AudioDirector.play_ui(&"click", -10.0)


## Go to the Mineral Lab and put a rock of `mineral_id` in the hand (from a lead).
func fetch_rock(mineral_id: StringName) -> void:
	if _leads_panel != null:
		_leads_panel.visible = false
	var cam: LabCamera3D = LabCamera3D.instance
	var store: InventoryStore = InventoryStore.instance
	if cam == null or store == null:
		return
	var id: String = "rock:" + String(mineral_id)
	if cam.station == InventoryStore.MINERAL_LAB_STATION:
		_hand_rock(id)
		return
	cam.go_to_station(InventoryStore.MINERAL_LAB_STATION)
	# Wait for the camera to arrive so the rock appears in view, under the cursor.
	get_tree().create_timer(1.0).timeout.connect(_hand_rock.bind(id))


func _hand_rock(id: String) -> void:
	var store: InventoryStore = InventoryStore.instance
	if store == null:
		return
	if store.take_to_hand(id) == null:
		show_toast(store.last_message, &"info")
	else:
		show_toast("Here you go. Drop it in the crusher hopper and turn the crank", &"info")


func _fill_leads() -> void:
	var dp: DiscoveryProgress = DiscoveryProgress.instance
	if dp == null:
		return
	_leads_count = dp.discovered_count()
	for child: Node in _leads_box.get_children():
		child.queue_free()
	_leads_box.add_child(CosmicTheme.label("✦ Things to try next", CosmicTheme.SIZE_SUBHEAD, CosmicTheme.STARLIGHT_GOLD, CosmicTheme.display_font()))
	var buyable: Array = [0]
	var rocks: Array = []
	var leads: PackedStringArray = dp.leads(6, buyable, rocks)
	for i: int in leads.size():
		var rock_id: StringName = rocks[i] if i < rocks.size() else &""
		var row: Button = Button.new()
		row.text = "✧  " + leads[i]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(400, 0)
		row.focus_mode = Control.FOCUS_NONE
		CosmicTheme.style_button(row, CosmicTheme.PRISM_CYAN)
		row.add_theme_font_size_override(&"font_size", 15)
		if rock_id != &"":
			var m: MineralData = Rock3D.get_mineral(String(rock_id))
			row.tooltip_text = "Click: go to the Mineral Lab with %s in your hand" % (m.display_name if m != null else "the rock")
			row.pressed.connect(fetch_rock.bind(rock_id))
		else:
			row.disabled = true
		_leads_box.add_child(row)
	if leads.is_empty():
		_leads_box.add_child(CosmicTheme.label("Every ingredient the rocks can give has been found.", 15, Color(0.9, 0.88, 1.0)))
	var foot: String = "Click a line to go to the Mineral Lab with that rock in your hand."
	if int(buyable[0]) > 0:
		foot += "
%d other ingredients can only be bought: click a ??? row in the satchel (%d ◉ each)." % [int(buyable[0]), DiscoveryProgress.BUY_PRICE_COINS]
	var note: Label = CosmicTheme.label(foot, 13, Color(0.72, 0.7, 0.88))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(380, 0)
	_leads_box.add_child(note)


# --- New ingredient reveal card -------------------------------------------------------

const REVEAL_SECONDS: float = 4.5
var _reveal_queue: Array[StringName] = []
var _reveal_card: PanelContainer
var _reveal_t: float = 0.0
var _reveal_hooked: bool = false
var _reveal_swatch: TextureRect
var _reveal_name: Label
var _reveal_formula: Label
var _reveal_text: Label


func _on_ingredient_revealed(substance_id: StringName) -> void:
	_reveal_queue.append(substance_id)


## A card drops in under the top bar for each newly discovered shelf
## ingredient: colour, name, formula, what it is, and where its bottle went.
func _update_reveal(delta: float) -> void:
	var dp: DiscoveryProgress = DiscoveryProgress.instance
	if dp != null and not _reveal_hooked:
		_reveal_hooked = true
		dp.ingredient_revealed.connect(_on_ingredient_revealed)
	if _reveal_card == null:
		_build_reveal_card()
	if _reveal_t <= 0.0:
		if _reveal_queue.is_empty():
			_reveal_card.visible = false
			return
		var idx: int = SubstanceRegistry.index_of_id(_reveal_queue.pop_front())
		if idx < 0:
			return
		var s: SubstanceData = SubstanceRegistry.get_substance(idx)
		_reveal_swatch.texture = _swatch(s.base_albedo_rgba)
		_reveal_swatch.modulate = Color(1.6, 1.6, 1.6)
		_reveal_name.text = s.display_name
		_reveal_formula.text = s.chemical_formula
		_reveal_text.text = (s.description + "
" if s.description != "" else "") + "Its stock bottle is now in your satchel."
		_reveal_t = REVEAL_SECONDS
		_reveal_card.visible = true
	_reveal_t -= delta
	# Drop in, hold, fade out.
	var age: float = REVEAL_SECONDS - _reveal_t
	var enter: float = clampf(age / 0.35, 0.0, 1.0)
	var leave: float = clampf(_reveal_t / 0.5, 0.0, 1.0)
	_reveal_card.modulate.a = minf(enter, leave)
	_reveal_card.offset_top = 84.0 - 30.0 * (1.0 - ease(enter, 0.3))
	_reveal_card.offset_bottom = _reveal_card.offset_top


func _build_reveal_card() -> void:
	_reveal_card = PanelContainer.new()
	_reveal_card.anchor_left = 0.5
	_reveal_card.anchor_right = 0.5
	_reveal_card.offset_left = -300
	_reveal_card.offset_right = 300
	_reveal_card.offset_top = 84
	_reveal_card.grow_vertical = Control.GROW_DIRECTION_END
	_reveal_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg: StyleBoxFlat = CosmicTheme.flat(Color(CosmicTheme.DEEP, 0.94), CosmicTheme.STARLIGHT_GOLD, 2, 18, 16)
	bg.shadow_color = Color(CosmicTheme.STARLIGHT_GOLD, 0.35)
	bg.shadow_size = 18
	_reveal_card.add_theme_stylebox_override(&"panel", bg)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_card.add_child(row)
	_reveal_swatch = TextureRect.new()
	_reveal_swatch.custom_minimum_size = Vector2(72, 72)
	_reveal_swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_reveal_swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_reveal_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reveal_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_reveal_swatch)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(CosmicTheme.label("✦  NEW INGREDIENT DISCOVERED", 14, CosmicTheme.STARLIGHT_GOLD))
	_reveal_name = CosmicTheme.label("", CosmicTheme.SIZE_TITLE, Color(1.0, 0.97, 0.88), CosmicTheme.display_font())
	col.add_child(_reveal_name)
	_reveal_formula = CosmicTheme.label("", 15, CosmicTheme.PRISM_CYAN, CosmicTheme.mono_font())
	col.add_child(_reveal_formula)
	_reveal_text = CosmicTheme.label("", 15, Color(0.86, 0.84, 0.95))
	_reveal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reveal_text.custom_minimum_size = Vector2(470, 0)
	col.add_child(_reveal_text)
	_reveal_card.visible = false
	_shell.add_child(_reveal_card)


## Found list (bottom left): the newest stored powders and finds, one click
## each. A click puts a scoop (or the stone) straight into the hand.
const FOUND_ROWS: int = 6


func _update_found() -> void:
	var store: InventoryStore = InventoryStore.instance
	if store == null:
		return
	if _found_box == null:
		_found_box = VBoxContainer.new()
		_found_box.anchor_top = 1.0
		_found_box.anchor_bottom = 1.0
		_found_box.offset_left = 18
		_found_box.offset_right = 262
		_found_box.offset_bottom = -30
		_found_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_found_box.alignment = BoxContainer.ALIGNMENT_END
		_found_box.add_theme_constant_override(&"separation", 4)
		_found_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shell.add_child(_found_box)
	var rows: Array[Dictionary] = store.recent_found(FOUND_ROWS)
	var key: String = ""
	for item: Dictionary in rows:
		key += "%s:%s:%s|" % [item["id"], item["count"], item.get("detail", "")]
	if key == _found_key:
		return
	_found_key = key
	for child: Node in _found_box.get_children():
		child.queue_free()
	_found_box.visible = not rows.is_empty()
	if rows.is_empty():
		return
	var head: Label = CosmicTheme.label("✦ Found  ·  click to use", 14, CosmicTheme.STARLIGHT_GOLD)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head_bg: StyleBoxFlat = CosmicTheme.flat(Color(CosmicTheme.DEEP, 0.85), Color(CosmicTheme.STARLIGHT_GOLD, 0.4), 1, 10, 4)
	head_bg.content_margin_left = 10
	head.add_theme_stylebox_override(&"normal", head_bg)
	_found_box.add_child(head)
	for item: Dictionary in rows:
		var b: Button = Button.new()
		var material: bool = item.has("kg")
		var amount: String = ("%.0f g" % (float(item["kg"]) * 1000.0)) if material else ("×%d" % int(item["count"]))
		b.text = "%s   %s" % [item["label"], amount]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(244, 32)
		b.focus_mode = Control.FOCUS_NONE
		b.icon = _swatch(item["color"] as Color)
		b.tooltip_text = ("Click: a scoop of %s goes into your hand. Hold it over a vessel and click to tip it in." if material else "Click: %s goes into your hand.") % item["label"]
		CosmicTheme.style_button(b, CosmicTheme.PRISM_CYAN if material else CosmicTheme.STARLIGHT_GOLD)
		b.add_theme_font_size_override(&"font_size", 14)
		var id: String = String(item["id"])
		b.pressed.connect(func() -> void:
			if InventoryStore.instance != null and InventoryStore.instance.take_to_hand(id) == null:
				show_toast(InventoryStore.instance.last_message, &"info"))
		_found_box.add_child(b)
	if store.recent_found(FOUND_ROWS + 1).size() > FOUND_ROWS:
		var more: Label = CosmicTheme.label("more in the satchel (Finds, Materials)", 12, Color(0.75, 0.72, 0.9))
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_found_box.add_child(more)


var _swatches: Dictionary = {}


## Small round colour dot for a Found row.
func _swatch(color: Color) -> Texture2D:
	var c: Color = Color(color.r, color.g, color.b, 1.0)
	var k: String = c.to_html(false)
	if not _swatches.has(k):
		var g: Gradient = Gradient.new()
		g.set_color(0, c.lightened(0.25))
		g.set_color(1, Color(c.r, c.g, c.b, 0.0))
		g.add_point(0.8, c)
		var tex: GradientTexture2D = GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 18
		tex.height = 18
		_swatches[k] = tex
	return _swatches[k]


## "✦ 3 found · Stove in 1 more": how far along the lab is.
func _update_discoveries() -> void:
	var dp: DiscoveryProgress = DiscoveryProgress.instance
	var on: bool = dp != null and dp.active
	_discoveries.visible = on
	if not on:
		return
	var n: int = dp.discovered_count()
	var next: Dictionary = dp.next_unlock()
	var text: String = "✦ %d found" % n
	if not next.is_empty():
		text += "  ·  %s in %d more" % [next["name"], next["remaining"]]
	text += "  ▾"
	if _leads_panel != null and _leads_panel.visible and n != _leads_count:
		_fill_leads()
	if _discoveries.text != text:
		_discoveries.text = text
		_discoveries.tooltip_text = "Click for things to try next.
Ingredients you have discovered. New things turn up when crushed rock powders meet water, vinegar or a flame.
Locked satchel rows (???) show a hint for each."


func _process(delta: float) -> void:
	_place_toasts()
	_update_satchel_tab()
	_update_lens_panel()
	if GrimoireJournal.instance != null:
		_coins.text = "◉ %d" % GrimoireJournal.instance.coins
	_update_discoveries()
	_update_found()
	_update_reveal(delta)
	var hint: String = grabber.assist_hint() if grabber != null else ""
	if _assist_hint.text != hint:
		_assist_hint.text = hint
	var hammer: Hammer3D = grabber.held_body as Hammer3D if grabber != null else null
	_strike.visible = hammer != null
	_charge_bar.visible = hammer != null and hammer.charging
	if _charge_bar.visible:
		_charge_bar.value = hammer.charge
		_strike.text = "RELEASE!" if hammer.charge >= 1.0 else "WINDING UP…"
	elif hammer != null:
		_strike.text = "STRIKE  [Space]"
	_load_rock.visible = LabCamera3D.instance != null and LabCamera3D.instance.station == 1
	# The pinned formula belongs to the potion bench.
	_pin_card.visible = _pin_shown != "" and (LabCamera3D.instance == null or LabCamera3D.instance.station == 0)
	if _pin_card.visible:
		# Float gently, like a page held up by magic.
		if not CosmicTheme.reduced_motion:
			_pin_card.position.y = _pin_base_y + sin(Time.get_ticks_msec() * 0.0015) * 4.0
			_pin_card.modulate.a = 0.9 + 0.08 * sin(Time.get_ticks_msec() * 0.0023)
		_pin_timer -= delta
		if _pin_timer <= 0.0:
			_pin_timer = 0.25
			var held_v: Vessel3D = grabber.held_body as Vessel3D if grabber != null else null
			if held_v != null:
				_pin_vessel = held_v
			elif camera != null:
				var hovered: Vessel3D = _pick(get_viewport().get_mouse_position()) as Vessel3D
				if hovered != null:
					_pin_vessel = hovered
			_update_pin_checks()
	if LabCamera3D.instance != null:
		for i: int in _station_buttons.size():
			_station_buttons[i].button_pressed = LabCamera3D.instance.station == i
	var book_open: bool = (GrimoireBookUI.instance != null and GrimoireBookUI.instance.is_open()) or (SafetySheetUI.instance != null and SafetySheetUI.instance.is_open())
	if book_open or _help.visible or camera == null:
		_inspector.visible = false
		return
	# Hidden while carrying (the hint line at the bottom says what is going
	# on); otherwise a one-line label after resting on something briefly.
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var target: Object = null if grabber != null and grabber.held_body != null else _pick(mouse)
	if target != _inspect_target:
		_inspect_target = target
		_inspect_wait = 0.35
	_inspect_wait -= delta
	var detailed: bool = Input.is_key_pressed(KEY_ALT)
	var text: String = (describe(target) if detailed else describe_short(target)) if _inspect_wait <= 0.0 or detailed else ""
	_inspector.visible = text != ""
	if _inspector.visible:
		if _inspector_label.text != text:
			_inspector_label.text = text
			_inspector_label.custom_minimum_size = Vector2(320.0 if detailed else 0.0, 0.0)
			_inspector_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if detailed else TextServer.AUTOWRAP_OFF
			_inspector.reset_size()
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var pos: Vector2 = mouse + Vector2(16.0, 14.0)
		pos.x = minf(pos.x, vp.x - _inspector.size.x - 8.0)
		pos.y = minf(pos.y, vp.y - _inspector.size.y - 8.0)
		_inspector.position = pos


func _pick(screen: Vector2) -> Object:
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var origin: Vector3 = camera.project_ray_origin(screen)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 6.0,
		SimConstants.LAYER_RIGID_VESSEL | SimConstants.LAYER_SOLID_REAGENT | SimConstants.LAYER_TACTILE_TOOL | SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_CLICK_TARGET)
	var hit: Dictionary = space.intersect_ray(query)
	var collider: Object = hit.get("collider", null)
	if collider is StaticBody3D:
		# Machines and stands: the nearest owner that can describe itself.
		var n: Node = collider as Node
		for i: int in 4:
			if n == null:
				break
			if n.has_method(&"hover_info"):
				return n
			n = n.get_parent()
		return null
	return collider


## One short line for the hover label: name plus the most useful number.
static func describe_short(target: Object) -> String:
	if target != null and target.has_method(&"hover_info"):
		return String(target.call(&"hover_info"))
	if target is Vessel3D:
		var v: Vessel3D = target as Vessel3D
		var m: MixtureContainer = v.mixture
		if m == null or m.get_liquid_volume_m3() * 1e6 < 0.5:
			return "Empty %s" % _vessel_kind(v)
		var tag: String = "  [color=#FF9A5C]burning[/color]" if m.burning else ("  [color=#8FE9FF]boiling[/color]" if v.is_boiling else "")
		if v.discovery_warmth >= 0.92:
			tag += "  [color=#F4D06F]✦ Almost there! %s[/color]" % v.discovery_hint
		elif v.discovery_warmth >= 0.78:
			tag += "  [color=#F4D06F]✦ Getting warm…[/color]"
		return "[b]%s[/b]  [color=#5CE1E6]%.0f mL · %.0f °C[/color]%s" % [Vessel3D.contents_tag_text(m, v.foam_height_meters), m.get_liquid_volume_m3() * 1e6, m.temperature_kelvin - 273.15, tag]
	if target is Rock3D:
		var rock: Rock3D = target as Rock3D
		return "[b]%s[/b]  [color=#%s]%s[/color]" % [rock.describe_name(), CosmicTheme.rarity_aura(rock.mineral.rarity).to_html(false), "★".repeat(rock.mineral.rarity + 1)]
	if target is Hammer3D:
		return "[b]Hammer[/b]"
	if target is MachineHandle3D:
		var handle: MachineHandle3D = target as MachineHandle3D
		return "[b]%s[/b]  [color=#B3ADD6]%s[/color]" % [handle.label, handle.hint.to_lower()]
	if target is StirTool3D:
		return "[b]%s[/b]" % String((target as StirTool3D).name).capitalize()
	if target is Berry3D:
		return "[b]%s[/b]" % (target as Berry3D).juice.display_name.replace(" Juice", "")
	return ""


static func describe(target: Object) -> String:
	if target != null and target.has_method(&"hover_info"):
		return String(target.call(&"hover_info"))
	if target is Vessel3D:
		var v: Vessel3D = target as Vessel3D
		var m: MixtureContainer = v.mixture
		if m == null or m.get_liquid_volume_m3() * 1e6 < 0.5:
			return "[b]Empty %s[/b]\n[color=#B3ADD6]Pour something in, or take reagents from the satchel.[/color]" % _vessel_kind(v)
		var flags: PackedStringArray = PackedStringArray()
		if m.burning:
			flags.append("[color=#FF9A5C]burning[/color]")
		if v.is_boiling:
			flags.append("[color=#8FE9FF]boiling[/color]")
		if v.sealed:
			flags.append("[color=#F4D06F]corked[/color]")
		if m.gas_generation_mol_s > 0.002:
			flags.append("fizzing")
		if m.precipitation_rate_mol_s > 0.0 or v.suspension_level > 0.05:
			flags.append("precipitating")
		if m.transmutation_rate_mol_s > 0.0:
			flags.append("[color=#F4D06F]transmuting[/color]")
		return "[b]%s[/b]\n[color=#5CE1E6]%.1f °C  ·  %.0f mL  ·  pH %.1f  ·  %s[/color]\n[color=#B3ADD6]%s[/color]%s" % [
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
		var finish: String = ""
		if rock.polish > 0.01 or rock.cut != RockMeshes.Cut.NONE:
			finish = "\n[color=#B3ADD6]Polish[/color] [color=#F4D06F]%s[/color]" % _meter(rock.polish)
			if rock.cut != RockMeshes.Cut.NONE:
				finish += "   [color=#B3ADD6]Cut quality[/color] [color=#FF6B9D]%s[/color] %d%%" % [_meter(rock.cut_quality), int(rock.cut_quality * 100.0)]
		return "[b]%s[/b]   [color=#%s]%s %s[/color]\n[color=#5CE1E6]%s  ·  Mohs %.1f  ·  %.0f g  ·  %d ◉[/color]%s\n[color=#D9D3F5][i]%s[/i][/color]\n[color=#B3ADD6]%s[/color]" % [
			rock.describe_name(), CosmicTheme.rarity_aura(m.rarity).to_html(false), "★".repeat(m.rarity + 1), m.rarity_name(), m.formula, m.hardness_mohs,
			rock.mass_kg * 1000.0, rock.value(), finish, m.fun_fact.get_slice(".", 0) + ".", hint]
	if target is Hammer3D:
		return "[b]Geologist's Hammer[/b]\n[color=#B3ADD6]Pick it up, hold it over a rock and click (or Space) to strike.[/color]"
	if target is MachineHandle3D:
		return "[b]Handle[/b]\n[color=#B3ADD6]Grab and drag it to work the machine.[/color]"
	if target is StirTool3D:
		var tool: StirTool3D = target as StirTool3D
		var hint: String = "spins liquids the opposite way" if tool.chirality_bias_rad_s > 0.0 and tool.chirality_sign < 0.0 else ("whips up foam" if tool.agitation_gain > 1.5 else "drag it through a liquid to stir")
		return "[b]%s[/b]\n[color=#B3ADD6]%s[/color]" % [String(tool.name).capitalize(), hint]
	if target is Berry3D:
		var berry: Berry3D = target as Berry3D
		return "[b]%s[/b]  [color=#F4D06F]%s[/color]\n[color=#B3ADD6]Drop it into a vessel to burst it.[/color]" % [berry.juice.display_name.replace(" Juice", ""), berry.juice.chemical_formula]
	return ""


## Ten-pip text meter, e.g. ◆◆◆◆◆◆◇◇◇◇ for 0.6.
static func _meter(fraction: float) -> String:
	var n: int = clampi(int(round(fraction * 10.0)), 0, 10)
	return "◆".repeat(n) + "◇".repeat(10 - n)


static func _vessel_kind(v: Vessel3D) -> String:
	return v.profile.vessel_name.replace("_", " ") if v.profile != null else "vessel"



## Toasts sit in the bottom-right corner, or just left of the satchel while
## it is open.
func _place_toasts() -> void:
	var right: float = -24.0
	var satchel: Node = get_node_or_null("../InventoryPanel")
	if satchel != null:
		var root: Control = satchel.get("_root") as Control
		if root != null and root.visible:
			var vp_w: float = get_viewport().get_visible_rect().size.x
			right = minf(right, root.get_global_rect().position.x - vp_w - 16.0)
	if _toasts.offset_right != right:
		_toasts.offset_right = right
		_toasts.offset_left = right - TOAST_WIDTH


# --- Satchel pocket: drop anything held into storage with the mouse ---------------

var _satchel_tab: Button


## A glowing pocket tab on the right edge while something is held: click it
## to put the item away (same as E).
func _build_satchel_tab() -> void:
	_satchel_tab = Button.new()
	_satchel_tab.text = "⤓\nPut in\nsatchel"
	_satchel_tab.tooltip_text = "Put the held item in the satchel (E)"
	_satchel_tab.anchor_left = 1.0
	_satchel_tab.anchor_right = 1.0
	_satchel_tab.anchor_top = 0.5
	_satchel_tab.anchor_bottom = 0.5
	_satchel_tab.offset_left = -92.0
	_satchel_tab.offset_right = -8.0
	_satchel_tab.offset_top = -56.0
	_satchel_tab.offset_bottom = 56.0
	_satchel_tab.add_theme_font_size_override(&"font_size", 15)
	_satchel_tab.add_theme_stylebox_override(&"normal", CosmicTheme.glow(CosmicTheme.STARLIGHT_GOLD, 10, 6, Color(CosmicTheme.DEEP, 0.88), 1))
	_satchel_tab.add_theme_stylebox_override(&"hover", CosmicTheme.glow(CosmicTheme.STARLIGHT_GOLD, 10, 14, Color(CosmicTheme.NEBULA, 0.95), 2))
	_satchel_tab.visible = false
	_satchel_tab.pressed.connect(func() -> void:
		if grabber != null and grabber.held_body != null and InventoryStore.instance != null:
			if InventoryStore.instance.stash(grabber.held_body):
				show_toast(InventoryStore.instance.last_message, &"info")
				AudioDirector.play_ui(&"ui_close", -8.0))
	_shell.add_child(_satchel_tab)


func _update_satchel_tab() -> void:
	if _satchel_tab != null:
		_satchel_tab.visible = grabber != null and grabber.held_body != null and not (grabber.held_body is MachineHandle3D)


# --- Alchemist's Lens: quick readings while holding the magnifying glass -----------

var _lens_panel: PanelContainer
var _lens_title: Label
var _lens_bars: Dictionary = {}


func _build_lens_panel() -> void:
	_lens_panel = PanelContainer.new()
	_lens_panel.add_theme_stylebox_override(&"panel", CosmicTheme.glow(CosmicTheme.STARLIGHT_GOLD, 12, 8, Color(0.063, 0.055, 0.11, 0.9), 1))
	_lens_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens_panel.visible = false
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	_lens_panel.add_child(col)
	_lens_title = CosmicTheme.label("Alchemist's Lens", 17, CosmicTheme.STARLIGHT_GOLD, CosmicTheme.display_font())
	col.add_child(_lens_title)
	for key: String in ["Temperature", "Acidity", "Thickness", "Arcane aura"]:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var name_label: Label = CosmicTheme.label(key, 15, CosmicTheme.TEXT)
		name_label.custom_minimum_size = Vector2(110.0, 0.0)
		row.add_child(name_label)
		var bar: ProgressBar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(150.0, 14.0)
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.0
		row.add_child(bar)
		var value_label: Label = CosmicTheme.label("", 15, CosmicTheme.PRISM_CYAN, CosmicTheme.mono_font())
		value_label.custom_minimum_size = Vector2(90.0, 0.0)
		row.add_child(value_label)
		col.add_child(row)
		_lens_bars[key] = [bar, value_label]
	_shell.add_child(_lens_panel)


func _lens_bar(key: String, fraction: float, text: String, color: Color) -> void:
	var pair: Array = _lens_bars[key]
	var bar: ProgressBar = pair[0]
	bar.value = clampf(fraction, 0.0, 1.0)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override(&"fill", fill)
	(pair[1] as Label).text = text


func _update_lens_panel() -> void:
	if _lens_panel == null:
		return
	var lens: MagnifyingLens3D = grabber.held_body as MagnifyingLens3D if grabber != null else null
	var v: Vessel3D = lens.target if lens != null else null
	_lens_panel.visible = v != null and v.mixture != null and v.mixture.get_total_mass_kg() > 1e-6
	if not _lens_panel.visible:
		return
	var m: MixtureContainer = v.mixture
	var t_c: float = m.temperature_kelvin - 273.15
	var ph: float = m.get_ph()
	var visc: float = m.get_liquid_viscosity_pas()
	var aura: Color = m.get_emission_hdr()
	var arcane: float = clampf(m.get_total_thaums() / maxf(m.get_total_moles(), 1e-9) / 60.0 + (aura.r + aura.g + aura.b) * 0.3, 0.0, 1.0)
	_lens_title.text = "Alchemist's Lens  ·  %s" % Vessel3D.contents_tag_text(m, v.foam_height_meters).get_slice(" (", 0)
	_lens_bar("Temperature", (t_c + 20.0) / 220.0, "%.0f °C" % t_c, Color(0.35, 0.6, 1.0).lerp(Color(1.0, 0.35, 0.15), clampf((t_c - 10.0) / 120.0, 0.0, 1.0)))
	var ph_color: Color = Color(1.0, 0.3, 0.2) if ph < 5.0 else (Color(0.4, 0.85, 0.4) if ph <= 9.0 else Color(0.45, 0.4, 1.0))
	_lens_bar("Acidity", ph / 14.0, "pH %.1f" % ph, ph_color)
	var thick: float = clampf((log(maxf(visc, 1e-4)) / log(10.0) + 3.0) / 5.0, 0.0, 1.0)
	_lens_bar("Thickness", thick, "runny" if thick < 0.3 else ("syrupy" if thick < 0.7 else "very thick"), Color(0.85, 0.7, 0.35))
	_lens_bar("Arcane aura", arcane, "none" if arcane < 0.05 else ("faint" if arcane < 0.35 else ("strong" if arcane < 0.75 else "blazing")), Color(0.7, 0.45, 1.0))
	if v.discovery_warmth >= 0.78:
		_lens_title.text += "\n✦ " + ("Almost there! " if v.discovery_warmth >= 0.92 else "Getting warm… ") + v.discovery_hint
	_lens_panel.reset_size()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var pos: Vector2 = get_viewport().get_mouse_position() + Vector2(24.0, -_lens_panel.size.y - 12.0)
	_lens_panel.position = Vector2(clampf(pos.x, 8.0, vp.x - _lens_panel.size.x - 8.0), clampf(pos.y, 70.0, vp.y - _lens_panel.size.y - 8.0))