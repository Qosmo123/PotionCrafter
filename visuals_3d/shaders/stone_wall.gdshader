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

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.35;
}
