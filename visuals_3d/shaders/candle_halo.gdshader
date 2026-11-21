// Soft warm glow around a candle flame: a camera-facing additive disc with
// a hot core and a wide, faint falloff. Strength flickers with the flame.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 glow_color : source_color = vec3(1.0, 0.62, 0.28);
instance uniform float strength = 1.0;

void vertex() {
	// Billboard (works for orthographic and perspective cameras).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = exp(-r * r * 30.0);
	float wide = exp(-r * r * 5.0) * (1.0 - smoothstep(0.7, 1.0, r));
	ALBEDO = glow_color * (core * 0.9 + wide * 0.35) * strength;
}
