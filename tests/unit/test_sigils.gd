extends "res://tests/unit/unit_test_base.gd"
## Geometric sigil recogniser: shapes are classified by measured geometry.

func _polygon(sides: int, radius: float, points_per_side: int, jitter: float = 0.0) -> PackedVector2Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99 + sides
	var pts: PackedVector2Array = PackedVector2Array()
	for s: int in sides:
		var a0: float = TAU * float(s) / float(sides) + 0.3
		var a1: float = TAU * float(s + 1) / float(sides) + 0.3
		var p0: Vector2 = Vector2(cos(a0), sin(a0)) * radius
		var p1: Vector2 = Vector2(cos(a1), sin(a1)) * radius
		for k: int in points_per_side:
			pts.append(p0.lerp(p1, float(k) / float(points_per_side)) + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter)))
	pts.append(pts[0])
	return pts


func _circle(radius: float, count: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in count + 1:
		var a: float = TAU * float(i) / float(count)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func test_circle_is_a_warding_circle() -> void:
	var r: SigilRecognizer.Result = SigilRecognizer.analyze(_circle(0.07, 120))
	check(r.kind == SigilRecognizer.Kind.CIRCLE, "circle recognised (got %s)" % r.describe())
	check(r.power > 0.8, "clean circle is powerful")


func test_polygons_by_vertex_count() -> void:
	var expected: Dictionary = {3: SigilRecognizer.Kind.TRIANGLE, 4: SigilRecognizer.Kind.SQUARE, 5: SigilRecognizer.Kind.PENTAGON, 6: SigilRecognizer.Kind.HEXAGON, 8: SigilRecognizer.Kind.OCTAGON}
	for sides: int in expected:
		var r: SigilRecognizer.Result = SigilRecognizer.analyze(_polygon(sides, 0.08, 20, 0.0008))
		check(r.kind == expected[sides], "%d-gon recognised (got %s)" % [sides, r.describe()])


func test_open_stroke_is_not_a_sigil() -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 50:
		pts.append(Vector2(float(i) * 0.004, sin(float(i) * 0.3) * 0.01))
	var r: SigilRecognizer.Result = SigilRecognizer.analyze(pts)
	check(r.kind == SigilRecognizer.Kind.NONE, "open scribble does nothing")


func test_sloppy_sigils_are_weaker() -> void:
	var clean: SigilRecognizer.Result = SigilRecognizer.analyze(_polygon(3, 0.08, 20, 0.0))
	var sloppy_pts: PackedVector2Array = _polygon(3, 0.08, 20, 0.0)
	sloppy_pts[sloppy_pts.size() - 1] = sloppy_pts[0] + Vector2(0.03, 0.0)
	var sloppy: SigilRecognizer.Result = SigilRecognizer.analyze(sloppy_pts)
	check(sloppy.power < clean.power, "an unclosed triangle is weaker (%.2f vs %.2f)" % [sloppy.power, clean.power])
