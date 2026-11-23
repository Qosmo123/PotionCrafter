class_name CosmicTheme
extends RefCounted
## The Cosmic Design System: palette tokens, type scale, spacing grid and the
## shared Theme every screen-space UI uses (HUD, satchel, Astral Grimoire,
## safety sheet). Presentation only: no game state lives here.
##
## Tokens
##   Void      #090A14  deepest background       Deep     #121329  panels
##   Nebula    #4A2574  hover / pressed fills     Violet   #7B3FE4  active fills
##   Gold      #F4D06F  borders, headings, coins  Cyan     #5CE1E6  data, info
##   Pink      #FF6B9D  new / rare / secret       Text     #ECE8FF  body copy
## Text on Glass (Deep at 85 %) reaches ~14:1 contrast; TEXT_DIM ~7:1.

# --- Palette ----------------------------------------------------------------------------
const VOID: Color = Color("#090A14")
const DEEP: Color = Color("#121329")
const NEBULA: Color = Color("#4A2574")
const VIOLET: Color = Color("#7B3FE4")
const STARLIGHT_GOLD: Color = Color("#F4D06F")
const PRISM_CYAN: Color = Color("#5CE1E6")
const PRISM_PINK: Color = Color("#FF6B9D")
const TEXT: Color = Color("#ECE8FF")
const TEXT_DIM: Color = Color("#B3ADD6")
const TEXT_FAINT: Color = Color("#7D77A3")
const SUCCESS: Color = Color("#7FE0A0")
const WARNING: Color = Color("#FFB45C")
const GLASS: Color = Color(0.071, 0.075, 0.161, 0.84)
const GLASS_LIGHT: Color = Color(0.11, 0.1, 0.22, 0.78)

# BBCode-ready hex strings for RichTextLabels.
const HEX_GOLD: String = "#F4D06F"
const HEX_CYAN: String = "#5CE1E6"
const HEX_PINK: String = "#FF6B9D"
const HEX_DIM: String = "#B3ADD6"
const HEX_FAINT: String = "#7D77A3"
const HEX_VIOLET: String = "#B18CFF"
const HEX_GREEN: String = "#7FE0A0"
const HEX_EMBER: String = "#FF9A5C"

# --- Layout grid (8 px base, 1920x1080 reference) ---------------------------------------
const GRID: int = 8
const RADIUS: int = 10
const TOUCH_MIN: int = 48
const GUTTER: int = 16

# --- Type scale ---------------------------------------------------------------------------
const SIZE_CAPTION: int = 15
const SIZE_BODY: int = 16
const SIZE_SUBHEAD: int = 19
const SIZE_TITLE: int = 26
const SIZE_HERO: int = 32

const GLASS_SHADER: Shader = preload("res://visuals_3d/ui/glass_blur.gdshader")

## Accessibility: when true, screen shake and big scale-ins are skipped.
static var reduced_motion: bool = false
static var _theme: Theme = null
static var _fonts: Dictionary = {}
static var _orbs: Dictionary = {}
static var _glass_material: ShaderMaterial = null


# --- Fonts ------------------------------------------------------------------------------
# Bundled OFL fonts (res://assets/fonts, licences alongside), each with system
# fallbacks in case a file is missing:
#   display  Fraunces SemiBold: titles, grimoire headings
#   body     Atkinson Hyperlegible: UI text, tooltips (Bold for labels)
#   mono     JetBrains Mono: formulas, live numbers (fixed-width digits)
#   chalk    Caveat: hand lettering on the chalkboard and notes
#   world    Atkinson Hyperlegible Bold, MSDF: 3D labels, sharp at any zoom

const FONT_DIR: String = "res://assets/fonts/"


## Engraved display serif for titles and tome headings.
static func display_font() -> Font:
	return _font(&"display", "Fraunces.ttf", 600, ["Cinzel", "Palatino Linotype", "Georgia", "serif"])


## Highly legible sans for body copy.
static func body_font() -> Font:
	return _font(&"body", "AtkinsonHyperlegible-Regular.ttf", 0, ["Segoe UI", "Roboto", "Arial", "sans-serif"])


## Monospace for numbers, carats, ratios and formulas.
static func mono_font() -> Font:
	return _font(&"mono", "JetBrainsMono.ttf", 450, ["Cascadia Mono", "Consolas", "monospace"])


## Hand lettering (chalkboard, notes).
static func chalk_font() -> Font:
	return _font(&"chalk", "Caveat.ttf", 600, ["Segoe Print", "Comic Sans MS", "cursive"])


## Bold, MSDF-rendered sans for Label3D text in the world.
static func world_font() -> Font:
	return _font(&"world", "AtkinsonHyperlegible-Bold.ttf", 0, ["Segoe UI", "Arial", "sans-serif"])


## Load a bundled font (optionally at a variable-font weight); fall back to
## system fonts if the file is missing.
static func _font(key: StringName, file: String, weight: int, fallback_names: PackedStringArray) -> Font:
	if _fonts.has(key):
		return _fonts[key]
	var f: Font = null
	if ResourceLoader.exists(FONT_DIR + file):
		var data: FontFile = load(FONT_DIR + file) as FontFile
		if data != null:
			if weight > 0:
				var v: FontVariation = FontVariation.new()
				v.base_font = data
				v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
				f = v
			else:
				f = data
	if f == null:
		var sys: SystemFont = SystemFont.new()
		sys.font_names = fallback_names
		sys.font_weight = weight if weight > 0 else 400
		sys.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		sys.hinting = TextServer.HINTING_LIGHT
		sys.allow_system_fallback = true
		f = sys
	_fonts[key] = f
	return f


# --- Style boxes --------------------------------------------------------------------------

## Glass panel with gold filigree. `accent` tints the border and filigree.
static func glass(accent: Color = STARLIGHT_GOLD, margin: int = 14, filigree: int = 2, bg: Color = GLASS, radius: int = RADIUS) -> CosmicStyleBox:
	var s: CosmicStyleBox = CosmicStyleBox.new()
	s.bg_color = bg
	s.border_color = Color(accent, 0.6)
	s.filigree_color = accent
	s.filigree = filigree
	s.corner_radius = radius
	s.set_content_margin_all(margin)
	return s


## A glowing glass panel (toasts, active tabs, rare cards).
static func glow(accent: Color, margin: int = 12, glow_size: int = 10, bg: Color = GLASS, filigree: int = 1) -> CosmicStyleBox:
	var s: CosmicStyleBox = glass(accent, margin, filigree, bg)
	s.glow_color = Color(accent, 0.35)
	s.glow_size = glow_size
	s.border_width = 1
	return s


## Plain flat box (chips, buttons, bars) on the palette.
static func flat(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = RADIUS, margin: int = 10) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


static func _button_box(bg: Color, border: Color, glow_col: Color = Color(0, 0, 0, 0), glow_px: int = 0) -> StyleBoxFlat:
	var s: StyleBoxFlat = flat(bg, border, 1, 8, 10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.shadow_color = glow_col
	s.shadow_size = glow_px
	return s


## Apply the standard button look (normal/hover/pressed/focus/disabled) to one button.
static func style_button(b: Button, accent: Color = STARLIGHT_GOLD, prominent: bool = false) -> void:
	var base: Color = Color(NEBULA, 0.55) if prominent else Color(DEEP, 0.82)
	b.add_theme_stylebox_override(&"normal", _button_box(base, Color(accent, 0.45)))
	b.add_theme_stylebox_override(&"hover", _button_box(Color(NEBULA, 0.8), Color(accent, 0.85), Color(accent, 0.25), 6))
	b.add_theme_stylebox_override(&"pressed", _button_box(Color(VIOLET, 0.75), accent, Color(accent, 0.45), 10))
	b.add_theme_stylebox_override(&"hover_pressed", _button_box(Color(VIOLET, 0.85), accent, Color(accent, 0.55), 12))
	b.add_theme_stylebox_override(&"focus", _focus_box(accent))
	b.add_theme_stylebox_override(&"disabled", _button_box(Color(VOID, 0.6), Color(TEXT_FAINT, 0.3)))
	b.add_theme_color_override(&"font_color", TEXT)
	b.add_theme_color_override(&"font_hover_color", accent.lightened(0.25))
	b.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	b.add_theme_color_override(&"font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override(&"font_disabled_color", TEXT_FAINT)


## Keyboard focus ring: cyan, never hidden (accessibility).
static func _focus_box(accent: Color = PRISM_CYAN) -> StyleBoxFlat:
	var s: StyleBoxFlat = flat(Color(0, 0, 0, 0), Color(PRISM_CYAN if accent == STARLIGHT_GOLD else accent, 0.9), 2, 9, 0)
	s.draw_center = false
	s.expand_margin_left = 2
	s.expand_margin_right = 2
	s.expand_margin_top = 2
	s.expand_margin_bottom = 2
	return s


## Rune tab: dim when idle, glowing violet-gold when active.
static func rune_tab(active: bool, accent: Color = STARLIGHT_GOLD) -> StyleBoxFlat:
	var s: StyleBoxFlat
	if active:
		s = _button_box(Color(VIOLET, 0.55), accent, Color(accent, 0.4), 9)
		s.border_width_bottom = 2
	else:
		s = _button_box(Color(DEEP, 0.7), Color(TEXT_FAINT, 0.35))
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


# --- The Theme ------------------------------------------------------------------------------

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = Theme.new()
	t.default_font = body_font()
	t.default_font_size = SIZE_BODY
	# Buttons
	var b: Button = Button.new()
	style_button(b)
	for sb_name: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		t.set_stylebox(sb_name, &"Button", b.get_theme_stylebox(sb_name))
	for c_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_disabled_color"]:
		t.set_color(c_name, &"Button", b.get_theme_color(c_name))
	t.set_color(&"font_focus_color", &"Button", TEXT)
	b.free()
	# Labels & rich text
	t.set_color(&"font_color", &"Label", TEXT)
	t.set_color(&"font_shadow_color", &"Label", Color(VOID, 0.6))
	t.set_color(&"default_color", &"RichTextLabel", TEXT)
	t.set_font(&"bold_font", &"RichTextLabel", _bold_body())
	t.set_font(&"mono_font", &"RichTextLabel", mono_font())
	# Panels
	t.set_stylebox(&"panel", &"PanelContainer", glass())
	t.set_stylebox(&"panel", &"Panel", glass())
	# Tooltips: glass with a cyan edge
	var tip: CosmicStyleBox = glass(PRISM_CYAN, 10, 1)
	t.set_stylebox(&"panel", &"TooltipPanel", tip)
	t.set_color(&"font_color", &"TooltipLabel", TEXT)
	t.set_font_size(&"font_size", &"TooltipLabel", 15)
	# Line edits
	t.set_stylebox(&"normal", &"LineEdit", flat(Color(VOID, 0.75), Color(VIOLET, 0.55), 1, 8, 10))
	t.set_stylebox(&"focus", &"LineEdit", _focus_box())
	t.set_color(&"font_color", &"LineEdit", TEXT)
	t.set_color(&"font_placeholder_color", &"LineEdit", TEXT_FAINT)
	t.set_color(&"caret_color", &"LineEdit", PRISM_CYAN)
	t.set_color(&"selection_color", &"LineEdit", Color(VIOLET, 0.5))
	# Tab containers: glowing rune tabs
	t.set_stylebox(&"tab_selected", &"TabContainer", rune_tab(true))
	t.set_stylebox(&"tab_unselected", &"TabContainer", rune_tab(false))
	t.set_stylebox(&"tab_hovered", &"TabContainer", _button_box(Color(NEBULA, 0.75), Color(STARLIGHT_GOLD, 0.6)))
	t.set_stylebox(&"tab_focus", &"TabContainer", _focus_box())
	t.set_stylebox(&"panel", &"TabContainer", flat(Color(VOID, 0.35), Color(STARLIGHT_GOLD, 0.18), 1, 8, 8))
	t.set_stylebox(&"tabbar_background", &"TabContainer", StyleBoxEmpty.new())
	t.set_color(&"font_selected_color", &"TabContainer", Color.WHITE)
	t.set_color(&"font_unselected_color", &"TabContainer", TEXT_DIM)
	t.set_color(&"font_hovered_color", &"TabContainer", STARLIGHT_GOLD)
	t.set_constant(&"side_margin", &"TabContainer", 0)
	# Scrollbars: slim violet thread
	for sb_type: StringName in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox(&"scroll", sb_type, flat(Color(VOID, 0.4), Color(0, 0, 0, 0), 0, 4, 3))
		t.set_stylebox(&"grabber", sb_type, flat(Color(VIOLET, 0.65), Color(0, 0, 0, 0), 0, 4, 3))
		t.set_stylebox(&"grabber_highlight", sb_type, flat(Color(STARLIGHT_GOLD, 0.7), Color(0, 0, 0, 0), 0, 4, 3))
		t.set_stylebox(&"grabber_pressed", sb_type, flat(STARLIGHT_GOLD, Color(0, 0, 0, 0), 0, 4, 3))
	# Progress bars: nebula track, gold-to-cyan fill
	t.set_stylebox(&"background", &"ProgressBar", flat(Color(VOID, 0.7), Color(VIOLET, 0.4), 1, 6, 0))
	t.set_stylebox(&"fill", &"ProgressBar", flat(STARLIGHT_GOLD, Color(0, 0, 0, 0), 0, 6, 0))
	t.set_color(&"font_color", &"ProgressBar", TEXT)
	_theme = t
	return t


static func _bold_body() -> Font:
	return _font(&"body_bold", "AtkinsonHyperlegible-Bold.ttf", 0, ["Segoe UI", "Arial", "sans-serif"])


## Give a top-level control (direct child of a CanvasLayer) the cosmic theme.
static func apply(control: Control) -> void:
	control.theme = theme()


# --- Glass blur (PC tier only) ---------------------------------------------------------

## Frosted-glass backdrop: blurs whatever is behind the panel. PC only; mobile
## tiers keep the plain translucent glass (no screen-texture reads on tilers).
static func frost(panel: CanvasItem) -> void:
	if QualityTier.is_mobile_tier() or DisplayServer.get_name() == "headless":
		return
	if _glass_material == null:
		_glass_material = ShaderMaterial.new()
		_glass_material.shader = GLASS_SHADER
	panel.material = _glass_material


# --- Text helpers ----------------------------------------------------------------------

static func label(text: String, size: int = SIZE_BODY, color: Color = TEXT, font: Font = null) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	if font != null:
		l.add_theme_font_override(&"font", font)
	return l


static func title(text: String, size: int = SIZE_TITLE, color: Color = STARLIGHT_GOLD) -> Label:
	var l: Label = label(text, size, color, display_font())
	l.add_theme_color_override(&"font_shadow_color", Color(color, 0.35))
	l.add_theme_constant_override(&"shadow_offset_x", 0)
	l.add_theme_constant_override(&"shadow_offset_y", 0)
	l.add_theme_constant_override(&"shadow_outline_size", 6)
	return l


# --- Colour helpers -------------------------------------------------------------------

## Rarity aura colours: common silver, uncommon cyan, rare violet, epic pink, legendary gold.
static func rarity_aura(rarity: int) -> Color:
	return [Color("#C9CCE0"), PRISM_CYAN, Color("#B18CFF"), PRISM_PINK, STARLIGHT_GOLD][clampi(rarity, 0, 4)]


static func toast_color(kind: StringName) -> Color:
	match kind:
		&"discovery": return STARLIGHT_GOLD
		&"secret": return PRISM_PINK
		&"bottle": return PRISM_CYAN
		&"coins": return STARLIGHT_GOLD
		&"warning": return WARNING
		&"tip": return PRISM_CYAN.lerp(TEXT, 0.35)
	return TEXT_DIM


## A small glowing orb icon in `color` (cached). `aura` > 0 adds a coloured halo
## for rare items; legendary gets a starlight ring.
static func orb_icon(color: Color, aura: int = 0, px: int = 26) -> ImageTexture:
	var key: String = "%s_%d_%d" % [color.to_html(false), aura, px]
	if _orbs.has(key):
		return _orbs[key]
	var img: Image = Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c: Vector2 = Vector2(px, px) * 0.5
	var core_r: float = px * (0.3 if aura > 0 else 0.36)
	var halo: Color = rarity_aura(aura)
	for y: int in px:
		for x: int in px:
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			var d: float = p.distance_to(c)
			var out: Color = Color(0, 0, 0, 0)
			if aura > 0:
				var g: float = clampf(1.0 - (d - core_r) / (px * 0.5 - core_r), 0.0, 1.0)
				out = Color(halo, g * g * 0.75)
				if aura >= 4 and absf(d - px * 0.44) < 0.8:
					out = Color(STARLIGHT_GOLD, 0.9)
			if d <= core_r + 0.5:
				var hl: float = clampf(1.0 - p.distance_to(c + Vector2(-core_r, -core_r) * 0.4) / core_r, 0.0, 1.0)
				var body: Color = Color(color, 1.0).lerp(Color.WHITE, hl * hl * 0.6)
				body = body.darkened(clampf(d / core_r - 0.6, 0.0, 0.4) * 0.6)
				var edge: float = clampf(core_r + 0.5 - d, 0.0, 1.0)
				out = out.blend(Color(body, edge))
			img.set_pixel(x, y, out)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_orbs[key] = tex
	return tex


# --- Ambience --------------------------------------------------------------------------

const BACKDROP_SHADER: Shader = preload("res://visuals_3d/ui/cosmic_backdrop.gdshader")


## Full-rect astral backdrop (nebula + twinkling stars + stardust) to sit
## behind modal books and sheets. Clicking it emits `gui_input` as usual.
static func backdrop(opacity: float = 0.88) -> ColorRect:
	var r: ColorRect = ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	mat.set_shader_parameter(&"opacity", opacity)
	r.material = mat
	r.resized.connect(func() -> void:
		if r.size.y > 0.0:
			mat.set_shader_parameter(&"aspect", r.size.x / r.size.y))
	return r


## Ethereal reveal: fade in with a slight scale-up from the control's centre.
static func reveal(c: Control, seconds: float = 0.24, from_scale: float = 0.965) -> Tween:
	c.pivot_offset = c.size * 0.5
	c.modulate.a = 0.0
	c.scale = Vector2(from_scale, from_scale)
	var tw: Tween = c.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, seconds)
	tw.tween_property(c, "scale", Vector2.ONE, seconds)
	return tw


## Gentle "can't do that" shake for invalid actions.
static func shake(c: Control, pixels: float = 8.0) -> void:
	var x0: float = c.position.x
	var tw: Tween = c.create_tween()
	for k: int in 4:
		tw.tween_property(c, "position:x", x0 + (pixels if k % 2 == 0 else -pixels) * (1.0 - k * 0.22), 0.05)
	tw.tween_property(c, "position:x", x0, 0.05)
