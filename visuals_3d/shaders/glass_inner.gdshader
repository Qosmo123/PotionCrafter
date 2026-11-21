// Inner/far wall of a glass vessel (back faces). Shared by PC and mobile tiers:
// no screen texture, only a faint Fresnel sheen and thickness edge, so the far
// wall reads through the near wall without adding heavy overdraw.
shader_type spatial;
render_mode blend_mix, cull_front, depth_draw_never, specular_schlick_ggx;

uniform vec3 edge_tint : source_color = vec3(0.55, 0.85, 0.78);
uniform float strength : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec3 n = -NORMAL;
	float n_dot_v = clamp(abs(dot(n, VIEW)), 0.001, 1.0);
	float fresnel = 0.036 + 0.964 * pow(1.0 - n_dot_v, 5.0);
	NORMAL = n;
	ALBEDO = edge_tint * 0.05;
	ALPHA = clamp((0.02 + fresnel * 0.6 + (1.0 - n_dot_v) * 0.08) * strength, 0.0, 0.6);
	ROUGHNESS = 0.07;  // softer pin-point light glints
	SPECULAR = 0.6;
}
