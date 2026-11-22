// A heap of spilled powder: a matte cone of grains in the powder's colour.
// The surface is broken up by fine grain speckle and a few lumps, the slope
// is a little uneven (heaps are never perfect cones) and the foot fades into
// a thin scatter of loose grains on the bench.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

instance uniform vec4 powder_color : source_color = vec4(0.8, 0.78, 0.72, 1.0);
instance uniform float seed = 0.0;
instance uniform float height_m = 0.01;

varying vec3 world_pos;
varying float up;

float hash13(vec3 p) {
	p = fract(p * 0.1031 + seed * 0.013);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash13(vec3(i, 0.0));
	float b = hash13(vec3(i + vec2(1.0, 0.0), 0.0));
	float c = hash13(vec3(i + vec2(0.0, 1.0), 0.0));
	float d = hash13(vec3(i + vec2(1.0, 1.0), 0.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	// Lumpy slope: push vertices in and out a little around the cone.
	up = VERTEX.y + 0.5;  // 0 at the foot, 1 at the apex
	float ang = atan(VERTEX.z, VERTEX.x);
	float lump = (vnoise2(vec2(ang * 2.5 + seed, up * 3.0)) - 0.5) * 0.18 * (1.0 - up) * up * 4.0;
	VERTEX.xz *= 1.0 + lump;
	VERTEX.y += lump * 0.25;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Grains: fine speckle at sub-millimetre scale plus a coarser mottling.
	float fine = hash13(floor(world_pos * 2200.0));
	float coarse = vnoise2(world_pos.xz * 300.0 + seed) * 0.6 + vnoise2(world_pos.xz * 900.0) * 0.4;
	float shade = 0.72 + 0.22 * coarse + 0.16 * (fine - 0.5);
	// The foot is thinner, so the bench darkens it slightly.
	shade *= mix(0.86, 1.0, smoothstep(0.0, 0.25, up));
	vec3 c = powder_color.rgb * shade;
	// A rare bright grain (crystal facets catching the light).
	float glint = step(0.996, fine);
	ALBEDO = c + vec3(glint * 0.25);
	ROUGHNESS = 0.92 - glint * 0.5;
	SPECULAR = 0.2 + glint * 0.4;
	METALLIC = 0.0;
	// Bump from the grain speckle.
	NORMAL = normalize(NORMAL + vec3(fine - 0.5, coarse - 0.5, 0.0) * 0.18);
}
