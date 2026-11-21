// Mobile tier gemstone: no screen-texture grab (tile-flush safe); alpha-blended
// Fresnel + faked transmission + facet sparkle.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, specular_schlick_ggx;
#include "res://visuals_3d/shaders/gem_common.gdshaderinc"
