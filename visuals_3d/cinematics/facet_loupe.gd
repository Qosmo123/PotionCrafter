class_name FacetLoupe
extends CanvasLayer
## Close-up inset while a stone is on the polisher or faceting lap: a second
## camera sits a few centimetres from the stone, looking down at it on the
## spinning lap with a shallow depth of field, and is shown in a round
## jeweller's loupe with a progress arc. The player keeps their normal view
## (and hand control); the loupe only renders while it is showing.

const SHADER: Shader = preload("res://visuals_3d/shaders/loupe.gdshader")
const SIZE_PX: int = 460

var _viewport: SubViewport
var _cam: Camera3D
var _rect: TextureRect
var _mat: ShaderMaterial
var _title: Label
var _caption_bg: Panel
var _detail: Label
var _alpha: float = 0.0
var _target: Node3D = null
var _orbit: float = 0.0


func _ready() -> void:
	layer = 40
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE_PX, SIZE_PX)
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_viewport.world_3d = get_viewport().world_3d
	_cam = Camera3D.new()
	_cam.fov = 22.0
	_cam.near = 0.004
	_cam.far = 6.0
	var attrs: CameraAttributesPractical = CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 0.16
	attrs.dof_blur_far_transition = 0.18
	attrs.dof_blur_amount = 0.12
	_cam.attributes = attrs
	_viewport.add_child(_cam)
	_cam.current = true
	_rect = TextureRect.new()
	_rect.texture = _viewport.get_texture()
	_rect.custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	_rect.size = Vector2(SIZE_PX, SIZE_PX)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	add_child(_rect)
	_caption_bg = Panel.new()
	_caption_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_bg.add_theme_stylebox_override(&"panel", CosmicTheme.flat(Color(0.05, 0.035, 0.08, 0.82), Color(CosmicTheme.STARLIGHT_GOLD, 0.45), 1, 10))
	add_child(_caption_bg)
	_title = CosmicTheme.label("", 20, Color(0.98, 0.93, 0.8), CosmicTheme.display_font())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_detail = CosmicTheme.label("", 15, Color(0.85, 0.82, 0.92))
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)
	_apply_alpha()


## Show the loupe on `stone` this frame (call every frame while working).
## `progress` 0..1 fills the arc; `steadiness` 0..1 tints it green..pink.
func show_on(stone: Node3D, progress: float, steadiness: float, title: String, detail: String) -> void:
	_target = stone
	_mat.set_shader_parameter(&"progress", clampf(progress, 0.0, 1.0))
	var col: Color = CosmicTheme.SUCCESS.lerp(CosmicTheme.WARNING, clampf((0.85 - steadiness) * 3.0, 0.0, 1.0))
	col = col.lerp(CosmicTheme.PRISM_PINK, clampf((0.5 - steadiness) * 3.0, 0.0, 1.0))
	_mat.set_shader_parameter(&"arc_color", col)
	_title.text = title
	_detail.text = detail


func hide_loupe() -> void:
	_target = null


func is_showing() -> bool:
	return _alpha > 0.01


func _process(delta: float) -> void:
	var want: bool = _target != null and is_instance_valid(_target) and _target.is_inside_tree()
	_alpha = move_toward(_alpha, 1.0 if want else 0.0, delta * (4.0 if want else 3.0))
	_apply_alpha()
	if _alpha <= 0.0:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if want:
		# Close and a little above, drifting slowly round so facets glint.
		_orbit += delta * 0.35
		var c: Vector3 = _target.global_position
		var main: Camera3D = get_viewport().get_camera_3d()
		var toward: Vector3 = Vector3(0.0, 0.0, 1.0)
		if main != null:
			toward = main.global_position - c
			toward.y = 0.0
			toward = toward.normalized() if toward.length() > 1e-3 else Vector3(0.0, 0.0, 1.0)
		var side: Vector3 = toward.cross(Vector3.UP).normalized()
		var dir: Vector3 = (toward + side * 0.45 * sin(_orbit)).normalized()
		_cam.global_position = c + dir * 0.085 + Vector3(0.0, 0.055, 0.0)
		_cam.look_at(c, Vector3.UP)
		(_cam.attributes as CameraAttributesPractical).dof_blur_far_distance = _cam.global_position.distance_to(c) + 0.03
	# Lay out: upper right, clear of the top bar and toasts.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var scale_k: float = clampf(vp.y / 1080.0, 0.6, 1.4)
	var d: float = float(SIZE_PX) * scale_k
	_rect.size = Vector2(d, d)
	_rect.position = Vector2(vp.x - d - 40.0 * scale_k, 90.0 * scale_k)
	_title.position = Vector2(_rect.position.x, _rect.position.y + d + 4.0)
	_title.size = Vector2(d, 28.0)
	_detail.position = Vector2(_rect.position.x, _rect.position.y + d + 32.0 * scale_k)
	_detail.size = Vector2(d, 22.0)
	_caption_bg.position = Vector2(_rect.position.x + d * 0.06, _title.position.y - 4.0)
	_caption_bg.size = Vector2(d * 0.88, 32.0 * scale_k + 30.0)


func _apply_alpha() -> void:
	_mat.set_shader_parameter(&"alpha", _alpha)
	_title.modulate.a = _alpha
	_detail.modulate.a = _alpha
	_caption_bg.modulate.a = _alpha
	_rect.visible = _alpha > 0.0
