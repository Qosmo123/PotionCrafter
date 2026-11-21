// A pouring stream drawn as one continuous ribbon. The strip mesh carries
// only (side, t); the vertex shader lays it along the real falling arc
// p(tau) = p0 + v0*tau + g*tau^2/2 and narrows it as the liquid speeds up
// (continuity: width ~ 1/sqrt(speed)). It always faces the camera and is
// shaded as a rounded, glossy rope with streaks flowing down it. Syrups stay
// thick and smooth; thin liquids neck and ripple slightly.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec3 start_point = vec3(0.0);
instance uniform vec3 start_velocity = vec3(0.0, -0.3, 0.0);
instance uniform float duration = 0.2;
instance uniform float start_width = 0.006;
instance uniform vec4 liquid_color : source_color = vec4(0.6, 0.75, 0.9, 0.6);
instance uniform float viscosity = 0.0;
instance uniform float glow = 0.0;
uniform float gravity = 9.81;

varying float side_v;
varying float along;

void vertex() {
	float t = UV.y;
	float side = UV.x * 2.0 - 1.0;
	float tau = t * duration;
	vec3 g = vec3(0.0, -gravity, 0.0);
	vec3 p = start_point + start_velocity * tau + 0.5 * g * tau * tau;
	vec3 vel = start_velocity + g * tau;
	float speed = max(length(vel), 0.05);
	// Thin liquids neck and ripple; viscous ones stay a smooth rope. Streams
	// narrow as they speed up, but surface tension keeps them from going
	// thread-thin (syrups hardly narrow at all).
	float runny = 1.0 - clamp(viscosity * 2.0, 0.0, 1.0);
	float narrowing = sqrt(max(length(start_velocity), 0.05) / speed);
	float w = start_width * max(narrowing, mix(0.8, 0.45, runny));
	w *= 1.0 + runny * 0.05 * sin(t * 18.0 - TIME * 22.0);
	// Rounded start at the lip, slight taper at the end.
	w *= smoothstep(0.0, 0.035, t) * 0.75 + 0.25;
	vec3 tangent = normalize(vel);
	vec3 view_fwd = -normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 side_dir = normalize(cross(tangent, view_fwd));
	vec3 world = p + side_dir * side * w * 0.5;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	vec3 toward_cam = -view_fwd;
	vec3 n = normalize(toward_cam * sqrt(max(1.0 - side * side, 0.0)) + side_dir * side);
	NORMAL = (inverse(MODEL_MATRIX) * vec4(n, 0.0)).xyz;
	side_v = side;
	along = t;
}

void fragment() {
	float edge = abs(side_v);
	float flow = TIME * mix(3.0, 0.6, clamp(viscosity, 0.0, 1.0));
	float streak = 0.88 + 0.12 * sin(along * 70.0 - flow * 25.0 + side_v * 2.5);
	// Clear liquids (water, spirits) are drawn as bright glassy threads so
	// they still read against the bench; coloured ones by their body.
	float clear_amount = 1.0 - clamp(liquid_color.a * 1.6, 0.0, 1.0);
	vec3 c = mix(liquid_color.rgb, vec3(0.86, 0.93, 1.0), clear_amount * 0.6);
	// A bright highlight line just off the centre, like light down a stream.
	float glint = pow(1.0 - clamp(abs(side_v + 0.3) * 2.4, 0.0, 1.0), 3.0);
	ALBEDO = c * streak + vec3(glint * (0.25 + clear_amount * 0.45));
	float body = max(clamp(liquid_color.a, 0.0, 1.0), 0.42);
	ALPHA = clamp(mix(body * 0.75 + 0.12, body + 0.32, smoothstep(0.5, 1.0, edge)) + glint * 0.25, 0.0, 0.95);
	ALPHA *= smoothstep(1.0, 0.985, along) * smoothstep(0.0, 0.01, along);
	ROUGHNESS = mix(0.04, 0.2, clamp(viscosity, 0.0, 1.0));
	SPECULAR = 0.85;
	METALLIC = 0.0;
	EMISSION = c * glow;
}
