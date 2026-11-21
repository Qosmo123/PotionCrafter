// Glowing fracture overlay for rocks being hammered (material_overlay pass).
// Cellular cracks in object space spread and widen as `damage` rises, with
// light "peeking through" in the colour of what's hidden inside. Additive and
// unshaded: no screen reads, so it is safe on the mobile tier too.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.75, 0.35, 1.0);
uniform float energy = 3.0;
uniform float cell_scale = 90.0;
uniform float seed = 0.0;

varying vec3 obj_pos;

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p + seed) * 43758.5453);
}

// Returns (F2 - F1, hash of nearest cell).
vec2 voronoi_edge(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 h = hash3(i + g);
		vec3 r = g + h - f;
		float d = dot(r, r);
		if (d < f1) { f2 = f1; f1 = d; id = h.x; }
		else if (d < f2) { f2 = d; }
	}
	return vec2(sqrt(f2) - sqrt(f1), id);
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	if (damage <= 0.001 && flash <= 0.001) {
		discard;
	}
	vec2 v = voronoi_edge(obj_pos * cell_scale);
	// More of the cell network "opens" as damage grows; cracks widen too.
	float open = step(v.y, damage * 1.15);
	float width = mix(0.02, 0.11, damage);
	float crack = smoothstep(width, 0.0, v.x) * open;
	float pulse = 0.75 + 0.25 * sin(TIME * 9.0 + v.y * 20.0);
	vec3 c = glow_color.rgb * crack * energy * (pulse * damage + flash * 2.0);
	ALBEDO = c;
}
