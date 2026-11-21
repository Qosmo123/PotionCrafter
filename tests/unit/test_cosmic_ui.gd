extends "res://tests/unit/unit_test_base.gd"
## Cosmic Design System and Astral Grimoire helpers (presentation only).


func _luminance(c: Color) -> float:
	var f: Callable = func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_theme_builds_once_with_core_styles() -> void:
	var t: Theme = CosmicTheme.theme()
	check(t == CosmicTheme.theme(), "the theme is built once and cached")
	check(t.has_stylebox(&"tab_selected", &"TabContainer"), "rune tabs are themed")
	check(t.get_stylebox(&"panel", &"PanelContainer") is CosmicStyleBox, "panels use the filigree glass box")
	check(t.has_stylebox(&"focus", &"Button"), "buttons keep a visible keyboard focus ring")
	check(t.default_font != null, "a body font is set")


func test_text_contrast_meets_wcag_on_glass() -> void:
	var glass_on_void: Color = CosmicTheme.VOID.lerp(Color(CosmicTheme.GLASS, 1.0), CosmicTheme.GLASS.a)
	check(_contrast(CosmicTheme.TEXT, glass_on_void) >= 7.0, "body text is AAA on glass (%.1f:1)" % _contrast(CosmicTheme.TEXT, glass_on_void))
	check(_contrast(CosmicTheme.TEXT_DIM, glass_on_void) >= 4.5, "dim text is AA on glass (%.1f:1)" % _contrast(CosmicTheme.TEXT_DIM, glass_on_void))
	check(_contrast(CosmicTheme.STARLIGHT_GOLD, glass_on_void) >= 4.5, "gold headings are AA on glass")


func test_orb_icons_are_cached_and_sized() -> void:
	var a: ImageTexture = CosmicTheme.orb_icon(Color.RED, 0, 24)
	check(a == CosmicTheme.orb_icon(Color.RED, 0, 24), "same orb returns the cached texture")
	check(a.get_width() == 24 and a.get_height() == 24, "orb has the requested size")
	var rare: Image = CosmicTheme.orb_icon(Color.RED, 3, 24).get_image()
	var plain: Image = a.get_image()
	check(rare.get_pixel(2, 12).a > plain.get_pixel(2, 12).a, "rare orbs carry a visible aura halo")


func test_affinity_tags_and_journey() -> void:
	var r: RecipeData = RecipeData.new()
	r.condition_traits = PackedStringArray(["temperature_c", "glow", "glow", "fraction:water"])
	r.condition_min = PackedFloat32Array([60.0, 0.5, 0.5, 0.3])
	r.condition_max = PackedFloat32Array([1e9, 1e9, 1e9, 1e9])
	var tags: Array[Array] = GrimoireBookUI._affinity_tags(r)
	var names: PackedStringArray = PackedStringArray()
	for t: Array in tags:
		names.append(String(t[0]))
	check("♨ Heat" in names and "✺ Glow" in names, "heat and glow tags come from the signature: %s" % ", ".join(names))
	check(names.size() == 3, "duplicate traits give one tag each")
	var sapphire: MineralData = Rock3D.get_mineral("sapphire")
	if sapphire != null:
		var steps: Array[Array] = GrimoireBookUI._journey(sapphire)
		check(String(steps[steps.size() - 1][0]).begins_with("Cut") == sapphire.can_facet, "facetable gems end the journey cut")
	var granite: MineralData = Rock3D.get_mineral("granite")
	if granite != null:
		var g: Array[Array] = GrimoireBookUI._journey(granite)
		check(String(g[0][0]) == "Rock Crate" and String(g[g.size() - 1][0]).length() > 3, "rocks journey from the crate to their crushed minerals")


func test_seen_pages_round_trip() -> void:
	var j: GrimoireJournal = GrimoireJournal.new()
	j.persist = false
	check(not j.is_seen("recipe:x"), "nothing is seen at first")
	j.mark_seen("recipe:x")
	check(j.is_seen("recipe:x"), "marking a page seen sticks")
	j.free()
