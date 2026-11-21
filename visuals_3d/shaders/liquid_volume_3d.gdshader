// Analytical 3D liquid volume (no particle fluid inside containers).
//
// The inner cylinder mesh is clipped against the free surface:
//   * a plane through `fill_point_world` with normal `surface_normal_world`
//     (tilted by the CPU slosh model), plus
//   * the paraboloid dip of a rotating fluid, h(r) = w^2/(2g) * (r^2 - R^2/2),
//     which conserves volume (the mean height is unchanged).
// Front faces are the liquid seen through the wall: colour follows
// Beer-Lambert absorption along the chord through the cylinder.
// Back faces below the surface stand in for the top surface (cap), with
// ripple normals, a bright meniscus ring and glints. Single draw call;
// up to 3 density layers stratified by depth.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

const float GRAVITY = 9.80665;

uniform vec3 fill_point_world = vec3(0.0);
uniform vec3 surface_normal_world = vec3(0.0, 1.0, 0.0);
uniform vec3 vessel_axis_world = vec3(0.0, 1.0, 0.0);
uniform float vessel_radius_meters = 0.03;
uniform float fill_fraction = 0.5;
uniform vec4 liquid_color : source_color = vec4(0.4, 0.65, 0.95, 0.5);
uniform vec4 surface_color : source_color = vec4(0.85, 0.93, 1.0, 0.85);
uniform vec4 emission_hdr = vec4(0.0);
uniform float turbidity : hint_range(0.0, 1.0) = 0.1;
uniform float swirl_rad_s = 0.0;
uniform float agitation : hint_range(0.0, 1.0) = 0.0;
uniform float effervescence : hint_range(0.0, 1.0) = 0.0;
uniform float foam_thickness_meters = 0.0;
uniform float glitter : hint_range(0.0, 1.0) = 0.0;
uniform float rainbow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 incandescence = vec3(0.0);
uniform vec3 foam_color : source_color = vec3(0.96, 0.95, 0.92);
uniform vec4 layer2_color : source_color = vec4(0.0);
uniform float layer2_depth_meters = -1.0;
uniform vec4 layer3_color : source_color = vec4(0.0);
uniform float layer3_depth_meters = -1.0;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Capillary ripple height field on the surface (metres-ish units, scaled later).
float ripple(vec2 p, float t, float r) {
	float rings = sin(r * 260.0 - t * 11.0) * 0.35 + sin(r * 410.0 - t * 17.0) * 0.15;
	float chop = vnoise(p * 160.0 + vec2(t * 0.9, -t * 0.7)) + vnoise(p * 330.0 - vec2(t * 1.3, t * 0.4)) * 0.5;
	return rings + chop;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 rel = world_pos - fill_point_world;
	vec3 radial = rel - dot(rel, vessel_axis_world) * vessel_axis_world;
	float r = length(radial);
	float R = vessel_radius_meters;
	float vortex_k = swirl_rad_s * swirl_rad_s / (2.0 * GRAVITY);
	float surface_offset = vortex_k * (r * r - 0.5 * R * R);
	float signed_dist = dot(rel, surface_normal_world) - surface_offset;
	if (fill_fraction <= 0.0005 || signed_dist > foam_thickness_meters) {
		discard;
	}
	// Foam head: a bubbly, nearly opaque band from the liquid surface up.
	if (signed_dist > 0.0) {
		float cells = vnoise(world_pos.xz * 900.0 + world_pos.y * 700.0) * 0.6 + vnoise(world_pos.xy * 2300.0) * 0.4;
		ALBEDO = foam_color * (0.82 + 0.18 * cells);
		ALPHA = 0.9;
		ROUGHNESS = 0.55;
		SPECULAR = 0.3;
		if (!FRONT_FACING) {
			NORMAL = normalize((VIEW_MATRIX * vec4(surface_normal_world, 0.0)).xyz);
		}
		EMISSION = emission_hdr.rgb * 0.15;
	} else {
	float depth_m = -signed_dist;

	vec4 col = liquid_color;
	if (layer2_depth_meters > 0.0) {
		col = mix(col, layer2_color, smoothstep(layer2_depth_meters - 0.002, layer2_depth_meters + 0.002, depth_m));
	}
	if (layer3_depth_meters > 0.0) {
		col = mix(col, layer3_color, smoothstep(layer3_depth_meters - 0.002, layer3_depth_meters + 0.002, depth_m));
	}

	float ang = atan(radial.z, radial.x);
	if (rainbow > 0.0) {
		float hue = fract(TIME * 0.08 + depth_m * 6.0 + ang / 6.2831853);
		vec3 rb = clamp(abs(fract(vec3(hue) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
		col.rgb = mix(col.rgb, rb, rainbow * 0.75);
		col.a = max(col.a, rainbow * 0.6);
	}
	float swirl_band = sin(ang * 3.0 - TIME * swirl_rad_s * 0.6 + depth_m * 70.0) * clamp(abs(swirl_rad_s) * 0.04, 0.0, 0.2);
	vec3 cell = floor(vec3(world_pos.x, world_pos.y - TIME * 0.06, world_pos.z) * 420.0);
	float bubble = step(1.0 - effervescence * 0.06, hash13(cell));
	vec3 aura = emission_hdr.rgb * (0.8 + 0.2 * sin(TIME * 1.7 + depth_m * 90.0 + ang * 2.0));
	// Glitter: tiny flakes that catch the light and twinkle as they tumble.
	vec3 flake_cell = floor(world_pos * 700.0 + vec3(0.0, TIME * 0.4, 0.0));
	float flake = step(1.0 - glitter * 0.035, hash13(flake_cell)) * (0.5 + 0.5 * sin(TIME * 9.0 + hash13(flake_cell + 7.0) * 40.0));
	aura += vec3(1.0, 0.95, 0.8) * flake * glitter * 3.0;
	aura += incandescence;

	if (FRONT_FACING) {
		float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		// Chord length through the cylinder along the view ray (thick at centre, thin at rim).
		float path_m = 2.0 * R * n_dot_v;
		vec3 sigma = (vec3(1.0) - col.rgb) * (18.0 + turbidity * 300.0) + vec3(turbidity * 140.0);
		vec3 transmit = exp(-sigma * path_m);
		float opacity = clamp(1.0 - (transmit.r + transmit.g + transmit.b) / 3.0, 0.0, 1.0);
		opacity = max(opacity, col.a * col.a * 0.8);
		float fresnel = pow(1.0 - n_dot_v, 4.0);
		float meniscus = 1.0 - smoothstep(0.0, 0.0022, depth_m);
		ALBEDO = mix(col.rgb * (1.0 + swirl_band) * mix(1.0, 0.7, opacity), surface_color.rgb, meniscus * 0.6) + vec3(bubble * 0.6);
		ALPHA = clamp(mix(0.04, 0.96, opacity) + fresnel * 0.3 + meniscus * 0.2 + bubble * 0.3, 0.0, 0.98);
		ROUGHNESS = 0.03;
		SPECULAR = 0.55;
		EMISSION = aura * (0.35 + 0.65 * opacity);
	} else {
		// Free surface: paraboloid vortex slope + slosh tilt + capillary ripples.
		vec2 sp = vec2(rel.x, rel.z);
		float t = TIME;
		float e = 0.0006;
		float amp = 0.00035 + agitation * 0.0022;
		float h0 = ripple(sp, t, r);
		float hx = (ripple(sp + vec2(e, 0.0), t, r) - h0) / e;
		float hz = (ripple(sp + vec2(0.0, e), t, r) - h0) / e;
		vec3 radial_dir = r > 1e-5 ? radial / r : vec3(0.0);
		vec3 n_world = normalize(surface_normal_world - radial_dir * (2.0 * vortex_k * r) - vec3(hx, 0.0, hz) * amp);
		float r_norm = clamp(r / max(R, 1e-4), 0.0, 1.0);
		float meniscus = smoothstep(0.82, 1.0, r_norm);
		float glint = pow(vnoise(sp * 520.0 + vec2(t * 2.0, t * 1.3)), 14.0) * (0.3 + agitation * 3.0);
		ALBEDO = mix(col.rgb, surface_color.rgb, 0.3 + meniscus * 0.45) + vec3(bubble * 0.5);
		ALPHA = clamp(0.12 + col.a * 0.7 + meniscus * 0.25 + glint, 0.0, 1.0);
		NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
		ROUGHNESS = 0.012 + agitation * 0.04;
		SPECULAR = 0.65;
		EMISSION = aura * 0.9 + vec3(glint);
		if (foam_thickness_meters > 0.0008) {
			// Looking down through the foam cap: foam, not liquid.
			ALBEDO = foam_color;
			ALPHA = 0.92;
			ROUGHNESS = 0.6;
		}
	}
	}
}
