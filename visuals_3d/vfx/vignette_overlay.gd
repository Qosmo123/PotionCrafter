class_name VignetteOverlay
extends CanvasLayer
## Gentle warm vignette over the 3D view (drawn under every HUD layer):
## darkens and slightly warms the screen edges to frame the bench.

@export var strength: float = 0.42
@export var tint: Color = Color(0.12, 0.06, 0.02)

const SHADER_CODE: String = """
shader_type canvas_item;
uniform float strength = 0.42;
uniform vec3 tint : source_color = vec3(0.12, 0.06, 0.02);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x *= 0.85;
	float v = smoothstep(0.55, 1.45, length(p));
	COLOR = vec4(tint, v * strength);
}
"""


func _ready() -> void:
	layer = -1
	var rect: ColorRect = ColorRect.new()
	rect.name = "Vignette"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = Shader.new()
	shader.code = SHADER_CODE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"strength", strength)
	mat.set_shader_parameter(&"tint", tint)
	rect.material = mat
	add_child(rect)
