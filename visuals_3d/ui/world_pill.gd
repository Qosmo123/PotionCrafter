class_name WorldPill
extends Label3D
## A machine's caption in the world, drawn as a small dark glass pill with a
## thin gold edge so it reads over light shafts and brickwork. It isn't on
## all the time: it shows while the machine is in use (`busy` returns true)
## and for a few seconds after its text changes (a knob turned, a stone
## loaded), then fades away. The hover label covers idle machines.
## With auto_hide off the owner shows and hides it itself.

const SHADER: Shader = preload("res://visuals_3d/shaders/world_pill.gdshader")
const SHOW_SECONDS: float = 4.0
const PAD_PX: Vector2 = Vector2(26.0, 14.0)

## Optional: returns true while the owning machine is in use.
var busy: Callable = Callable()
var auto_hide: bool = true

var _backing: MeshInstance3D
var _quad: QuadMesh
var _last_text: String = ""
var _since_change_s: float = 1e9
var _alpha: float = 0.0


## A pill under `parent` at `at` (local), set up like the old captions.
static func make(parent: Node3D, at: Vector3, font_size_px: int = 26, pixel: float = 0.00042) -> WorldPill:
	var pill: WorldPill = WorldPill.new()
	pill.font_size = font_size_px
	pill.pixel_size = pixel
	pill.position = at
	parent.add_child(pill)
	return pill


func _ready() -> void:
	font = CosmicTheme.world_font()
	outline_size = 0
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	modulate = Color(0.96, 0.92, 0.84)
	render_priority = 2
	no_depth_test = false
	_quad = QuadMesh.new()
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = 1
	_quad.material = mat
	_backing = MeshInstance3D.new()
	_backing.mesh = _quad
	_backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_backing)
	_last_text = text
	_resize()


func _process(delta: float) -> void:
	if text != _last_text:
		# The first text a machine sets up is its idle caption: no flash.
		if _last_text != "":
			_since_change_s = 0.0
		_last_text = text
		_resize.call_deferred()
	_since_change_s += delta
	if not auto_hide:
		# The owner shows and hides it; just keep it fully opaque.
		if _alpha != 1.0:
			_alpha = 1.0
			modulate.a = 1.0
			(_quad.material as ShaderMaterial).set_shader_parameter(&"alpha", 1.0)
		return
	var want: bool = _since_change_s < SHOW_SECONDS or (busy.is_valid() and bool(busy.call()))
	_set_alpha(move_toward(_alpha, 1.0 if want else 0.0, delta * (6.0 if want else 2.5)))


func _set_alpha(a: float) -> void:
	if a == _alpha and visible == (a > 0.0):
		return
	_alpha = a
	visible = a > 0.0
	modulate.a = a
	(_quad.material as ShaderMaterial).set_shader_parameter(&"alpha", a)


## Fit the backing to the text.
func _resize() -> void:
	if _quad == null:
		return
	# Measure the text with the font (the label's own AABB lags a frame).
	var f: Font = font if font != null else CosmicTheme.world_font()
	var text_px: Vector2 = f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width if autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0, font_size)
	if text_px.x <= 0.0:
		text_px = Vector2(80.0, float(font_size))
	# Height from the line count: Label3D spaces lines a little wider.
	var lines: int = text.count("\n") + 1
	text_px.y = maxf(text_px.y, float(lines) * (f.get_height(font_size) * 1.18 + line_spacing))
	_quad.size = (text_px + PAD_PX) * pixel_size
	(_quad.material as ShaderMaterial).set_shader_parameter(&"size_px", text_px + PAD_PX)
	_backing.position = Vector3(0.0, 0.0, -0.0005)
