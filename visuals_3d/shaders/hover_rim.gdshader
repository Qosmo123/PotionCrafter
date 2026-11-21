// Soft warm rim glow drawn over whatever the pointer is hovering, so it is
// clear what a click will pick up. Used as a material overlay.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 rim_color : source_color = vec3(1.0, 0.8, 0.45);
uniform float strength = 0.55;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float breathe = 0.85 + 0.15 * sin(TIME * 4.0);
	ALBEDO = rim_color * rim * strength * breathe;
}
