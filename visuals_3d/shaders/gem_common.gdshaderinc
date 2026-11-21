// Shared true-to-life gemstone shading. Included by gem_pc / gem_mobile / gem_opaque.
//  * Schlick Fresnel from the stone's real refractive index (diamond 2.42 is
//    much more mirror-like than quartz 1.55).
//  * Facet scintillation: the internally refracted view ray is bucketed into
//    virtual pavilion facets, so tilting the stone makes facets blink on/off,
//    and dispersion splits each blink into spectral "fire".
//  * Beer-Lambert body colour that deepens with path length through the stone.
//  * Phenomena: asterism (6-ray star), chatoyancy (cat's eye), play of colour,
//    adularescence, colour change, iridescence, fluorescence, double
//    refraction and aventurescence.
//  * PC (GEM_SCREEN_REFRACTION): background seen *through* the stone with
//    per-channel offsets; mobile fakes transmission without screen grabs.

uniform vec3 body_color : source_color = vec3(0.8);
uniform vec3 alt_color : source_color = vec3(0.8);
uniform float clarity : hint_range(0.0, 1.0) = 0.8;
uniform float ior = 1.55;
uniform float dispersion = 0.013;
uniform float polish : hint_range(0.0, 1.0) = 1.0;
uniform float faceted : hint_range(0.0, 1.0) = 0.0;
uniform int phenomenon = 0;
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow_energy = 0.0;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float inclusion_amount : hint_range(0.0, 1.0) = 0.15;
uniform float size_meters = 0.01;
uniform float seed = 0.0;

#ifdef GEM_SCREEN_REFRACTION
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
#endif

varying vec3 obj_pos;
varying vec3 obj_normal;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

float fbm3(vec3 p) {
	return vnoise3(p) * 0.55 + vnoise3(p * 2.1) * 0.3 + vnoise3(p * 4.3) * 0.15;
}

vec3 spectrum(float h) {
	return clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

// Brightness of a ray across virtual facets; one bucket lookup per channel
// with the ray bent slightly differently per wavelength = fire.
float facet_flash(vec3 dir) {
	vec3 cell = floor(dir * 5.0 + seed * 3.17);
	float h = hash13(cell);
	return smoothstep(0.55, 0.95, h);
}

// Phenomenon light along great circles through the highlight (object space).
float star_rays(vec3 n, vec3 h, int rays) {
	vec3 d = n - h;
	float s = 0.0;
	for (int i = 0; i < 3; i++) {
		if (i >= rays) break;
		float a = float(i) * 1.0472;
		vec3 axis = vec3(cos(a), 0.0, sin(a));
		float along = dot(d, axis);
		float perp = length(d - along * axis);
		s += exp(-perp * perp * 900.0) * exp(-along * along * 2.5);
	}
	return s;
}

void vertex() {
	obj_pos = VERTEX / max(size_meters, 0.001);
	obj_normal = NORMAL;
}

void fragment() {
	mat3 to_obj = transpose(mat3(MODEL_MATRIX));
	vec3 v_obj = normalize(to_obj * (mat3(INV_VIEW_MATRIX) * VIEW));
	vec3 n_obj = normalize(obj_normal);
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.001, 1.0);
	float f0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
	float fresnel = f0 + (1.0 - f0) * pow(1.0 - n_dot_v, 5.0);

	// Body colour: deeper through thick parts (grazing), paler face-up.
	float path = mix(0.8, 2.6, 1.0 - n_dot_v);
	vec3 tint = pow(max(body_color, vec3(0.002)), vec3(path * mix(1.6, 0.8, clarity)));
	vec3 body = body_color;
	if (phenomenon == 5) {
		// Colour change / pleochroism: the hue swings with viewing angle.
		float k = smoothstep(0.25, 0.85, 0.5 + 0.5 * sin(dot(v_obj, vec3(2.3, 1.1, -1.7)) * 2.5 + seed));
		body = mix(body_color, alt_color, k);
		tint = pow(max(body, vec3(0.002)), vec3(path * mix(1.6, 0.8, clarity)));
	}

	// Inclusions: soft clouds, silk and "jardin" inside less-than-perfect stones.
	float cloud = smoothstep(0.52, 0.8, fbm3(obj_pos * 2.6 + seed));
	float incl = inclusion_amount * cloud;

	// Internal facet scintillation and fire.
	vec3 refr = refract(-v_obj, n_obj, 1.0 / ior);
	vec3 fire_rgb = vec3(
		facet_flash(refr * (1.0 - dispersion * 4.0)),
		facet_flash(refr),
		facet_flash(refr * (1.0 + dispersion * 4.0)));
	float fire_amount = clamp(dispersion * 22.0, 0.0, 1.0);
	vec3 sparkle = mix(vec3(fire_rgb.g), fire_rgb, fire_amount) * faceted * polish * clarity;
	sparkle *= mix(tint * 1.4 + 0.15, vec3(1.0), fire_amount * 0.6);

	vec3 transmitted;
#ifdef GEM_SCREEN_REFRACTION
	// Gems bend light hard: the background is strongly displaced and broken up.
	vec2 bend = NORMAL.xy * (ior - 1.0) * 0.14;
	float lod = (1.0 - polish) * 3.5 + incl * 2.0;
	vec3 bg;
	bg.r = textureLod(screen_texture, SCREEN_UV - bend * (1.0 + dispersion * 6.0), lod).r;
	bg.g = textureLod(screen_texture, SCREEN_UV - bend, lod).g;
	bg.b = textureLod(screen_texture, SCREEN_UV - bend * (1.0 - dispersion * 6.0), lod).b;
	if (phenomenon == 8) {
		// Birefringence: a second, displaced image (Iceland spar "double vision").
		vec3 bg2 = textureLod(screen_texture, SCREEN_UV - bend - vec2(0.012, 0.004), lod).rgb;
		bg = mix(bg, bg2, 0.5);
	}
	transmitted = bg * tint * (1.0 - incl * 0.7);
#else
	transmitted = tint * (0.18 + 0.25 * (1.0 - n_dot_v)) * (1.0 - incl * 0.5);
#endif

	// Total internal reflection: most light entering a well-cut gem bounces
	// around inside and comes back out through the crown, carrying body colour
	// in a mosaic of bright and dark virtual facets.
	vec3 bounce = reflect(refr, normalize(vec3(sin(seed), -1.6, cos(seed))));
	float mosaic = 0.1 + 0.9 * facet_flash(bounce * 1.3 + 0.5);
	float tir = mix(0.35, 1.0, faceted) * mosaic * clamp((ior - 1.3) * 1.4, 0.15, 1.2);
	vec3 internal = tint * tir * (0.55 + 0.45 * polish);
#ifdef GEM_SCREEN_REFRACTION
	vec3 emit = (transmitted * 0.55 + internal * 0.7) * clarity;
#else
	vec3 emit = (transmitted + internal * 0.6) * clarity;
#endif
	emit += sparkle * 0.9;
	emit += glow_color * glow_energy;

	// Light direction proxy for phenomena: the half vector of a fixed key light
	// above the bench and the viewer, in object space.
	vec3 key_obj = normalize(to_obj * vec3(0.3, 1.0, 0.4));
	vec3 h_obj = normalize(key_obj + v_obj);
	if (phenomenon == 1) {
		emit += vec3(1.0, 0.98, 0.95) * star_rays(n_obj, h_obj, 3) * (0.4 + polish) * 0.9;
	} else if (phenomenon == 2) {
		emit += vec3(1.0, 0.95, 0.8) * star_rays(n_obj, h_obj, 1) * (0.4 + polish) * 1.1;
	} else if (phenomenon == 3) {
		// Play of colour: patches of diffraction colour that flash with angle.
		vec3 cellp = floor(obj_pos * 4.0 + vnoise3(obj_pos * 3.0) * 1.5 + seed);
		float hc = hash13(cellp);
		float flash = smoothstep(0.45, 0.9, hash13(cellp + floor(v_obj * 3.0 + 7.0)));
		emit += spectrum(hc + dot(v_obj, vec3(0.7, 0.4, 0.2))) * flash * (0.2 + polish * 0.4);
	} else if (phenomenon == 4) {
		// Adularescence: billowy blue sheen floating under the surface.
		float billow = smoothstep(0.35, 0.95, dot(n_obj, h_obj)) * (0.6 + 0.4 * fbm3(obj_pos * 3.0 + v_obj * 2.0));
		emit += vec3(0.55, 0.7, 1.0) * billow * 0.7;
	} else if (phenomenon == 6) {
		// Thin-film iridescence (bismuth, bornite, labradorite flash).
		float film = n_dot_v * 2.2 + fbm3(obj_pos * 4.0) * 1.5 + seed;
		body = mix(body, spectrum(film), 0.7);
		emit += spectrum(film) * 0.12 * smoothstep(0.2, 0.8, dot(n_obj, h_obj));
	} else if (phenomenon == 7) {
		emit += body * 0.08;
	} else if (phenomenon == 9) {
		// Aventurescence: tiny reflective platelets glittering inside.
		vec3 gp = floor(obj_pos * 26.0 + seed);
		float g = hash13(gp);
		float tw = step(0.93, hash13(gp + floor(v_obj * 9.0)));
		emit += mix(vec3(1.0), body * 1.6, 0.4) * step(0.6, g) * tw * 1.2;
	}

	ALBEDO = mix(body, body * 0.12, clarity) * (1.0 - metallic_amount * 0.2);
	EMISSION = emit;
	ROUGHNESS = mix(0.65, 0.025, polish);
	METALLIC = metallic_amount;
	SPECULAR = clamp(f0 / 0.08 * 0.5, 0.2, 1.0);
#ifndef GEM_OPAQUE
#ifdef GEM_SCREEN_REFRACTION
	ALPHA = mix(1.0, 0.92, clarity);
#else
	ALPHA = mix(1.0, clamp(0.5 + fresnel * 0.5, 0.0, 1.0), clarity);
#endif
#endif
}
