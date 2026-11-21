class_name AudioHaptics
extends RefCounted
## Velocity-mapped haptic feedback. Procedural impact audio will hook in here too.

const MIN_IMPACT_SPEED_M_S: float = 0.35


## Short haptic tick scaled by impact speed (Android only; no-op elsewhere).
static func impact(relative_speed_m_s: float) -> void:
	if relative_speed_m_s < MIN_IMPACT_SPEED_M_S or not OS.has_feature("android"):
		return
	var duration_ms: int = int(clampf(relative_speed_m_s * 8.0, 8.0, 30.0))
	var amplitude: float = clampf(relative_speed_m_s / 3.0, 0.15, 1.0)
	Input.vibrate_handheld(duration_ms, amplitude)


## Crisp 12 ms tick for cork pops, valve clicks and similar.
static func tick() -> void:
	if OS.has_feature("android"):
		Input.vibrate_handheld(12, 0.6)
