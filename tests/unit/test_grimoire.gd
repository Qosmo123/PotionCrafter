extends "res://tests/unit/unit_test_base.gd"
## Grimoire helpers: sigils, grades, radar values, plain-language notes.


func test_sigil_seed_is_deterministic_and_formatted() -> void:
	var v: PackedFloat32Array = PackedFloat32Array([0.1, 0.5, 0.9, 0.0, 1.0, 0.3, 0.2, 0.7])
	var a: String = GrimoireJournal.sigil_seed(v)
	check(a == GrimoireJournal.sigil_seed(v), "same traits give the same sigil")
	check(a.length() == 14 and a[4] == "-" and a[9] == "-", "seed format XXXX-XXXX-XXXX (got %s)" % a)
	v[2] = 0.1
	check(a != GrimoireJournal.sigil_seed(v), "different traits give a different sigil")


func test_grade_ordering() -> void:
	check(GrimoireJournal.grade_at_least("S", "B"), "S beats B")
	check(GrimoireJournal.grade_at_least("B", "B"), "B meets B")
	check(not GrimoireJournal.grade_at_least("C", "B"), "C misses B")


func test_radar_values_are_normalised() -> void:
	var m: MixtureContainer = MixtureContainer.new()
	m.add_substance(SubstanceRegistry.index_of_id(&"moonwater"), 5.0, 330.0)
	var values: PackedFloat32Array = GrimoireJournal.radar_values(RecipeBook.measure_mixture(m, 0.0, false))
	check(values.size() == GrimoireJournal.RADAR_AXES.size(), "one value per axis")
	for f: float in values:
		check(f >= 0.0 and f <= 1.0, "radar value in 0..1 (got %s)" % str(f))
	check(values[4] > 0.5, "moonwater reads as buoyant")


func test_every_substance_has_notes_and_a_group() -> void:
	for i: int in SubstanceRegistry.count():
		var s: SubstanceData = SubstanceRegistry.get_substance(i)
		check(GrimoireBookUI.behaviour_notes(s).size() > 0, "%s has behaviour notes" % s.substance_id)
		check(GrimoireBookUI.substance_group(s) != "", "%s has a codex group" % s.substance_id)
