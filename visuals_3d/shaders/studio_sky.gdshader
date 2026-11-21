// Jeweller's studio for the hero shots: a deep violet room with a few bright
// softboxes and a warm window. Gems take their fire from what they reflect,
// so the softboxes are what make facets flash as the stone turns.
shader_type sky;

uniform vec3 base_color : source_color = vec3(0.018, 0.012, 0.03);
uniform vec3 floor_color : source_color = vec3(0.01, 0.007, 0.012);
uniform vec3 key_color : source_color = vec3(1.0, 0.92, 0.8);
uniform vec3 rim_color : source_color = vec3(0.55, 0.75, 1.0);
uniform float energy = 6.0;
uniform float turn = 0.0;  // slowly rotates the softboxes for moving glints

float softbox(vec3 dir, vec3 centre, vec2 half_size) {
	vec3 c = normalize(centre);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), c));
	vec3 up = cross(c, right);
	float facing = dot(dir, c);
	if (facing <= 0.0) return 0.0;
	vec2 p = vec2(dot(dir, right), dot(dir, up)) / facing;
	vec2 d = abs(p) - half_size;
	float box = 1.0 - smoothstep(0.0, 0.03, max(d.x, d.y));
	return box;
}

void sky() {
	vec3 dir = EYEDIR;
	float s = sin(turn), c = cos(turn);
	dir.xz = mat2(vec2(c, -s), vec2(s, c)) * dir.xz;
	float h = dir.y;
	vec3 col = mix(floor_color, base_color, smoothstep(-0.2, 0.25, h));
	// Faint vertical glow behind the stage.
	col += base_color * 2.0 * exp(-abs(h) * 4.0);
	col += key_color * energy * softbox(dir, vec3(-0.7, 0.8, 0.5), vec2(0.35, 0.22));
	col += key_color * energy * 0.6 * softbox(dir, vec3(0.8, 0.45, 0.6), vec2(0.12, 0.45));
	col += rim_color * energy * 0.7 * softbox(dir, vec3(0.2, 0.6, -1.0), vec2(0.5, 0.08));
	col += rim_color * energy * 0.35 * softbox(dir, vec3(-0.9, 0.2, -0.6), vec2(0.06, 0.3));
	col += vec3(1.0, 0.6, 0.3) * energy * 0.25 * softbox(dir, vec3(0.0, -0.3, 1.0), vec2(0.4, 0.04));
	COLOR = col;
}
