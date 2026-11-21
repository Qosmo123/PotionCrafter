class_name CurveChart
extends Control
## Temperature curve (°C over time) inked onto the page.

@export var ink: Color = Color(0.28, 0.16, 0.07)
@export var line: Color = Color(0.7, 0.2, 0.08)
@export var sample_interval_s: float = 0.5

var samples: PackedFloat32Array = PackedFloat32Array()


func set_samples(new_samples: PackedFloat32Array) -> void:
	samples = new_samples
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var rect: Rect2 = Rect2(Vector2(34.0, 8.0), size - Vector2(42.0, 30.0))
	draw_rect(rect, Color(ink, 0.3), false, 1.0)
	draw_string(font, Vector2(4.0, size.y - 6.0), "Thermal curve before discovery", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(ink, 0.8))
	if samples.size() < 2:
		draw_string(font, rect.position + Vector2(10.0, rect.size.y * 0.5), "no record", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(ink, 0.6))
		return
	var lo: float = samples[0]
	var hi: float = samples[0]
	for s: float in samples:
		lo = minf(lo, s)
		hi = maxf(hi, s)
	if hi - lo < 4.0:
		var mid: float = (hi + lo) * 0.5
		lo = mid - 2.0
		hi = mid + 2.0
	draw_string(font, Vector2(2.0, rect.position.y + 10.0), "%d°" % int(round(hi)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
	draw_string(font, Vector2(2.0, rect.end.y), "%d°" % int(round(lo)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in samples.size():
		var x: float = rect.position.x + rect.size.x * float(i) / float(samples.size() - 1)
		var y: float = rect.end.y - rect.size.y * (samples[i] - lo) / (hi - lo)
		pts.append(Vector2(x, y))
	draw_polyline(pts, line, 2.0, true)
	var span_s: float = float(samples.size() - 1) * sample_interval_s
	var span_text: String = "%ds" % int(span_s)
	draw_string(font, Vector2(rect.end.x - font.get_string_size(span_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, size.y - 6.0), span_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(ink, 0.8))
