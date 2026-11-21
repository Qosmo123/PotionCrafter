extends "res://tests/unit/unit_test_base.gd"
## Field-guide encyclopedia, gem cuts, cleavage fragments and lapidary rules.


func test_encyclopedia_is_big_and_has_field_guide_data() -> void:
	var all: Dictionary = Rock3D.registry()
	check(all.size() >= 150, "150+ collectibles (got %d)" % all.size())
	var gems: int = 0
	var phenomena: Dictionary = {}
	for id: String in all:
		var m: MineralData = all[id]
		if m.kind == MineralData.Kind.SAND:
			continue
		check(m.crystal_system != "" and m.mineral_class != "", "%s has class and crystal system" % id)
		check(m.localities != "" and m.uses != "" and m.colors_text != "", "%s has localities, uses and colours" % id)
		check(m.hardness_mohs >= 1.0 and m.hardness_mohs <= 10.0, "%s Mohs in 1..10" % id)
		if m.diaphaneity == MineralData.Diaphaneity.TRANSPARENT and m.kind == MineralData.Kind.GEM:
			check(m.refractive_index > 1.3, "%s transparent gem has a refractive index" % id)
		if m.kind == MineralData.Kind.GEM:
			gems += 1
		phenomena[int(m.phenomenon)] = true
	check(gems >= 60, "60+ gemstones (got %d)" % gems)
	check(phenomena.size() >= 9, "most optical phenomena are represented (%d)" % phenomena.size())


func test_rocks_crush_into_their_real_mineral_mix() -> void:
	var granite: MineralData = Rock3D.get_mineral("granite")
	var ids: PackedStringArray = PackedStringArray()
	for p: Resource in granite.crush_products:
		ids.append(String((p as SubstanceData).substance_id))
	check("quartz_sand_fine" in ids and "feldspar_powder" in ids and "mica_flakes" in ids, "granite = quartz + feldspar + mica (%s)" % ", ".join(ids))
	var hematite: MineralData = Rock3D.get_mineral("hematite")
	check(hematite.streak_color.r > hematite.streak_color.g * 2.0, "hematite streaks red")


func test_every_cut_builds_a_closed_outward_mesh() -> void:
	for cut: int in range(1, RockMeshes.CUT_NAMES.size()):
		var mesh: Mesh = RockMeshes.faceted(cut, 0.01)
		var arrays: Array = mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		check(v.size() >= 36, "%s has facets (%d verts)" % [RockMeshes.CUT_NAMES[cut], v.size()])
		var inward: int = 0
		var i: int = 0
		while i < v.size():
			var c: Vector3 = (v[i] + v[i + 1] + v[i + 2]) / 3.0
			if n[i].dot(c - Vector3(0.0, c.y * 0.5 - 0.001, 0.0)) < -1e-6:
				inward += 1
			i += 3
		check(inward <= v.size() / 30, "%s normals face outward (%d inward)" % [RockMeshes.CUT_NAMES[cut], inward])
	check(RockMeshes.CUT_NAMES.size() == RockMeshes.CUT_INFO.size(), "every cut has a description")
	check(RockMeshes.CUT_NAMES.size() >= 21, "20+ cuts")


func test_cleavage_shapes_and_ease() -> void:
	for c: int in 7:
		var mesh: Mesh = RockMeshes.cleavage_fragment(c, 0.01, 3)
		check(mesh.get_surface_count() == 1, "cleavage %d builds a fragment" % c)
	check(Rock3D.cleavage_ease(MineralData.Cleavage.CUBIC) > Rock3D.cleavage_ease(MineralData.Cleavage.NONE), "perfect cleavage splits easier than none")
	var galena: MineralData = Rock3D.get_mineral("galena")
	check(galena.cleavage == MineralData.Cleavage.CUBIC, "galena has cubic cleavage")
	check(Rock3D.break_description(galena, 4).contains("cubes"), "galena breaks into cubes")
	var obsidian: MineralData = Rock3D.get_mineral("volcanic_obsidian")
	check(Rock3D.break_description(obsidian, 2).contains("conchoidal"), "obsidian shows conchoidal fracture")


func test_cabochon_suits_phenomenal_stones() -> void:
	var star: MineralData = Rock3D.get_mineral("star_sapphire")
	check(LapidaryWheel3D.cut_suitability(star, RockMeshes.Cut.CABOCHON) > LapidaryWheel3D.cut_suitability(star, RockMeshes.Cut.ROUND), "star sapphire prefers a cabochon")
	var diamond: MineralData = Rock3D.get_mineral("diamond")
	check(LapidaryWheel3D.cut_suitability(diamond, RockMeshes.Cut.ROUND) >= 0.9, "diamond faceted happily")


func test_specimen_crate_draws_by_rarity() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var common: int = 0
	var legendary: int = 0
	for _i: int in 600:
		var m: MineralData = MineralCrate3D.pick_random(rng, PackedInt32Array([2, 3, 4]))
		check(m != null and m.kind != MineralData.Kind.ROCK, "random specimen is a mineral/gem/fossil")
		if m.rarity == 0:
			common += 1
		elif m.rarity == 4:
			legendary += 1
	check(common > legendary * 4, "commons far outnumber legendaries (%d vs %d)" % [common, legendary])
