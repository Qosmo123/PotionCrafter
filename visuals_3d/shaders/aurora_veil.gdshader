// Aurora veil: a slow curtain of coloured light hanging in front of the lab
// wall. One additive quad per station; fades out at its edges and bottom.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec3 color_low : source_color = vec3(0.2, 0.9, 0.8);
uniform vec3 color_mid : source_color = vec3(0.55, 0.35, 1.0);
uniform vec3 color_high : source_color = vec3(1.0, 0.45, 0.8);
uniform float strength = 0.5;
uniform float speed = 0.05;
uniform float seed = 0.0;

float hash11(float x) {
	return fract(sin(x * 127.1 + seed * 31.7) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash11(i), hash11(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	float t = TIME * speed;
	// The curtain's lower hem waves; rays stream upward from it.
	float sway = (noise1(UV.x * 3.0 + t) - 0.5) * 0.25 + (noise1(UV.x * 9.0 - t * 1.7) - 0.5) * 0.08;
	float h = 1.0 - UV.y + sway;  // 0 at the bottom, 1 at the top
	float rays = 0.55 * noise1(UV.x * 26.0 + t * 2.0 + sway * 6.0) + 0.45 * noise1(UV.x * 61.0 - t * 3.0);
	float body = smoothstep(0.18, 0.42, h) * (1.0 - smoothstep(0.55, 1.0, h));
	float hem = smoothstep(0.16, 0.26, h) * (1.0 - smoothstep(0.26, 0.5, h));
	vec3 col = mix(color_low, color_mid, smoothstep(0.25, 0.6, h));
	col = mix(col, color_high, smoothstep(0.6, 0.95, h));
	float sides = smoothstep(0.0, 0.18, UV.x) * (1.0 - smoothstep(0.82, 1.0, UV.x));
	float a = (body * (0.35 + 0.65 * rays) + hem * 0.5) * sides;
	ALBEDO = col * a * strength;
}
