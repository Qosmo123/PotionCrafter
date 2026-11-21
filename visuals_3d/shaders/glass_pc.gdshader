// PC tier (Forward+) borosilicate glass.
//  * Schlick Fresnel from the real IOR (F0 ~ 0.036): nearly invisible face-on,
//    mirror-like at grazing angles, so the reflection probe, sky and lights
//    show on the rims.
//  * Wall-thickness tint: the path through the glass grows ~1/cos at the
//    silhouette, which gives the faint green-cyan edge of real glass.
//  * Screen-texture chromatic refraction of the opaque background.
//  * Faint hand-blown waviness and micro-roughness variation in the normals.
// A second pass (glass_inner) draws the far inner wall for the double-wall look.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec3 edge_tint : source_color = vec3(0.55, 0.85, 0.78);
uniform float ior = 1.47;
uniform float wall_thickness_meters = 0.0022;
uniform float absorption_per_meter = 55.0;
uniform float refraction_strength = 0.035;
uniform float chromatic_spread = 0.22;
uniform float waviness = 0.25;
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.06;
// Cool moonlight rim so clear glass reads against dark wood.
uniform vec3 moon_rim_color : source_color = vec3(0.6, 0.74, 1.0);
uniform float moon_rim_strength = 0.24;

varying vec3 world_pos;

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
}

void fragment() {
	vec2 wp = world_pos.xz * 90.0 + vec2(world_pos.y * 140.0, 0.0);
	vec3 wobble = vec3(vnoise(wp) - 0.5, vnoise(wp + 17.0) - 0.5, 0.0) * waviness * 0.12;
	vec3 n = normalize(NORMAL + wobble);
	float n_dot_v = clamp(dot(n, VIEW), 0.001, 1.0);

	float f0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
	float fresnel = f0 + (1.0 - f0) * pow(1.0 - n_dot_v, 5.0);

	float path_m = wall_thickness_meters / max(n_dot_v, 0.08);
	vec3 transmit = exp(-(vec3(1.0) - edge_tint) * absorption_per_meter * path_m);

	vec2 offset = n.xy * refraction_strength * (1.0 - n_dot_v);
	vec3 refracted;
	refracted.r = textureLod(screen_texture, SCREEN_UV - offset * (1.0 + chromatic_spread), 0.0).r;
	refracted.g = textureLod(screen_texture, SCREEN_UV - offset, 0.0).g;
	refracted.b = textureLod(screen_texture, SCREEN_UV - offset * (1.0 - chromatic_spread), 0.0).b;

	float edge = 1.0 - transmit.g;
	// Crisp silhouette: thick glass seen edge-on goes dark (total internal
	// reflection) with a thin bright line just inside; plus a soft vertical
	// studio-light streak on cylinders. Reads clearly in the side view.
	float rim = smoothstep(0.34, 0.05, n_dot_v);
	float rim_line = exp(-pow((n_dot_v - 0.19) / 0.035, 2.0));
	float streak = smoothstep(0.1, 0.0, abs(n.x - 0.52)) * smoothstep(-0.6, 0.2, n.y);
	ALBEDO = edge_tint * 0.06;
	float moon_rim = pow(1.0 - n_dot_v, 4.0);
	EMISSION = refracted * transmit * 0.35 * (1.0 - rim * 0.6) + vec3(rim_line * 0.1 + streak * 0.16) + moon_rim_color * moon_rim * moon_rim_strength;
	ALPHA = clamp(0.05 + edge * 3.0 + fresnel * 0.9 + rim * 0.2 + streak * 0.25 + moon_rim * 0.15, 0.0, 0.95);
	NORMAL = n;
	ROUGHNESS = glass_roughness * (0.6 + vnoise(wp * 3.0) * 0.8);
	METALLIC = 0.0;
	SPECULAR = 0.5 + fresnel * 0.5;
}
