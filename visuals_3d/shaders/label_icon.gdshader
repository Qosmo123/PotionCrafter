// Category stamp on a bottle label: a filled round badge with a simple
// shape knocked out of it. icon: 0 droplet (liquid), 1 crystal (powder),
// 2 warning triangle (strong acid/base), 3 star (arcane), 4 berry (juice).
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, shadows_disabled;

uniform int icon = 0;
uniform vec4 tint : source_color = vec4(0.2, 0.55, 0.6, 1.0);
uniform vec4 ink : source_color = vec4(0.95, 0.91, 0.82, 1.0);

float sd_circle(vec2 p, float r) { return length(p) - r; }

float sd_triangle(vec2 p, float r) {
	const float k = sqrt(3.0);
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
}

float sd_rhombus(vec2 p, vec2 b) {
	p = abs(p);
	float h = clamp((-2.0 * dot(p, b) + dot(b, b)) / dot(b, b), -1.0, 1.0);
	float d = length(p - 0.5 * b * vec2(1.0 - h, 1.0 + h));
	return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

float sd_star(vec2 p, float r) {
	// Five-pointed star (Inigo Quilez).
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = 0.45 * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float badge = sd_circle(p, 0.92);
	float shape;
	if (icon == 0) {
		// Droplet: circle plus a point on top.
		shape = min(sd_circle(p + vec2(0.0, 0.15), 0.38), sd_triangle(vec2(p.x, p.y - 0.18) * vec2(1.0, 0.9), 0.32));
	} else if (icon == 1) {
		shape = sd_rhombus(p, vec2(0.36, 0.55));
	} else if (icon == 2) {
		shape = sd_triangle(p + vec2(0.0, 0.08), 0.5);
	} else if (icon == 3) {
		shape = sd_star(p, 0.55);
	} else {
		shape = min(sd_circle(p + vec2(0.0, 0.08), 0.42), sd_circle(p - vec2(0.12, 0.42), 0.12));
	}
	float aa = 0.06;
	float in_badge = 1.0 - smoothstep(-aa, aa, badge);
	float in_shape = 1.0 - smoothstep(-aa, aa, shape);
	ALBEDO = mix(tint.rgb, ink.rgb, in_shape);
	ALPHA = in_badge;
}
