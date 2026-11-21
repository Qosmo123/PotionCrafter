// Procedural mortared stone blocks for the lab walls and floor (no textures).
shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec3 stone_light : source_color = vec3(0.42, 0.39, 0.35);
uniform vec3 stone_dark : source_color = vec3(0.17, 0.155, 0.14);
uniform vec3 mortar_color : source_color = vec3(0.1, 0.09, 0.08);
uniform vec2 block_size_meters = vec2(0.45, 0.22);
uniform float bump_strength = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * vnoise(p);
		p *= 2.1;
		amp *= 0.5;
	}
	return sum;
}

vec3 stone(vec2 p) {
	vec2 cell = p / block_size_meters;
	cell.x += step(1.0, mod(floor(cell.y), 2.0)) * 0.5;
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	vec2 edge = min(f, 1.0 - f) * block_size_meters;
	float joint = smoothstep(0.004, 0.014, min(edge.x, edge.y));
	float n = fbm(p * 9.0 + id * 3.1);
	float tone = clamp(hash12(id) * 0.5 + n * 0.7, 0.0, 1.0);
	float height = joint * (0.6 + n * 0.4);
	return vec3(tone, height, joint);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = abs(world_normal.y) > 0.5 ? world_pos.xz : (abs(world_normal.x) > 0.5 ? world_pos.zy : world_pos.xy);
	vec3 s = stone(p);
	float e = 0.002;
	float hx = stone(p + vec2(e, 0.0)).y - s.y;
	float hy = stone(p + vec2(0.0, e)).y - s.y;
	ALBEDO = mix(mortar_color, mix(stone_dark, stone_light, s.x), s.z);
	NORMAL_MAP = normalize(vec3(-hx / e * 0.01 * bump_strength, -hy / e * 0.01 * bump_strength, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = mix(0.95, 0.78, s.z);
	SPECULAR = 0.3;
}
