// Frosted glass for UI panels (PC tier only, assigned by CosmicTheme.frost()).
// The panel's own translucent fill is composited over a mip-blurred copy of
// the screen behind it; borders and filigree (high alpha) stay crisp. Child
// controls keep their own material, so text is never blurred.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 6.0) = 3.2;
uniform float saturation : hint_range(0.0, 1.5) = 0.7;

void fragment() {
	vec4 c = COLOR;
	if (c.a > 0.004 && c.a < 0.97) {
		vec3 bg = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
		float luma = dot(bg, vec3(0.299, 0.587, 0.114));
		bg = mix(vec3(luma), bg, saturation);
		COLOR.rgb = mix(bg, c.rgb, c.a);
		COLOR.a = smoothstep(0.0, 0.1, c.a);
	}
}
