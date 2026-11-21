// A soft beam of window light for the 2.5D side view (volumetric fog is off
// with the orthographic camera, so beams are faked). QuadMesh: UV.x across,
// UV.y along the beam (0 = window end). The beam widens as it travels,
// carries slow drifting streaks, and fades softly where it meets surfaces
// (scene depth), so there are no hard intersection lines.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 beam_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float spread = 1.8;
uniform float soft_fade_meters = 0.12;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
instance uniform float strength = 0.1;
instance uniform float phase = 0.0;

varying float frag_view_z;

void vertex() {
	VERTEX.x *= mix(1.0, spread, UV.y);
	frag_view_z = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

float wave(float x) {
	return 0.5 + 0.5 * sin(x);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float edge = smoothstep(0.0, 0.55, across);
	float along = smoothstep(0.0, 0.2, UV.y) * (1.0 - smoothstep(0.7, 1.0, UV.y));
	float t = TIME * 0.05 + phase;
	float streaks = 0.65 + 0.35 * (wave(UV.x * 23.0 + t * 7.0) * 0.6 + wave(UV.x * 51.0 - t * 11.0 + 1.7) * 0.4);
	float breathe = 0.85 + 0.15 * wave(TIME * 0.4 + phase * 3.0);

	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	float scene_z = view.z / view.w;
	float soft = clamp((frag_view_z - scene_z) / soft_fade_meters, 0.0, 1.0);

	ALBEDO = beam_color * edge * along * streaks * breathe * soft * strength;
}
