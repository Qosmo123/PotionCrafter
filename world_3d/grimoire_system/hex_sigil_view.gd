class_name HexSigilView
extends Control
## Deterministic alchemical hex-sigil drawn from a seed (GrimoireJournal.sigil_seed).
## Same seed -> same glyph on every platform, so players can share them.

@export var ink: Color = Color(0.28, 0.16, 0.07)

var seed_text: String = ""


func set_seed(text: String) -> void:
	seed_text = text
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.5 - 8.0)
	var r: float = minf(size.x, size.y - 20.0) * 0.42
	if seed_text == "":
		draw_arc(center, r, 0.0, TAU, 48, Color(ink, 0.3), 1.0, true)
		draw_string(font, center - Vector2(8.0, -6.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(ink, 0.4))
		return
	var bytes: PackedByteArray = seed_text.replace("-", "").hex_decode()
	while bytes.size() < 6:
		bytes.append(0)
	var hue: float = float(bytes[3]) / 255.0
	var accent: Color = Color.from_hsv(hue, 0.65, 0.55)
	draw_arc(center, r, 0.0, TAU, 64, ink, 2.0, true)
	draw_arc(center, r * 0.86, 0.0, TAU, 64, Color(ink, 0.6), 1.0, true)
	# Rim ticks: one per bit of byte 4/5.
	for i: int in 16:
		var on: bool = ((int(bytes[4]) << 8 | int(bytes[5])) >> i) & 1 == 1
		var a: float = TAU * float(i) / 16.0
		var d: Vector2 = Vector2(cos(a), sin(a))
		draw_line(center + d * r * 0.86, center + d * r * (0.98 if on else 0.92), ink, 2.0 if on else 1.0, true)
	# Polygon and star.
	var n: int = 3 + int(bytes[0]) % 6
	var step: int = 1 + int(bytes[1]) % maxi(n / 2, 1)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		var a: float = TAU * float(i) / float(n) - PI * 0.5
		pts.append(center + Vector2(cos(a), sin(a)) * r * 0.72)
	for i: int in n:
		draw_line(pts[i], pts[(i + 1) % n], ink, 1.5, true)
		draw_line(pts[i], pts[(i + step) % n], accent, 1.5, true)
	# Satellites.
	var moons: int = 1 + int(bytes[2]) % 5
	for i: int in moons:
		var a: float = TAU * float(i) / float(moons) + float(bytes[2]) * 0.05
		draw_arc(center + Vector2(cos(a), sin(a)) * r * 0.36, r * 0.08, 0.0, TAU, 20, accent, 1.5, true)
	draw_circle(center, r * 0.06, ink)
	var w: float = font.get_string_size(seed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(size.x * 0.5 - w * 0.5, size.y - 4.0), seed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
