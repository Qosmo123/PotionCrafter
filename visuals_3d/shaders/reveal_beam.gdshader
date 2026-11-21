// Pillar of light for a rare find: soft vertical beam that fades with height
// and over its lifetime (`life` 1 -> 0). Additive, unshaded, mobile-safe.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.96, 0.82, 0.44, 1.0);
uniform float life : hint_range(0.0, 1.0) = 1.0;
uniform float energy = 2.5;

void fragment() {
	float h = UV.y;              // 0 at top, 1 at bottom on CylinderMesh
	float fade = smoothstep(0.0, 0.9, h) * smoothstep(1.0, 0.92, h);
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float shimmer = 0.8 + 0.2 * sin(TIME * 14.0 + h * 30.0);
	ALBEDO = color.rgb * energy * fade * (1.0 - rim * 0.7) * shimmer * life;
}
