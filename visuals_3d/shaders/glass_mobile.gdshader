// Android tier (Vulkan Mobile) glass: NO screen-texture grab (avoids tile flushes
// on Mali/Adreno). Single-pass alpha-blended Schlick Fresnel from the real IOR,
// wall-thickness edge tint, and reflections from the scene ReflectionProbe/sky.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;

uniform vec3 edge_tint : source_color = vec3(0.55, 0.85, 0.78);
uniform float ior = 1.47;
uniform float wall_thickness_meters = 0.0022;
uniform float absorption_per_meter = 55.0;
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.06;

void fragment() {
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.001, 1.0);
	float f0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
	float fresnel = f0 + (1.0 - f0) * pow(1.0 - n_dot_v, 5.0);
	float path_m = wall_thickness_meters / max(n_dot_v, 0.08);
	float edge = 1.0 - exp(-(1.0 - edge_tint.g) * absorption_per_meter * path_m);
	ALBEDO = edge_tint * 0.08;
	ALPHA = clamp(0.04 + edge * 3.0 + fresnel * 0.9, 0.0, 0.95);
	ROUGHNESS = glass_roughness;
	METALLIC = 0.0;
	SPECULAR = 0.5 + fresnel * 0.5;
}
