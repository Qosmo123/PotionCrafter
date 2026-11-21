// Jeweller's loupe inset: a round lens view with a little barrel bulge,
// colour fringing and vignette at the rim, a brass bezel, and a progress arc
// around the bezel tinted by how steady the hand is.
shader_type canvas_item;

uniform float progress = 0.0;
uniform vec4 arc_color : source_color = vec4(0.36, 0.88, 0.6, 1.0);
uniform vec4 brass : source_color = vec4(0.83, 0.62, 0.3, 1.0);
uniform float alpha = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float lens_r = 0.84;
	// Barrel bulge and slight chromatic split toward the rim.
	vec2 q = p * (1.0 - 0.12 * r * r);
	vec2 uv = q * 0.5 / 1.0 + 0.5;
	float split = 0.006 * r * r;
	vec3 col;
	col.r = texture(TEXTURE, uv + q * split).r;
	col.g = texture(TEXTURE, uv).g;
	col.b = texture(TEXTURE, uv - q * split).b;
	col *= 1.0 - 0.55 * smoothstep(0.45, lens_r, r);
	// Glass glint across the top of the lens.
	col += vec3(1.0) * 0.06 * smoothstep(0.5, 0.0, length(p - vec2(-0.35, -0.45))) ;
	float in_lens = 1.0 - smoothstep(lens_r - 0.006, lens_r + 0.006, r);
	// Bezel: brass ring with a bevel.
	float bezel = smoothstep(lens_r - 0.004, lens_r + 0.004, r) * (1.0 - smoothstep(0.99, 1.0, r));
	float bevel = 0.65 + 0.35 * sin((r - lens_r) / (1.0 - lens_r) * 3.14159);
	float light = 0.75 + 0.25 * dot(normalize(p + 1e-4), normalize(vec2(-0.6, -0.8)));
	vec3 ring = brass.rgb * bevel * light;
	// Progress arc running clockwise from the top, inside the bezel.
	float ang = atan(p.x, -p.y);
	float a01 = fract(ang / 6.28318 + 1.0);
	float band = smoothstep(0.88, 0.895, r) * (1.0 - smoothstep(0.945, 0.96, r));
	float filled = step(a01, progress);
	ring = mix(ring, mix(ring * 0.45, arc_color.rgb * 1.4, filled), band * 0.9);
	vec3 outc = mix(col, ring, bezel);
	float a = max(in_lens, bezel) * alpha;
	COLOR = vec4(outc, a);
}
