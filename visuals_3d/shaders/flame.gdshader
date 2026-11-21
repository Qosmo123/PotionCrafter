// A small open flame on a quad that turns round its vertical axis to face
// the camera. Teardrop shape with a flickering, licking outline; a blue core
// at the wick, an orange-yellow body and a fading tip. Unlit, alpha blended
// (additive washes out against the warm bench).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity = 1.0;
uniform float seed = 0.0;

varying float y_v;

float wave(float t) {
	return sin(t) * 0.5 + sin(t * 2.3 + 1.7) * 0.3 + sin(t * 5.1 + 0.4) * 0.2;
}

void vertex() {
	// Face the camera round Y only, so the flame stays upright.
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	to_cam.y = 0.0;
	vec3 fwd = length(to_cam) > 1e-4 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + right * VERTEX.x * scale.x + vec3(0.0, VERTEX.y * scale.y, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	y_v = UV.y;
}

void fragment() {
	float y = 1.0 - UV.y;          // 0 at the wick, 1 at the tip
	float x = UV.x * 2.0 - 1.0;
	float t = TIME + seed;
	// The outline licks sideways more toward the tip.
	x += wave(t * 9.0 + y * 6.0) * 0.18 * y * y;
	float half_w = 0.92 * pow(max(1.0 - y, 0.0), 0.6) * smoothstep(0.0, 0.3, y + 0.1);
	half_w *= 1.0 + wave(t * 13.0 + y * 3.0) * 0.08;
	float d = abs(x) / max(half_w, 1e-3);
	float body = 1.0 - smoothstep(0.55, 1.0, d);
	// Brighter inside, dimmer toward the tip.
	float heat = (1.0 - d * 0.6) * (1.0 - smoothstep(0.55, 1.0, y));
	vec3 outer = mix(vec3(1.0, 0.36, 0.05), vec3(1.0, 0.72, 0.26), heat * 0.75);
	// Blue core low down.
	float core = (1.0 - smoothstep(0.0, 0.6, d)) * (1.0 - smoothstep(0.1, 0.45, y));
	vec3 col = mix(outer, vec3(0.25, 0.45, 1.0), core * 0.9);
	ALBEDO = col * intensity * 1.25;
	ALPHA = clamp(body * (0.55 + 0.45 * heat + core * 0.3), 0.0, 1.0) * (1.0 - smoothstep(0.75, 1.0, y));
}
