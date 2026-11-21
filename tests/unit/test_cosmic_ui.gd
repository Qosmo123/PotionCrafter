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


func _store() -> InventoryStore:
	var store: InventoryStore = InventoryStore.new()
	store._build_catalog()
	return store


func test_gather_matches_ingredients_by_longest_name() -> void:
	var store: InventoryStore = _store()
	var moon: String = store.match_ingredient("Moonwater")
	check(moon != "" and String(store.find_item(moon)["label"]).to_lower().contains("moon"), "Moonwater beats plain Water (%s)" % moon)
	check(store.match_ingredient("Heat") == "", "heat is not a shelf item")
	check(store.match_ingredient("A stirrer") == "", "tools are not gathered as ingredients")
	store.free()


func test_item_card_shows_hazards_and_rarity() -> void:
	var store: InventoryStore = _store()
	var acid: Dictionary = store.find_item("chem:sulfuric_acid")
	check(not acid.is_empty(), "sulfuric acid is on a shelf")
	var card: Control = SatchelItemButton.build_card(acid)
	var text: String = _all_text(card)
	check(text.contains("DANGER") and text.contains("Corrosive"), "acid card warns DANGER: corrosive")
	check(text.contains("Shift-click"), "card teaches the quick gestures")
	card.free()
	var water_card: Control = SatchelItemButton.build_card(store.find_item("chem:acetone") if not store.find_item("chem:acetone").is_empty() else acid)
	check(_all_text(water_card).contains("boils"), "card lists physical properties")
	water_card.free()
	store.free()


func _all_text(n: Node) -> String:
	var out: String = ""
	if n is Label:
		out += (n as Label).text + "\n"
	for c: Node in n.get_children():
		out += _all_text(c)
	return out


func test_pinned_recipe_toggles() -> void:
	var j: GrimoireJournal = GrimoireJournal.new()
	j.persist = false
	j.pin("levitation")
	check(j.pinned_recipe == "levitation", "pinning remembers the recipe")
	j.pin("levitation")
	check(j.pinned_recipe == "", "pinning the same recipe again unpins it")
	j.free()


func test_anvil_toss_lands_on_target() -> void:
	var from: Vector3 = Vector3(2.5, 0.85, 0.3)
	var target: Vector3 = Vector3(3.2, 0.95, 0.22)
	var v: Vector3 = AnvilLoader.toss_velocity(from, target)
	var t: float = AnvilLoader.FLIGHT_SECONDS
	var g: float = SimConstants.GRAVITY_M_S2
	var landing: Vector3 = from + v * t + Vector3(0.0, -0.5 * g * t * t, 0.0)
	check(landing.distance_to(target) < 1e-3, "ballistic toss lands on the anvil (off by %.4f m)" % landing.distance_to(target))
	check(v.y > 0.0, "the rock is lobbed upward in an arc")


func test_hammer_charge_builds_and_releases() -> void:
	var h: Hammer3D = Hammer3D.new()
	h.begin_charge()
	for i: int in 30:
		h._physics_process(1.0 / 60.0)
	check(h.charging and h.charge > 0.5 and h.charge < 0.7, "half a second of holding winds up ~60%% (%.2f)" % h.charge)
	var hover_charged: float = h.get_hover_override_y()
	check(hover_charged > h.bench_top_y + 0.25, "winding up lifts the hammer higher")
	h.release_charge()
	check(not h.charging and h.get_hover_override_y() < hover_charged, "releasing swings it down to the bench")
	h.free()
