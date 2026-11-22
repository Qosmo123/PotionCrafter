// Shared body of the analytical liquid volume (see liquid_volume_3d.gdshader
// for the mobile tier and liquid_volume_pc.gdshader for PC).
//
// The inner cylinder mesh is clipped against the free surface:
//   * a plane through `fill_point_world` with normal `surface_normal_world`
//     (tilted by the CPU slosh model), plus
//   * the paraboloid dip of a rotating fluid, h(r) = w^2/(2g) * (r^2 - R^2/2),
//     which conserves volume (the mean height is unchanged).
//
// Look: a real liquid is mostly the scene behind it, bent and tinted.
//   * Absorption (Beer-Lambert): light loses the colours the liquid absorbs
//     along the path through it; `liquid_color.a` says how strongly coloured
//     the liquid is (water ~0.2, ink ~1).
//   * Scattering (`turbidity`): cloudy liquids (milk, slime, suspensions)
//     scatter light back toward you, so they look lit and opaque.
//   * PC (LIQUID_SCREEN_REFRACTION): the opaque scene behind is sampled,
//     refracted by the curved surface and multiplied by the transmission.
//     Mobile: no screen reads; transparency + dark absorptive tint instead.
//   * Glossy surface with Fresnel: clear highlights, brighter at grazing angles.
// Alive: the surface line always wobbles a little (more when shaken), the
// meniscus climbs the glass at the walls, a bright edge with a shadow band
// marks the waterline, deeper liquid is darker and richer, clear liquids
// carry a slow caustic shimmer, and round bubbles drift up.
// Front faces = liquid seen through the wall; back faces = the free surface,
// seen from above (intersected properly with the surface plane). Up to 3
// density layers, foam head, bubbles, swirl, glitter, rainbow, arcane glow.

render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

const float GRAVITY = 9.80665;
const float LIQUID_IOR = 1.33;

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
// Absorption strength per metre for a fully coloured liquid (alpha = 1).
uniform float absorption_per_m = 140.0;
// Scattering per metre at turbidity 1. Scattering rises steeply with
// turbidity (t^2.5): water (0.03) stays crystal clear, soap (0.25) is hazy,
// glue/milk (0.7+) turn opaque.
uniform float scatter_per_m = 420.0;
// Idle surface wobble (metres) and meniscus climb at the glass (metres).
uniform float idle_wave_meters = 0.0007;
uniform float meniscus_climb_meters = 0.0018;
// Where a pour stream lands on this liquid and how hard (0..1): a dimple,
// rings running outward and a column of plunge bubbles.
uniform vec3 pour_hit_world = vec3(0.0);
// 1 = the contents are a dry or damp powder (Vessel3D granular mode): an
// opaque matte bed of grains whose surface is the heap, not a level liquid.
uniform float granular = 0.0;
// 0..1: how damp the powder is (darker, clumpier).
uniform float powder_damp = 0.0;
// 0..1: how finely ground (MixtureContainer.grain_surface): finer powder has
// smaller grains and looks paler (more surfaces scatter light).
uniform float powder_fineness = 0.0;
uniform float pour_intensity = 0.0;

#ifdef LIQUID_SCREEN_REFRACTION
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float refraction_strength = 0.06;
#endif

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

// Capillary ripple height field on the surface.
float ripple(vec2 p, float t, float r) {
	float rings = sin(r * 260.0 - t * 11.0) * 0.35 + sin(r * 410.0 - t * 17.0) * 0.15;
	float chop = vnoise(p * 160.0 + vec2(t * 0.9, -t * 0.7)) + vnoise(p * 330.0 - vec2(t * 1.3, t * 0.4)) * 0.5;
	return rings + chop;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float scatter_coeff(float turb) {
	return pow(clamp(turb, 0.0, 1.0), 2.5) * scatter_per_m;
}


// Per-channel extinction for this liquid: absorption of the colours it is
// not, scaled by how strongly coloured it is, plus grey scattering.
vec3 extinction(vec4 col, float turb) {
	float strength = 0.15 + col.a * col.a * 1.6;
	vec3 absorb = (vec3(1.0) - col.rgb) * absorption_per_m * strength;
	return absorb + vec3(scatter_coeff(turb));
}

void fragment() {
	vec3 rel = world_pos - fill_point_world;
	vec3 radial = rel - dot(rel, vessel_axis_world) * vessel_axis_world;
	float r = length(radial);
	float R = vessel_radius_meters;
	float vortex_k = granular > 0.5 ? 0.0 : swirl_rad_s * swirl_rad_s / (2.0 * GRAVITY);
	float surface_offset = vortex_k * (r * r - 0.5 * R * R);
	// Living surface: two travelling waves (stronger when agitated) and the
	// meniscus curling up where the liquid meets the glass.
	float wave_amp = granular > 0.5 ? 0.0 : idle_wave_meters + agitation * 0.004 + effervescence * 0.0015;
	float wave = (sin(world_pos.x * 190.0 + TIME * 3.1) * 0.6 + sin(world_pos.x * 330.0 - world_pos.z * 140.0 - TIME * 4.7) * 0.4) * wave_amp;
	float climb = (granular > 0.5 ? 0.0 : meniscus_climb_meters) * smoothstep(0.78, 1.0, clamp(r / max(R, 1e-4), 0.0, 1.0));
	surface_offset -= wave + climb;
	// Pour impact: a Gaussian dimple under the stream and rings running out.
	float hit_d = length((world_pos - pour_hit_world).xz);
	float dimple = (granular > 0.5 ? 0.0 : pour_intensity) * 0.0035 * exp(-hit_d * hit_d / 0.00002);
	float rings_h = (granular > 0.5 ? 0.0 : pour_intensity) * 0.0009 * sin(hit_d * 280.0 - TIME * 16.0) * exp(-hit_d * 45.0);
	surface_offset += dimple - rings_h;
	float signed_dist = dot(rel, surface_normal_world) - surface_offset;
	if (fill_fraction <= 0.0005 || signed_dist > foam_thickness_meters) {
		discard;
	}
	vec3 cam_world = INV_VIEW_MATRIX[3].xyz;
	bool eye_above = dot(cam_world - fill_point_world, surface_normal_world) > 0.0;
	// Back faces only stand in for the free surface, seen from above. From the
	// side, the front faces already show the whole body of liquid.
	if (!FRONT_FACING && !eye_above) {
		discard;
	}
	if (!FRONT_FACING && signed_dist <= 0.0) {
		// Only where the line of sight really enters through the top surface:
		// intersect the eye->fragment ray with the surface plane and keep it if
		// that crossing lies inside the vessel. Otherwise the eye looks in
		// through the side wall, and the front faces already show it.
		vec3 d = world_pos - cam_world;
		float denom = dot(d, surface_normal_world);
		if (abs(denom) < 1e-6) {
			discard;
		}
		float ts = dot(fill_point_world - cam_world, surface_normal_world) / denom;
		vec3 cross_rel = cam_world + d * ts - fill_point_world;
		vec3 cross_radial = cross_rel - dot(cross_rel, vessel_axis_world) * vessel_axis_world;
		if (ts <= 0.0 || ts >= 1.0 || length(cross_radial) > vessel_radius_meters * 1.02) {
			discard;
		}
	}

	// Powder: an opaque bed of grains. Seen through the glass, grains pack
	// against the wall in faint strata (each pour leaves a layer); from above,
	// the heap surface is speckled and bumpy. No refraction, gloss or waves.
	if (granular > 0.5) {
		if (signed_dist > 0.0) {
			discard;
		}
		float depth_g = -signed_dist;
		vec4 gcol = liquid_color;
		if (layer2_depth_meters > 0.0) {
			gcol = mix(gcol, layer2_color, smoothstep(layer2_depth_meters - 0.001, layer2_depth_meters + 0.001, depth_g));
		}
		if (layer3_depth_meters > 0.0) {
			gcol = mix(gcol, layer3_color, smoothstep(layer3_depth_meters - 0.001, layer3_depth_meters + 0.001, depth_g));
		}
		float fine = hash13(floor(world_pos * (2400.0 + powder_fineness * 3600.0)));
		float coarse = vnoise(world_pos.xz * 320.0 + world_pos.y * 90.0) * 0.6 + vnoise(world_pos.xy * 1100.0) * 0.4;
		float strata = 0.5 + 0.5 * sin(depth_g * 900.0 + vnoise(world_pos.xz * 140.0) * 5.0);
		float shade = 0.74 + 0.2 * coarse + 0.14 * (fine - 0.5);
		if (FRONT_FACING) {
			shade *= 0.92 + 0.08 * strata;
			// Grains pressed against the glass right at the top edge catch light.
			shade += (1.0 - smoothstep(0.0, 0.0015, depth_g)) * 0.12;
		} else {
			vec3 bump = vec3(fine - 0.5, 0.0, coarse - 0.5) * 0.35;
			NORMAL = normalize((VIEW_MATRIX * vec4(normalize(surface_normal_world + bump), 0.0)).xyz);
		}
		shade *= 1.0 - powder_damp * 0.35;
		float glint = step(0.995, fine) * (0.6 + 0.4 * sin(TIME * 3.0 + fine * 50.0));
		vec3 flake_cell = floor(world_pos * 700.0);
		float flake = step(1.0 - glitter * 0.04, hash13(flake_cell)) * (0.5 + 0.5 * sin(TIME * 7.0 + hash13(flake_cell + 7.0) * 40.0));
		vec3 base_g = mix(gcol.rgb, gcol.rgb * 0.75 + vec3(0.25), powder_fineness * 0.45);
		ALBEDO = base_g * shade + vec3(glint * 0.2 * (1.0 - powder_fineness * 0.7));
		ALPHA = 1.0;
		ROUGHNESS = mix(0.95, 0.7, powder_damp) - glint * 0.4;
		SPECULAR = 0.18 + glint * 0.4 + powder_damp * 0.15;
		EMISSION = emission_hdr.rgb * 0.5 + vec3(1.0, 0.95, 0.8) * flake * glitter * 2.0 + incandescence;
	} else if (signed_dist > 0.0) {
		// Foam head: a bubbly, nearly opaque band from the liquid surface up.
		float cells = vnoise(world_pos.xz * 900.0 + world_pos.y * 700.0) * 0.6 + vnoise(world_pos.xy * 2300.0) * 0.4;
		ALBEDO = foam_color * (0.82 + 0.18 * cells);
		ALPHA = 0.92;
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
		vec3 bp = vec3(world_pos.x, world_pos.y - TIME * (0.035 + effervescence * 0.05), world_pos.z) * 380.0;
		vec3 bcell = floor(bp);
		vec3 bf = fract(bp) - 0.5;
		float bubble_rate = 0.0015 + effervescence * 0.08;
		// Plunge bubbles: a column under the stream that rises back up.
		float col_d = length((world_pos - pour_hit_world).xz);
		float column = pour_intensity * (1.0 - smoothstep(0.002, 0.008, col_d));
		float rise = fract(world_pos.y * 120.0 - TIME * 3.0 + vnoise(world_pos.xz * 900.0) * 3.0);
		float bubble = step(1.0 - bubble_rate, hash13(bcell)) * smoothstep(0.32, 0.22, length(bf.xy));
		bubble += column * smoothstep(0.85, 1.0, rise) * (1.0 - smoothstep(0.0, 0.04, depth_m * 0.5));
		vec3 aura = emission_hdr.rgb * (0.8 + 0.2 * sin(TIME * 1.7 + depth_m * 90.0 + ang * 2.0));
		vec3 flake_cell = floor(world_pos * 700.0 + vec3(0.0, TIME * 0.4, 0.0));
		float flake = step(1.0 - glitter * 0.035, hash13(flake_cell)) * (0.5 + 0.5 * sin(TIME * 9.0 + hash13(flake_cell + 7.0) * 40.0));
		aura += vec3(1.0, 0.95, 0.8) * flake * glitter * 3.0;
		aura += incandescence;
		vec3 sigma = extinction(col, turbidity);
		vec3 tint = col.rgb * (1.0 + swirl_band);

		vec3 n_view = NORMAL;
		float path_m;
		float meniscus;
		if (FRONT_FACING) {
			float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
			// Chord through the cylinder along the view ray: thick in the middle, thin at the rim.
			path_m = max(2.0 * R * n_dot_v, 0.002);
			meniscus = 1.0 - smoothstep(0.0, 0.0025, depth_m);
			ROUGHNESS = 0.06;
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
			n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
			NORMAL = n_view;
			// Looking down through the surface the light crosses the whole depth.
			path_m = max(depth_m + R, 0.004);
			meniscus = smoothstep(0.85, 1.0, clamp(r / max(R, 1e-4), 0.0, 1.0));
			ROUGHNESS = 0.05 + agitation * 0.05;
		}
		// Deeper liquid looks darker and richer (longer light path to the eye).
		path_m += depth_m * 0.5;
		vec3 transmit = exp(-sigma * path_m);
		// Waterline: a bright edge right at the surface and a soft shadow band below.
		float edge = (1.0 - smoothstep(0.0, 0.0012, depth_m)) * (FRONT_FACING ? 1.0 : 0.0);
		float shadow_band = smoothstep(0.0008, 0.003, depth_m) * (1.0 - smoothstep(0.003, 0.009, depth_m)) * (FRONT_FACING ? 1.0 : 0.0);
		transmit *= 1.0 - shadow_band * 0.22;
		// Caustic shimmer: slow light ripples, strongest in clear liquids.
		vec2 cq = vec2(world_pos.x * 140.0 + TIME * 0.6, world_pos.y * 140.0 - TIME * 0.4);
		float caustic = pow(abs(sin(cq.x + vnoise(cq * 0.7) * 3.0) * sin(cq.y * 0.8 + vnoise(cq.yx * 0.6) * 3.0)), 6.0);
		float transmit_avg = (transmit.r + transmit.g + transmit.b) / 3.0;
		// Scattering: cloudy liquids glow with their own (lit) colour.
		float scatter = 1.0 - exp(-scatter_coeff(turbidity) * path_m);
		float n_dot_v2 = clamp(dot(n_view, VIEW), 0.0, 1.0);
		float fresnel = 0.02 + 0.98 * pow(1.0 - n_dot_v2, 5.0);

#ifdef LIQUID_SCREEN_REFRACTION
		// See the bench through the liquid: refracted, tinted, cloudier with depth.
		vec2 bend = n_view.xy * (LIQUID_IOR - 1.0) * refraction_strength * (FRONT_FACING ? 1.0 : 0.6);
		float blur = clamp(scatter * 5.0, 0.0, 4.0);
		vec3 behind = textureLod(screen_tex, SCREEN_UV - bend, blur).rgb;
		ALBEDO = tint * scatter * 0.9 + vec3(bubble * 0.5) + surface_color.rgb * meniscus * 0.25;
		EMISSION = behind * transmit * (1.0 - fresnel) + aura * (0.4 + 0.6 * (1.0 - transmit_avg))
			+ tint * caustic * transmit_avg * 0.25 + vec3(edge * 0.35) + vec3(bubble * 0.4);
		ALPHA = clamp(0.94 + meniscus * 0.06, 0.0, 1.0);
#else
		// No screen reads on mobile: darken by absorption, light only the scatter.
		float opacity = clamp(1.0 - transmit_avg, 0.0, 1.0);
		ALBEDO = mix(tint * 0.35, tint, scatter) * (0.4 + 0.6 * scatter) + vec3(bubble * 0.5) + surface_color.rgb * meniscus * 0.25;
		ALPHA = clamp(0.06 + opacity * 0.85 + scatter * 0.3 + fresnel * 0.4 + meniscus * 0.2 + bubble * 0.3, 0.0, 0.97);
		EMISSION = aura * (0.35 + 0.65 * opacity) + tint * caustic * (1.0 - opacity) * 0.2 + vec3(edge * 0.3);
		ALPHA = clamp(ALPHA + edge * 0.4 - shadow_band * 0.0, 0.0, 0.98);
#endif
		SPECULAR = FRONT_FACING ? 0.6 : 0.4;
		if (!FRONT_FACING && foam_thickness_meters > 0.0008) {
			// Looking down through a foam cap: foam, not liquid.
			ALBEDO = foam_color;
			EMISSION = vec3(0.0);
			ALPHA = 0.92;
			ROUGHNESS = 0.6;
		}
	}
}
