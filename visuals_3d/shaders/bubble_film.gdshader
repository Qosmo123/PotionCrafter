// Soap-bubble thin film: interference colours from film thickness and view
// angle (constructive wavelength shifts with optical path 2*n*d*cos(theta)),
// mostly transparent with a strong Fresnel rim. Each particle gets its own
// thickness phase from INSTANCE_CUSTOM.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;

uniform float film_thickness_nm = 420.0;
uniform float thickness_variation_nm = 260.0;
uniform float film_ior = 1.33;

varying float phase;

void vertex() {
	phase = INSTANCE_CUSTOM.x;
}

void fragment() {
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Film thins toward the top as it drains, plus a slow swirl.
	float d = film_thickness_nm + thickness_variation_nm * (sin(phase * 31.0 + UV.y * 6.0 + TIME * 0.7) * 0.5 + UV.y * 0.5 - 0.25);
	float cos_t = sqrt(1.0 - (1.0 - n_dot_v * n_dot_v) / (film_ior * film_ior));
	float path_nm = 2.0 * film_ior * d * cos_t;
	vec3 wavelengths = vec3(650.0, 530.0, 440.0);
	vec3 interference = 0.5 + 0.5 * cos(6.2831853 * path_nm / wavelengths);
	float fresnel = 0.04 + 0.96 * pow(1.0 - n_dot_v, 4.0);
	ALBEDO = interference * 0.25;
	EMISSION = interference * fresnel * 0.6;
	ALPHA = clamp(0.04 + fresnel * 0.75, 0.0, 0.85);
	ROUGHNESS = 0.02;
	SPECULAR = 0.8;
}
