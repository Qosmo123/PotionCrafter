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
	// Crisp silhouette (dark edge + inner line) and a vertical studio streak.
	float rim = smoothstep(0.34, 0.05, n_dot_v);
	float rim_line = exp(-pow((n_dot_v - 0.19) / 0.035, 2.0));
	float streak = smoothstep(0.1, 0.0, abs(NORMAL.x - 0.52)) * smoothstep(-0.6, 0.2, NORMAL.y);
	ALBEDO = edge_tint * 0.08 * (1.0 - rim * 0.7);
	EMISSION = vec3(rim_line * 0.1 + streak * 0.16);
	ALPHA = clamp(0.04 + edge * 3.0 + fresnel * 0.9 + rim * 0.25 + streak * 0.25, 0.0, 0.95);
	ROUGHNESS = glass_roughness;
	METALLIC = 0.0;
	SPECULAR = 0.5 + fresnel * 0.5;
}
