class_name QualityTier
extends RefCounted
## Runtime PC (Forward+) vs Android (Mobile renderer) quality switch.


static func is_mobile_tier() -> bool:
	return OS.has_feature("mobile") or RenderingServer.get_current_rendering_method() == "mobile"


## Pick the material variant for the active tier. Never returns a screen-texture
## glass material on the mobile tier.
static func pick_material(pc_material: Material, mobile_material: Material) -> Material:
	return mobile_material if is_mobile_tier() else pc_material
