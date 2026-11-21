// Procedural varnished oak planks. Resolution-independent, so it stays sharp
// at 4K with no texture memory. Grain, growth rings, plank seams and bump
// normals all come from world-space noise.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec3 wood_light : source_color = vec3(0.42, 0.27, 0.15);
uniform vec3 wood_dark : source_color = vec3(0.17, 0.095, 0.045);
uniform float ring_frequency = 70.0;
uniform float plank_width_meters = 0.18;
uniform float bump_strength = 0.6;
uniform float varnish = 0.35;

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
	for (int i = 0; i < 5; i++) {
		sum += amp * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return sum;
}

// Returns (tone, height). Planks run along x.
vec2 wood(vec2 p) {
	float plank_id = floor(p.y / plank_width_meters);
	float in_plank = fract(p.y / plank_width_meters);
	vec2 q = p + vec2(hash12(vec2(plank_id, 7.0)) * 13.0, plank_id * 3.7);
	float warp = fbm(q * vec2(2.0, 9.0)) * 0.08;
	float rings = fract((q.y * 0.9 + warp) * ring_frequency);
	rings = smoothstep(0.0, 0.35, rings) * smoothstep(1.0, 0.55, rings);
	float grain = fbm(q * vec2(6.0, 260.0));
	float tone = clamp(rings * 0.55 + grain * 0.6 + hash12(vec2(plank_id, 1.0)) * 0.25 - 0.15, 0.0, 1.0);
	float seam = smoothstep(0.0, 0.012, in_plank) * smoothstep(1.0, 0.988, in_plank);
	float height = grain * 0.4 + rings * 0.15 + (seam - 1.0) * 0.8;
	return vec2(tone * seam + (1.0 - seam) * 0.05, height);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = abs(world_normal.y) > 0.5 ? world_pos.xz : vec2(world_pos.x + world_pos.z, world_pos.y * 4.0);
	vec2 w = wood(p);
	float e = 0.0006;
	float hx = wood(p + vec2(e, 0.0)).y - w.y;
	float hy = wood(p + vec2(0.0, e)).y - w.y;
	// Wear: bottle ring stains, knife scratches, and darker grime toward the edges.
	vec2 stain_cell = floor(p / 0.23);
	vec2 stain_center = (stain_cell + vec2(hash12(stain_cell), hash12(stain_cell + 5.3))) * 0.23;
	float stain_r = 0.02 + hash12(stain_cell + 2.1) * 0.03;
	float ring_d = abs(length(p - stain_center) - stain_r);
	float stain = (1.0 - smoothstep(0.0006, 0.0025, ring_d)) * step(0.55, hash12(stain_cell + 9.7));
	vec2 sp = vec2(p.x * 0.7 + p.y * 0.7, p.y * 0.7 - p.x * 0.7);
	float scratch = smoothstep(0.985, 1.0, vnoise(vec2(sp.x * 600.0, sp.y * 4.0))) * 0.6;
	float grime = smoothstep(0.35, 0.6, abs(world_pos.z)) * 0.25;
	vec3 base = mix(wood_dark, wood_light, w.x);
	base *= 1.0 - stain * 0.45 - grime;
	base = mix(base, vec3(0.55, 0.42, 0.3), scratch * 0.5);
	ALBEDO = base;
	NORMAL_MAP = normalize(vec3(-hx / e * 0.002 * bump_strength, -hy / e * 0.002 * bump_strength, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = clamp(mix(0.72, 0.42, w.x) + scratch * 0.3 + stain * 0.15, 0.0, 1.0);
	SPECULAR = 0.45;
	CLEARCOAT = varnish;
	CLEARCOAT_ROUGHNESS = 0.22;
}
