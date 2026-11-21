// Backing for in-world captions (WorldPill): a dark translucent rounded
// rectangle with a thin muted-gold edge, always facing the camera.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec2 size_px = vec2(200.0, 60.0);
uniform float alpha = 1.0;
uniform vec4 fill : source_color = vec4(0.063, 0.055, 0.11, 0.88);
uniform vec4 edge : source_color = vec4(0.784, 0.643, 0.365, 0.85);
uniform float radius_px = 14.0;
uniform float edge_px = 1.6;

void vertex() {
	// Billboard: keep the quad's size, turn it to face the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * size_px;
	float d = rounded_box(p, size_px * 0.5 - vec2(1.0), radius_px);
	float inside = 1.0 - smoothstep(-0.8, 0.8, d);
	float ring = 1.0 - smoothstep(edge_px - 0.8, edge_px + 0.8, abs(d + edge_px * 0.5));
	vec3 col = mix(fill.rgb, edge.rgb, ring * edge.a);
	ALBEDO = col;
	ALPHA = clamp(max(inside * fill.a, ring * edge.a), 0.0, 1.0) * alpha;
}
