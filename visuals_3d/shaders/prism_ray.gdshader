// One coloured ray of light for the faceting station's prism fan. Per-ray
// colour and strength are instance uniforms, so all rays share one material
// and updating them each frame allocates nothing. Additive, mobile-safe.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float strength = 0.0;

void fragment() {
	// QuadMesh: UV.x across the ray, UV.y along it (fades toward the tip).
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(1.0, 0.15, UV.y) * smoothstep(0.0, 0.05, UV.y);
	float shimmer = 0.85 + 0.15 * sin(TIME * 11.0 + UV.y * 25.0);
	ALBEDO = tint.rgb * pow(across, 2.0) * along * strength * 2.4 * shimmer;
}
