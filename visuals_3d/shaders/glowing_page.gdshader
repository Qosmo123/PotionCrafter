// Recipe page on the wall: aged parchment with a border of glowing runes that
// pulses gently once the recipe is known (glow_strength 0 = unlearned, dim).
// `flash` briefly brightens everything when a recipe is first discovered.
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D parchment : source_color, filter_linear_mipmap;
uniform vec4 glow_color : source_color = vec4(0.96, 0.82, 0.44, 1.0);
uniform float glow_strength = 1.0;
uniform float flash = 0.0;
uniform float seed = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 paper = texture(parchment, UV).rgb;
	float dim = mix(0.55, 1.0, clamp(glow_strength, 0.0, 1.0));
	ROUGHNESS = 0.85;
	// Border band of little rune glyphs: a grid of cells, each lit in a few
	// strokes (random bars), only inside a thin frame around the page.
	vec2 uv = UV;
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float band = smoothstep(0.02, 0.035, edge) * (1.0 - smoothstep(0.085, 0.1, edge));
	vec2 g = uv * vec2(14.0, 18.0);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float h = hash12(cell + seed);
	float bar_v = step(0.55, h) * (1.0 - smoothstep(0.08, 0.16, abs(f.x - 0.5)));
	float bar_h = step(0.35, fract(h * 7.3)) * (1.0 - smoothstep(0.08, 0.16, abs(f.y - fract(h * 3.1) * 0.6 - 0.2)));
	float rune = clamp(bar_v + bar_h, 0.0, 1.0) * band;
	float frame = 1.0 - smoothstep(0.0, 0.006, abs(edge - 0.11));
	float pulse = 0.75 + 0.25 * sin(TIME * 1.6 + seed * 3.0);
	float glow = (rune * 2.2 + frame * 0.8) * glow_strength * pulse + flash * (rune * 4.0 + 0.6);
	ALBEDO = mix(paper * dim, glow_color.rgb * 0.4, clamp(rune * glow_strength, 0.0, 1.0) * 0.5);
	EMISSION = glow_color.rgb * glow;
}
