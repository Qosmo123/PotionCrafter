class_name SimConstants
extends RefCounted
## Global simulation constants, physics layer bitmasks, and safety clamps.
## Pure static class: reference as `SimConstants.X` from anywhere (no autoload needed,
## so it also works in headless `--script` tools and tests).

# --- Fixed tick -------------------------------------------------------------
const TICK_SECONDS: float = 1.0 / 60.0

# --- Conservation & safety ---------------------------------------------------
const CONSERVATION_EPSILON: float = 1e-5
const MIN_TEMP_KELVIN: float = 0.1
const MAX_TEMP_KELVIN: float = 10000.0
const AMBIENT_TEMP_KELVIN: float = 293.15
const AMBIENT_PRESSURE_KPA: float = 101.325

# --- Physical constants ------------------------------------------------------
const GAS_CONSTANT_J_MOL_K: float = 8.314462618
const GRAVITY_M_S2: float = 9.80665

# --- Jolt collision layer bitmasks (match project.godot layer_names) ---------
const LAYER_STATIC_BENCH: int = 1 << 0
const LAYER_RIGID_VESSEL: int = 1 << 1
const LAYER_SOLID_REAGENT: int = 1 << 2
const LAYER_TACTILE_TOOL: int = 1 << 3
const LAYER_POUR_STREAM_RAY: int = 1 << 4
const LAYER_TERRARIUM_ENTITY: int = 1 << 5
const LAYER_SNAP_SOCKET: int = 1 << 6


## Clamp a temperature into the safe simulation range, scrubbing NaN/Inf.
static func sanitize_temp_kelvin(temp_kelvin: float) -> float:
	if is_nan(temp_kelvin):
		return AMBIENT_TEMP_KELVIN
	if is_inf(temp_kelvin):
		return MAX_TEMP_KELVIN if temp_kelvin > 0.0 else MIN_TEMP_KELVIN
	return clampf(temp_kelvin, MIN_TEMP_KELVIN, MAX_TEMP_KELVIN)
