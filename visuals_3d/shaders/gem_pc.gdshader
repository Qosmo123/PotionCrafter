// PC tier (Forward+) gemstone: screen-texture refraction with dispersion fire.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, specular_schlick_ggx;
#define GEM_SCREEN_REFRACTION
#include "res://visuals_3d/shaders/gem_common.gdshaderinc"
