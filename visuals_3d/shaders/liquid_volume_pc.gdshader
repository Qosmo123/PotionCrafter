// Analytical 3D liquid volume, PC tier (Forward+): the bench behind is
// refracted and tinted through the liquid. See liquid_common.gdshaderinc.
shader_type spatial;
#define LIQUID_SCREEN_REFRACTION
#include "res://visuals_3d/shaders/liquid_common.gdshaderinc"
