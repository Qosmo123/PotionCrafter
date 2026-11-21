extends CanvasLayer
## Alchemist's readout (F3 toggles): per-vessel procedural name, temperature,
## volume, pH, composition formula, and any reaction equations happening now.
## The diegetic Spectrometer/Grimoire book will replace this panel later.

const REFRESH_SECONDS: float = 0.25

var _label: RichTextLabel
var _timer: float = 0.0


func _ready() -> void:
	visible = false  # Debug readout: F3. The hover inspector covers everyday play.
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	margin.add_theme_constant_override(&"margin_left", maxi(16, safe.position.x))
	margin.add_theme_constant_override(&"margin_top", maxi(16, safe.position.y))
	add_child(margin)
	CosmicTheme.apply(margin)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", CosmicTheme.glass(CosmicTheme.PRISM_CYAN, 12, 1))
	margin.add_child(panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(620, 0)
	_label.add_theme_font_size_override(&"normal_font_size", 17)
	_label.add_theme_color_override(&"default_color", CosmicTheme.TEXT)
	_label.add_theme_font_override(&"mono_font", CosmicTheme.mono_font())
	panel.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		visible = not visible


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or not visible:
		return
	_timer = REFRESH_SECONDS
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[color=#c9a35a]Drag[/color] move · [color=#c9a35a]Wheel[/color] zoom / tilt while holding · [color=#c9a35a]M[/color] stirrer · [color=#c9a35a]F5[/color] %s · [color=#c9a35a]F3[/color] hide" % GraphicsProfile.active_preset_name)
	lines.append("[color=#c9a35a]C[/color] chalk sigils · [color=#c9a35a]X[/color] wipe  [color=#d7b6ff]%s[/color]" % ChalkDrawing3D.last_result_text)
	if RecipeBook.instance != null and RecipeBook.instance.last_discovery_text != "":
		lines.append("[color=#ffd36e][b]%s[/b][/color]" % RecipeBook.instance.last_discovery_text)
	lines.append("[color=#c9a35a]Tab[/color] satchel · [color=#c9a35a]E[/color] store held item")
	for vessel: Vessel3D in Vessel3D.all_vessels:
		var m: MixtureContainer = vessel.mixture
		if m == null or m.get_liquid_volume_m3() * 1e6 < 0.5:
			continue
		lines.append("[b]%s[/b]  [color=#9fb7c9]%.1f °C · %.0f mL · pH %.1f[/color]" % [
			PotionNamer.name_for(m, vessel.foam_height_meters),
			m.temperature_kelvin - 273.15, m.get_liquid_volume_m3() * 1e6, m.get_ph()])
		lines.append("   [color=#a89a80]%s[/color]" % PotionNamer.formula_for(m))
		for eq: String in PotionNamer.equations_for(m):
			lines.append("   [color=#e8b04a]⚗ %s[/color]" % eq)
	_label.text = "\n".join(lines)
