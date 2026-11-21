// Leather-bound book cover. The 4K leather set gives the grain; the spine
// (vertex COLOR.r) adds raised-band wear (COLOR.g is the band profile), gilt
// rules beside each band, a title label with a gilt border and stamped
// lettering, and small gilt ornaments in the other panels. Per-book colour,
// panel count and seed are instance uniforms, so every book shares one material.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_meters = 0.12;
uniform vec3 gilt_color : source_color = vec3(0.95, 0.72, 0.3);
// Books sit in the background: a little darker and less saturated so the
// workbench in front stands out.
uniform float background_shade = 0.78;
uniform float background_desaturate = 0.18;
instance uniform vec3 base_color : source_color = vec3(0.35, 0.06, 0.05);
instance uniform vec3 label_color : source_color = vec3(0.05, 0.04, 0.04);
instance uniform float seed = 0.0;
instance uniform float panels = 4.0;
instance uniform float aspect = 1.2;

varying float book_seed;

void vertex() {
	book_seed = seed;
}

float hash21(vec2 p, float sd) {
	p = fract(p * vec2(123.34, 456.21) + sd * 0.37);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p, float sd) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i, sd), hash21(i + vec2(1.0, 0.0), sd), f.x), mix(hash21(i + vec2(0.0, 1.0), sd), hash21(i + vec2(1.0, 1.0), sd), f.x), f.y);
}

void fragment() {
	float sd = book_seed;
	vec2 tuv = UV2 / tile_meters;
	vec3 grain = texture(albedo_tex, tuv).rgb;
	float spine = COLOR.r;
	float band = COLOR.g;
	float s = UV.x;
	float v = UV.y;
	float scuff = vnoise(UV2 * 160.0, sd) * 0.6 + vnoise(UV2 * 45.0, sd) * 0.4;

	vec3 col = base_color * grain * 1.25;
	// Rubbed lighter on the raised bands, along the joints and at head and tail.
	float joint = spine * (1.0 - smoothstep(0.0, 0.14, min(s, 1.0 - s)));
	float ends = 1.0 - smoothstep(0.0, 0.035, min(v, 1.0 - v));
	float rub = clamp(band * 0.7 + joint * 0.5 + ends * 0.6, 0.0, 1.0) * smoothstep(0.25, 0.7, scuff);
	col = mix(col, col * 1.7 + vec3(0.05, 0.035, 0.02), rub * 0.6);
	// Grime settling in the creases beside each band.
	float crease = smoothstep(0.02, 0.12, band) * (1.0 - smoothstep(0.12, 0.3, band));
	col *= 1.0 - crease * 0.3 * spine;

	float gilt = 0.0;
	float pv = v * panels;
	float pi = floor(pv);
	vec2 q = vec2(s * 2.0 - 1.0, (fract(pv) * 2.0 - 1.0) * aspect);
	float in_width = 1.0 - smoothstep(0.8, 0.86, abs(q.x));
	// Gilt rules just clear of each raised band.
	float rule_d = abs(abs(q.y) - (aspect - 0.2));
	gilt = max(gilt, (1.0 - smoothstep(0.03, 0.06, rule_d)) * in_width);
	bool is_label = abs(pi - (panels - 2.0)) < 0.5;
	if (is_label) {
		vec2 box = vec2(0.8, aspect - 0.34);
		vec2 d = abs(q) - box;
		float inside = 1.0 - smoothstep(-0.02, 0.02, max(d.x, d.y));
		col = mix(col, label_color * (0.8 + grain * 0.4), inside * spine);
		float border = 1.0 - smoothstep(0.03, 0.06, abs(max(d.x, d.y) + 0.1));
		gilt = max(gilt, border * inside);
		// Stamped lettering: lines of little blocks.
		float ly = (q.y / box.y * 0.5 + 0.5) * 4.0;
		float lx = (q.x / box.x * 0.5 + 0.5) * 7.0;
		float line = floor(ly);
		float lf = fract(ly);
		float cf = fract(lx);
		float glyph = step(0.3, hash21(vec2(floor(lx), line + pi * 7.0), sd)) * step(0.22, lf) * step(lf, 0.72) * step(0.12, cf) * step(cf, 0.88);
		float text_zone = step(0.5, line) * step(line, 2.5) * step(abs(q.x), box.x - 0.2);
		gilt = max(gilt, glyph * text_zone * inside);
	} else {
		float kind = hash21(vec2(pi, 3.0), sd);
		float r = length(q);
		float diamond = abs(q.x) + abs(q.y);
		if (kind < 0.35) {
			gilt = max(gilt, 1.0 - smoothstep(0.05, 0.09, abs(diamond - 0.5)));
			gilt = max(gilt, 1.0 - smoothstep(0.1, 0.14, r));
		} else if (kind < 0.65) {
			gilt = max(gilt, 1.0 - smoothstep(0.04, 0.08, abs(r - 0.45)));
			gilt = max(gilt, (1.0 - smoothstep(0.05, 0.09, min(abs(q.x), abs(q.y)))) * step(r, 0.3));
		} else if (kind < 0.85) {
			float a = atan(q.y, q.x);
			gilt = max(gilt, 1.0 - smoothstep(0.0, 0.06, r - 0.22 - 0.2 * abs(cos(a * 3.0))));
		}
	}
	// Old gilt flakes away in patches.
	gilt *= spine * smoothstep(0.18, 0.4, scuff) * (1.0 - band * 0.5);

	vec3 albedo = mix(col, gilt_color, gilt);
	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(albedo, vec3(luma), background_desaturate) * background_shade;
	METALLIC = gilt;
	ROUGHNESS = mix(texture(rough_tex, tuv).r, 0.32, gilt);
	NORMAL_MAP = texture(normal_tex, tuv).rgb;
	NORMAL_MAP_DEPTH = 1.0 - gilt * 0.5;
}
