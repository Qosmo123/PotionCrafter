// Full-screen astral backdrop behind open books and sheets: a slow nebula,
// twinkling star field and drifting stardust motes. Procedural and cheap
// (no textures, no screen reads), so it runs on both PC and mobile tiers.
shader_type canvas_item;

uniform vec4 void_color : source_color = vec4(0.035, 0.039, 0.078, 1.0);
uniform vec4 nebula_a : source_color = vec4(0.29, 0.145, 0.455, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.36, 0.88, 0.9, 1.0);
uniform vec4 star_color : source_color = vec4(0.96, 0.82, 0.44, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.88;
uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform float aspect = 1.7778;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float stars(vec2 uv, float scale, float t, float thresh) {
	vec2 g = uv * scale;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(id);
	if (h < thresh) {
		return 0.0;
	}
	vec2 off = vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5;
	float d = length(f - off * 0.7);
	float tw = 0.55 + 0.45 * sin(t * (1.0 + h * 3.0) + h * 40.0);
	float core = smoothstep(0.06, 0.0, d);
	float cross = smoothstep(0.012, 0.0, abs(f.x - off.x * 0.7)) * smoothstep(0.25, 0.0, abs(f.y - off.y * 0.7))
		+ smoothstep(0.012, 0.0, abs(f.y - off.y * 0.7)) * smoothstep(0.25, 0.0, abs(f.x - off.x * 0.7));
	return (core + cross * 0.35 * step(0.985, h)) * tw;
}

void fragment() {
	vec2 uv = vec2(UV.x * aspect, UV.y);
	float t = TIME;
	float n = fbm(uv * 1.6 + vec2(t * 0.012, -t * 0.008));
	float n2 = fbm(uv * 3.1 - vec2(t * 0.02, 0.0) + n);
	vec3 col = void_color.rgb;
	col = mix(col, nebula_a.rgb, smoothstep(0.35, 0.85, n) * 0.75);
	col = mix(col, nebula_b.rgb * 0.55, smoothstep(0.62, 0.95, n2) * 0.22);
	// Vignette towards the void.
	float vig = smoothstep(1.25, 0.25, length(UV - 0.5) * 1.6);
	col *= mix(0.55, 1.0, vig);
	float thr = 1.0 - 0.06 * star_density;
	float s = stars(uv, 90.0, t, thr) + stars(uv + 11.3, 46.0, t * 0.8, thr + 0.02) * 1.3;
	col += star_color.rgb * s;
	// Stardust motes drifting upward.
	vec2 mv = uv * 7.0 + vec2(sin(t * 0.1) * 0.3, t * 0.06);
	float mote = stars(mv, 1.0, t * 1.7, 0.86) * 0.5;
	col += mix(nebula_b.rgb, star_color.rgb, 0.5) * mote;
	COLOR = vec4(col, opacity);
}
