// Sealing wax over a bottle's cork and neck. While it is poured the wax runs
// down (vertices below `flow_y` are held at the flow front) and glows hot,
// then cools to a glossy, slightly translucent finish. The signet medallion
// uses the same shader with an embossed emblem normal map.
shader_type spatial;
render_mode cull_back;

uniform sampler2D emblem_tex : hint_normal, filter_linear_mipmap;
uniform float emblem_strength = 0.0;
instance uniform vec3 wax_color : source_color = vec3(0.55, 0.06, 0.05);
instance uniform float flow_y = -10.0;
instance uniform float heat = 0.0;
instance uniform float metal = 0.0;

varying vec3 local_pos;

void vertex() {
	VERTEX.y = max(VERTEX.y, flow_y);
	local_pos = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	// Faint mottling, as real wax is never perfectly even.
	float mottle = hash3(floor(local_pos * 900.0)) * 0.06;
	vec3 c = wax_color * (0.94 + mottle);
	ALBEDO = c;
	METALLIC = metal;
	ROUGHNESS = mix(mix(0.3, 0.42, mottle * 8.0), 0.12, heat);
	SPECULAR = 0.5;
	if (emblem_strength > 0.0) {
		NORMAL_MAP = texture(emblem_tex, UV).rgb;
		NORMAL_MAP_DEPTH = emblem_strength;
	}
	// Molten wax glows, then cools through deep orange back to its colour.
	ALBEDO = mix(c, vec3(0.9, 0.32, 0.06), heat * 0.6);
	EMISSION = vec3(1.0, 0.3, 0.05) * heat * heat * 0.7 + c * heat * 0.3;
	// Thin wax lets a little warm light through at grazing angles.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += c * rim * 0.12;
}
