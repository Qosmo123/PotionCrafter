// Lab walls and floor: 4K tileable masonry / flagstone sets (made by
// tools/gen_textures_4k.py) projected in world space, tinted, with a slow
// macro variation to hide tiling, damp grime near the floor and soot
// toward the ceiling.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.5, 0.47, 0.43);
uniform float tile_meters = 1.8;
uniform float normal_strength = 1.0;
uniform float macro_strength = 0.22;
// Walls only: darker, damper stone near the floor, soot near the ceiling.
uniform float grime_height_meters = 0.7;
uniform float grime_strength = 0.0;
uniform float soot_start_meters = 2.2;
uniform float soot_strength = 0.0;

// Enchanted stone (walls only): a slow star map glows in the masonry, with
// constellation lines and a faint drifting nebula.
uniform float cosmic_strength = 0.0;
uniform vec3 nebula_a : source_color = vec3(0.45, 0.2, 0.9);
uniform vec3 nebula_b : source_color = vec3(0.1, 0.7, 0.85);
uniform vec3 star_color : source_color = vec3(1.0, 0.9, 0.65);
uniform float star_cell_meters = 0.17;

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

vec2 star_pos(vec2 cell) {
	return cell + 0.2 + 0.6 * vec2(hash12(cell), hash12(cell + 19.7));
}

float star_here(vec2 cell) {
	return step(0.3, hash12(cell + 3.3));
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	// Planar projection along the dominant axis; V is "image up".
	vec3 u_axis;
	vec3 v_axis;
	if (abs(n.y) > 0.5) {
		u_axis = vec3(1.0, 0.0, 0.0);
		v_axis = vec3(0.0, 0.0, -1.0);
	} else if (abs(n.x) > 0.5) {
		u_axis = vec3(0.0, 0.0, -sign(n.x));
		v_axis = vec3(0.0, 1.0, 0.0);
	} else {
		u_axis = vec3(sign(n.z), 0.0, 0.0);
		v_axis = vec3(0.0, 1.0, 0.0);
	}
	vec2 p = vec2(dot(world_pos, u_axis), dot(world_pos, v_axis));
	vec2 uv = vec2(p.x, -p.y) / tile_meters;

	vec3 alb = texture(albedo_tex, uv).rgb;
	vec3 tn = texture(normal_tex, uv).xyz * 2.0 - 1.0;
	tn.xy *= normal_strength;
	vec3 wn = normalize(u_axis * tn.x + v_axis * tn.y + n * tn.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Slow colour variation (two octaves) so repeats don't line up.
	float macro = vnoise(p * 0.7) * 0.65 + vnoise(p * 2.3 + 7.1) * 0.35;
	vec3 col = alb * tint * (1.0 + (macro - 0.5) * 2.0 * macro_strength);
	float rough = texture(rough_tex, uv).r;

	float grime = (1.0 - smoothstep(0.0, grime_height_meters, world_pos.y)) * grime_strength;
	grime *= 0.7 + 0.3 * vnoise(p * vec2(6.0, 1.5));
	col *= 1.0 - grime * 0.55;
	rough = mix(rough, rough * 0.8, grime);
	float soot = smoothstep(soot_start_meters, soot_start_meters + 0.9, world_pos.y) * soot_strength;
	col *= 1.0 - soot * (0.6 + 0.4 * vnoise(p * 3.0));

	if (cosmic_strength > 0.0 && abs(n.y) < 0.5) {
		vec2 q = p / star_cell_meters;
		vec2 cell = floor(q);
		float stars = 0.0;
		float lines = 0.0;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 c = cell + vec2(float(i), float(j));
				float here = star_here(c);
				vec2 s = star_pos(c);
				float mag = 0.35 + 0.65 * hash12(c + 8.1);
				float twinkle = 0.6 + 0.4 * sin(TIME * (0.6 + 1.8 * hash12(c + 1.7)) + 6.283 * hash12(c + 4.4));
				float d = length(q - s);
				stars += here * mag * twinkle * (smoothstep(0.05, 0.0, d) + 0.1 * smoothstep(0.2, 0.0, d));
				vec2 cr = c + vec2(1.0, 0.0);
				lines += here * star_here(cr) * step(0.55, hash12(c + 12.9)) * smoothstep(0.012, 0.0, seg_dist(q, s, star_pos(cr)));
				vec2 cu = c + vec2(0.0, 1.0);
				lines += here * star_here(cu) * step(0.7, hash12(c + 27.3)) * smoothstep(0.012, 0.0, seg_dist(q, s, star_pos(cu)));
			}
		}
		lines *= 0.55 + 0.45 * sin(TIME * 0.35 + macro * 9.0);
		float cloud = smoothstep(0.38, 0.9, vnoise(p * 0.9 + vec2(TIME * 0.02, 0.0)) * 0.7 + vnoise(p * 2.6 - vec2(0.0, TIME * 0.015)) * 0.3);
		vec3 nebula = mix(nebula_a, nebula_b, vnoise(p * 0.6 + 11.0 + TIME * 0.01)) * cloud;
		float rise = smoothstep(0.2, 1.1, world_pos.y);
		EMISSION = cosmic_strength * rise * (star_color * stars * 5.0 + mix(star_color, nebula_b, 0.6) * lines * 0.9 + nebula * 0.3);
		col = mix(col, col * (0.75 + nebula * 1.4), cloud * 0.5 * min(cosmic_strength, 1.0));
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.35;
}
