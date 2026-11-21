// Opaque gemstone (tiger eye, star sapphire, opal, malachite...): same phenomena,
// drawn in the opaque pass on both PC and mobile.
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;
#define GEM_OPAQUE
#include "res://visuals_3d/shaders/gem_common.gdshaderinc"
