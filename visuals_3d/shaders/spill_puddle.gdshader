// A puddle of spilled liquid on the bench: a thin, glossy film in the
// liquid's colour with an irregular, organic outline, a slightly darker wet
// rim where it soaks the wood, and a faint ripple when it is freshly fed.
// Drawn on a flat quad; UV 0..1 across the puddle.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

instance uniform vec4 liquid_color : source_color = vec4(0.6, 0.75, 0.9, 0.6);
instance uniform float seed = 0.0;
// 0..1: how freshly fed (ripples, gloss); fades as it settles.
instance uniform float fresh = 0.0;
// 0..1: how dried out (shrinks the film, leaves a faint stain ring).
instance uniform float dry = 0.0;

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

float wobble(float a) {
	// Smooth random outline from a few angular harmonics.
	float r = 0.0;
	for (int k = 1; k <= 5; k++) {
		float fk = float(k);
		r += (hash(fk) - 0.5) * 0.32 / fk * sin(a * fk + hash(fk + 9.0) * 6.2831);
	}
	return r;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	float edge = 0.78 + wobble(a) - dry * 0.25;
	float d = length(p) / max(edge, 0.05);
	if (d > 1.12) {
		discard;
	}
	float film = 1.0 - smoothstep(0.86, 1.0, d);
	float rim = smoothstep(0.7, 0.98, d) * (1.0 - smoothstep(1.0, 1.12, d));
	float ripple = fresh * 0.5 * (0.5 + 0.5 * sin(d * 40.0 - TIME * 9.0)) * film;
	vec3 base = liquid_color.rgb;
	// Thin film: mostly see-through, deeper colour toward the middle.
	float depth = film * (0.55 + 0.45 * (1.0 - d));
	ALBEDO = mix(base * 0.35, base, depth) + ripple * 0.06;
	ALPHA = clamp(liquid_color.a * depth * (1.0 - dry * 0.6) + rim * 0.22, 0.0, 0.92);
	ROUGHNESS = mix(0.04, 0.3, dry) + rim * 0.4;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	NORMAL = normalize(NORMAL + vec3(0.0, 0.0, ripple * 0.15));
}
