class_name RadarChart
extends Control
## Property radar ("spider") chart drawn in ink on parchment.

@export var ink: Color = Color(0.28, 0.16, 0.07)
@export var fill: Color = Color(0.62, 0.22, 0.12, 0.35)

var axes: PackedStringArray = GrimoireJournal.RADAR_AXES
var values: PackedFloat32Array = PackedFloat32Array()


func set_values(new_values: PackedFloat32Array, new_fill: Color = Color(0.62, 0.22, 0.12, 0.35)) -> void:
	values = new_values
	fill = new_fill
	queue_redraw()


func _draw() -> void:
	var n: int = axes.size()
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.34
	var font: Font = ThemeDB.fallback_font
	for ring: int in range(1, 5):
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in n + 1:
			pts.append(center + _dir(i, n) * radius * float(ring) / 4.0)
		draw_polyline(pts, Color(ink, 0.25), 1.0, true)
	for i: int in n:
		draw_line(center, center + _dir(i, n) * radius, Color(ink, 0.35), 1.0, true)
		var label_pos: Vector2 = center + _dir(i, n) * (radius + 16.0)
		var text_w: float = font.get_string_size(axes[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, label_pos - Vector2(text_w * 0.5, -4.0), axes[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
	if values.size() < n:
		draw_string(font, center - Vector2(70.0, 0.0), "no measurements", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(ink, 0.6))
		return
	var poly: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		poly.append(center + _dir(i, n) * radius * clampf(values[i], 0.03, 1.0))
	draw_colored_polygon(poly, fill)
	poly.append(poly[0])
	draw_polyline(poly, ink, 2.0, true)
	for i: int in n:
		draw_circle(poly[i], 2.5, ink)


func _dir(i: int, n: int) -> Vector2:
	var a: float = TAU * float(i) / float(n) - PI * 0.5
	return Vector2(cos(a), sin(a))
