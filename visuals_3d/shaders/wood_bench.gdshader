// Procedural varnished oak planks. Resolution-independent: it stays sharp at
// any resolution (8K and beyond) with zero texture memory. Grain, growth
// rings, knots, plank seams and bump normals all come from world-space noise.
// An alchemist's bench is well used: worn edges where arms rest, ring stains,
// coloured potion spills, scorch marks, chalk dust and iron nail heads.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec3 wood_light : source_color = vec3(0.42, 0.27, 0.15);
uniform vec3 wood_dark : source_color = vec3(0.17, 0.095, 0.045);
uniform float ring_frequency = 70.0;
uniform float plank_width_meters = 0.18;
uniform float bump_strength = 0.6;
uniform float varnish = 0.35;
uniform float wear = 1.0;
// Front edge of the bench in world z (where hands and sleeves wear it).
uniform float front_edge_z = 0.6;

// Star specks inlaid in the bench top: sparse, slowly twinkling.
uniform float star_inlay = 0.0;

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
	// Knots: every ~0.7 m along some planks, the grain bends around a dark eye.
	float knot_cell = floor(p.x / 0.7);
	vec2 knot_c = vec2((knot_cell + 0.2 + hash12(vec2(knot_cell, plank_id)) * 0.6) * 0.7,
		(plank_id + 0.3 + hash12(vec2(plank_id, knot_cell + 3.0)) * 0.4) * plank_width_meters);
	vec2 kd = (p - knot_c) * vec2(1.0, 2.2);
	float knot_on = step(0.55, hash12(vec2(knot_cell * 1.7, plank_id + 11.0)));
	float knot_r = length(kd);
	q.y += knot_on * 0.012 / (knot_r * 40.0 + 0.6);
	float warp = fbm(q * vec2(2.0, 9.0)) * 0.08;
	float rings = fract((q.y * 0.9 + warp) * ring_frequency);
	rings = smoothstep(0.0, 0.35, rings) * smoothstep(1.0, 0.55, rings);
	float grain = fbm(q * vec2(6.0, 260.0));
	float tone = clamp(rings * 0.55 + grain * 0.6 + hash12(vec2(plank_id, 1.0)) * 0.25 - 0.15, 0.0, 1.0);
	float knot_eye = knot_on * (1.0 - smoothstep(0.004, 0.011, knot_r));
	tone = mix(tone, 0.02, knot_eye * 0.9);
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
	// Fine open pores of oak.
	float pores = smoothstep(0.72, 0.95, vnoise(vec2(p.x * 900.0, p.y * 140.0)));
	base *= 1.0 - pores * 0.12;
	base *= 1.0 - stain * 0.45 - grime;
	base = mix(base, vec3(0.55, 0.42, 0.3), scratch * 0.5);
	// Worn front edge: varnish rubbed off, paler and rougher where arms rest.
	float edge_wear = smoothstep(front_edge_z - 0.09, front_edge_z, world_pos.z) * (0.6 + 0.4 * vnoise(p * 30.0)) * wear;
	base = mix(base, base * 1.35 + vec3(0.04, 0.03, 0.02), edge_wear * 0.6);
	// Potion spills: faint coloured, dried-edge blotches (a few per bench).
	vec2 spill_cell = floor(p / 0.45);
	float spill_h = hash12(spill_cell + 31.0);
	vec2 spill_c = (spill_cell + vec2(hash12(spill_cell + 1.7), hash12(spill_cell + 4.1))) * 0.45;
	float spill_d = length((p - spill_c) * vec2(1.0, 1.3)) + (fbm(p * 40.0) - 0.5) * 0.03;
	float spill_r = 0.025 + hash12(spill_cell + 8.8) * 0.04;
	float spill = (1.0 - smoothstep(spill_r - 0.004, spill_r, spill_d)) * step(0.62, spill_h) * wear;
	float spill_rim = spill * smoothstep(spill_r - 0.006, spill_r - 0.001, spill_d);
	vec3 spill_col = mix(vec3(0.35, 0.15, 0.5), vec3(0.15, 0.4, 0.25), hash12(spill_cell + 2.2));
	spill_col = mix(spill_col, vec3(0.45, 0.25, 0.08), step(0.82, hash12(spill_cell + 6.6)));
	base = mix(base, base * spill_col * 2.2, spill * 0.45 + spill_rim * 0.35);
	// Scorch marks: charred, soft-edged burns from hot flasks and dropped coals.
	vec2 burn_cell = floor(p / 0.6);
	vec2 burn_c = (burn_cell + vec2(hash12(burn_cell + 13.0), hash12(burn_cell + 17.0))) * 0.6;
	float burn_d = length(p - burn_c) + (fbm(p * 25.0) - 0.5) * 0.04;
	float burn = (1.0 - smoothstep(0.01, 0.05, burn_d)) * step(0.78, hash12(burn_cell + 23.0)) * wear;
	base = mix(base, vec3(0.03, 0.02, 0.015), burn * 0.8);
	// Chalk dust from drawing sigils: pale smudges.
	float chalk = smoothstep(0.68, 0.85, fbm(p * 7.0 + 40.0)) * smoothstep(0.55, 0.8, vnoise(p * 60.0)) * 0.35 * wear;
	base = mix(base, vec3(0.86, 0.84, 0.8), chalk);
	// Iron nail heads at the plank ends every 0.6 m.
	float plank_row = floor(p.y / plank_width_meters);
	vec2 nail_c = vec2((floor(p.x / 0.6) + 0.5) * 0.6, (plank_row + 0.5) * plank_width_meters);
	vec2 nd = p - nail_c;
	float nail = 1.0 - smoothstep(0.0028, 0.0036, length(vec2(abs(nd.x) - 0.04, nd.y)));
	base = mix(base, vec3(0.12, 0.11, 0.1), nail);
	if (star_inlay > 0.0 && world_normal.y > 0.5) {
		vec2 sq = world_pos.xz / 0.07;
		vec2 sc = floor(sq);
		float present = step(0.8, hash12(sc + 5.5));
		vec2 sp2 = sc + 0.25 + 0.5 * vec2(hash12(sc + 1.3), hash12(sc + 9.1));
		float sd = length(sq - sp2);
		float tw = 0.5 + 0.5 * sin(TIME * (0.5 + 1.5 * hash12(sc + 2.2)) + 6.283 * hash12(sc + 7.7));
		float speck = present * tw * (smoothstep(0.07, 0.0, sd) + 0.2 * smoothstep(0.3, 0.0, sd));
		vec3 speck_col = mix(vec3(1.0, 0.85, 0.5), vec3(0.45, 0.85, 1.0), step(0.5, hash12(sc + 3.9)));
		EMISSION = speck_col * speck * 1.6 * star_inlay;
	}
	ALBEDO = base;
	METALLIC = nail * 0.8;
	NORMAL_MAP = normalize(vec3(-hx / e * 0.002 * bump_strength, -hy / e * 0.002 * bump_strength, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = clamp(mix(0.72, 0.42, w.x) + scratch * 0.3 + stain * 0.15 + edge_wear * 0.3 + burn * 0.25 + chalk * 0.4 - spill * 0.15 - nail * 0.3, 0.0, 1.0);
	SPECULAR = 0.45;
	CLEARCOAT = varnish * (1.0 - edge_wear * 0.8) * (1.0 - burn) * (1.0 - chalk);
	CLEARCOAT_ROUGHNESS = 0.22;
}
