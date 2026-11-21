@tool
class_name CosmicStyleBox
extends StyleBox
## Dark translucent "glass" panel with a thin starlight-gold border, an optional
## coloured glow halo and celestial filigree: corner brackets with tiny
## four-point stars joined by faint constellation lines. Pure vector draws
## (no textures), so it scales cleanly to any resolution and costs a handful
## of canvas commands per panel.

@export var bg_color: Color = CosmicTheme.GLASS:
	set(v):
		bg_color = v
		_dirty = true
@export var border_color: Color = Color(CosmicTheme.STARLIGHT_GOLD, 0.55):
	set(v):
		border_color = v
		_dirty = true
@export var border_width: int = 1:
	set(v):
		border_width = v
		_dirty = true
@export var corner_radius: int = CosmicTheme.RADIUS:
	set(v):
		corner_radius = v
		_dirty = true
@export var glow_color: Color = Color(0, 0, 0, 0):
	set(v):
		glow_color = v
		_dirty = true
@export var glow_size: int = 0:
	set(v):
		glow_size = v
		_dirty = true
## 0 = none, 1 = corner brackets, 2 = brackets + constellation stars.
@export_range(0, 2) var filigree: int = 2
@export var filigree_color: Color = CosmicTheme.STARLIGHT_GOLD

var _flat: StyleBoxFlat = StyleBoxFlat.new()
var _dirty: bool = true


func _sync() -> void:
	_flat.bg_color = bg_color
	_flat.border_color = border_color
	_flat.set_border_width_all(border_width)
	_flat.set_corner_radius_all(corner_radius)
	_flat.shadow_color = glow_color
	_flat.shadow_size = glow_size
	_flat.anti_aliasing = true
	_dirty = false


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow(float(glow_size))


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if _dirty:
		_sync()
	_flat.draw(to_canvas_item, rect)
	if filigree <= 0 or rect.size.x < 40.0 or rect.size.y < 30.0:
		return
	# Kept within ~22 px of the edge so it lives in the content margin, never over text.
	var inset: float = 3.0 + float(corner_radius) * 0.2
	var arm: float = clampf(minf(rect.size.x, rect.size.y) * 0.12, 8.0, 20.0)
	var line_col: Color = Color(filigree_color, 0.75)
	var faint: Color = Color(filigree_color, 0.28)
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var dirs: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for i: int in 4:
		var d: Vector2 = dirs[i]
		var p: Vector2 = corners[i] + d * inset
		# L-shaped bracket with a small diamond at the elbow.
		RenderingServer.canvas_item_add_line(to_canvas_item, p, p + Vector2(d.x * arm, 0.0), line_col, 1.0, true)
		RenderingServer.canvas_item_add_line(to_canvas_item, p, p + Vector2(0.0, d.y * arm), line_col, 1.0, true)
		_diamond(to_canvas_item, p, 2.2, filigree_color)
		if filigree >= 2 and minf(rect.size.x, rect.size.y) > 70.0:
			# A three-star constellation tucked into the corner.
			var s1: Vector2 = p + Vector2(d.x * arm * 0.5, d.y * arm * 0.38)
			var s2: Vector2 = p + Vector2(d.x * arm * 1.15, d.y * arm * 0.55)
			var s3: Vector2 = p + Vector2(d.x * arm * 0.38, d.y * arm * 1.0)
			RenderingServer.canvas_item_add_line(to_canvas_item, s1, s2, faint, 1.0, true)
			RenderingServer.canvas_item_add_line(to_canvas_item, s1, s3, faint, 1.0, true)
			_star(to_canvas_item, s1, 3.0, filigree_color)
			_star(to_canvas_item, s2, 2.0, Color(filigree_color, 0.8))
			_star(to_canvas_item, s3, 1.6, Color(filigree_color, 0.65))
	if filigree >= 2 and rect.size.x > 160.0:
		# Centre crest on the top edge.
		var top: Vector2 = Vector2(rect.get_center().x, rect.position.y + inset * 0.6)
		RenderingServer.canvas_item_add_line(to_canvas_item, top - Vector2(arm * 1.4, 0.0), top - Vector2(5.0, 0.0), faint, 1.0, true)
		RenderingServer.canvas_item_add_line(to_canvas_item, top + Vector2(5.0, 0.0), top + Vector2(arm * 1.4, 0.0), faint, 1.0, true)
		_diamond(to_canvas_item, top, 3.0, filigree_color)


static func _star(ci: RID, c: Vector2, r: float, col: Color) -> void:
	RenderingServer.canvas_item_add_line(ci, c - Vector2(r, 0.0), c + Vector2(r, 0.0), col, 1.0, true)
	RenderingServer.canvas_item_add_line(ci, c - Vector2(0.0, r), c + Vector2(0.0, r), col, 1.0, true)
	RenderingServer.canvas_item_add_circle(ci, c, maxf(r * 0.32, 0.8), col)


static func _diamond(ci: RID, c: Vector2, r: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([col, col, col, col]))
