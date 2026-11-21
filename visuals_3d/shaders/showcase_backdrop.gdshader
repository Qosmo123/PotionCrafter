// Backdrop card behind a hero-shot gem: a velvet gradient with a soft pool
// of light in the gem's colour and slowly drifting motes of dust.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.6, 0.3, 0.9, 1.0);
uniform vec4 deep : source_color = vec4(0.012, 0.008, 0.02, 1.0);
uniform float strength = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 p = UV - vec2(0.5, 0.55);
	float r = length(p * vec2(1.0, 1.25));
	vec3 col = deep.rgb;
	col += tint.rgb * 0.12 * strength * exp(-r * r * 11.0);
	col += vec3(1.0, 0.9, 0.75) * 0.05 * strength * exp(-r * r * 40.0);
	// Velvet nap: very fine vertical streaks.
	col *= 0.92 + 0.08 * hash(vec2(floor(UV.x * 900.0), 0.0));
	// Dust motes.
	vec2 g = UV * vec2(36.0, 22.0) + vec2(0.0, TIME * 0.12);
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5 - (vec2(hash(cell), hash(cell + 7.0)) - 0.5) * 0.7;
	float mote = smoothstep(0.06, 0.0, length(f)) * step(0.86, hash(cell + 3.0));
	col += vec3(1.0, 0.85, 0.6) * mote * 0.35 * strength * (0.5 + 0.5 * sin(TIME * 2.0 + hash(cell) * 6.28));
	ALBEDO = col;
}
