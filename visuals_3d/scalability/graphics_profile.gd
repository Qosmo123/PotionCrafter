class_name GraphicsProfile
extends Node
## Runtime graphics presets for the PC Forward+ tier (the mobile tier is always LOW).
##
## ULTRA: SDFGI ray-marched global illumination, SSR, SSAO + SSIL, volumetric
##        fog light shafts, 8K PCSS soft shadows, FSR2 (4K output renders at
##        0.67 internal scale; below 4K FSR2 runs at 1.0 as temporal AA).
## HIGH:  SDFGI (3 cascades), SSR, SSAO, fog, 4K shadows.
## LOW:   shadows + glow only (mobile baseline).
## F5 cycles presets, F11 toggles fullscreen.
##
## Shadow budget: each shadowed omni light redraws the scene into a shadow map
## (6 faces as a cube, 2 as dual-paraboloid), so only the lights at the
## station you're looking at cast shadows. Below ULTRA they use dual-paraboloid
## maps and the sun uses 2 cascades instead of 4.

enum Preset { LOW, HIGH, ULTRA }

const PRESET_NAMES: PackedStringArray = ["LOW", "HIGH", "ULTRA"]

@export var world_environment: WorldEnvironment
@export var key_light: DirectionalLight3D
@export var preset: Preset = Preset.ULTRA

static var active_preset_name: String = "ULTRA"

## Omni lights that cast shadows in the scene as authored.
var _shadow_lights: Array[OmniLight3D] = []
var _station: int = -1


func _ready() -> void:
	if QualityTier.is_mobile_tier():
		preset = Preset.LOW
	get_viewport().size_changed.connect(_apply_upscaler)
	_collect_shadow_lights.call_deferred()
	apply()


func _collect_shadow_lights() -> void:
	var root: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	for n: Node in root.find_children("*", "OmniLight3D", true, false):
		var l: OmniLight3D = n as OmniLight3D
		if l.shadow_enabled:
			_shadow_lights.append(l)
	_station = -1


func _process(_delta: float) -> void:
	var s: int = LabCamera3D.instance.station if LabCamera3D.instance != null else 0
	if s != _station:
		_station = s
		_apply_light_shadows()


## Shadows only from the lights that light the current station.
func _apply_light_shadows() -> void:
	var center_x: float = 0.0
	if LabCamera3D.instance != null and _station >= 0 and _station < LabCamera3D.instance.station_offsets.size():
		center_x = LabCamera3D.instance.station_offsets[_station].x
	for l: OmniLight3D in _shadow_lights:
		if not is_instance_valid(l):
			continue
		l.shadow_enabled = absf(l.global_position.x - center_x) < 1.8
		l.omni_shadow_mode = OmniLight3D.SHADOW_CUBE if preset == Preset.ULTRA else OmniLight3D.SHADOW_DUAL_PARABOLOID


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F5 and not QualityTier.is_mobile_tier():
		preset = ((preset + 1) % PRESET_NAMES.size()) as Preset
		apply()
	elif key.keycode == KEY_F11:
		var fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func apply() -> void:
	active_preset_name = PRESET_NAMES[preset]
	var ultra: bool = preset == Preset.ULTRA
	var high: bool = preset >= Preset.HIGH
	if world_environment != null and world_environment.environment != null:
		var env: Environment = world_environment.environment
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.0
		env.glow_enabled = true
		env.glow_bloom = 0.06
		env.glow_hdr_threshold = 1.1
		env.glow_intensity = 0.9

		env.sdfgi_enabled = high
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4 if ultra else 3
		env.sdfgi_min_cell_size = 0.03
		env.sdfgi_energy = 1.0
		env.sdfgi_bounce_feedback = 0.6

		env.ssr_enabled = high
		env.ssr_max_steps = 96 if ultra else 48
		env.ssr_fade_in = 0.1
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.05

		env.ssao_enabled = high
		env.ssao_radius = 0.35
		env.ssao_intensity = 1.6
		env.ssil_enabled = ultra
		env.ssil_radius = 1.2
		env.ssil_intensity = 0.8

		env.volumetric_fog_enabled = high
		env.volumetric_fog_density = 0.035
		env.volumetric_fog_albedo = Color(0.95, 0.85, 0.72)
		env.volumetric_fog_anisotropy = 0.65
		env.volumetric_fog_length = 6.0
		env.volumetric_fog_ambient_inject = 0.15

	if key_light != null:
		key_light.shadow_enabled = true
		key_light.light_angular_distance = 1.2 if high else 0.0
		key_light.shadow_blur = 1.0
		key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if ultra else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		key_light.directional_shadow_max_distance = 6.0 if ultra else 4.0

	var shadow_quality: RenderingServer.ShadowQuality = (RenderingServer.SHADOW_QUALITY_SOFT_ULTRA if ultra
		else (RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW))
	RenderingServer.directional_shadow_atlas_set_size(8192 if ultra and DisplayServer.window_get_size().y >= 1400 else (4096 if high else 2048), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow_quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(shadow_quality)
	get_viewport().positional_shadow_atlas_size = 4096 if high else 2048
	get_viewport().use_debanding = true
	if not _shadow_lights.is_empty():
		_apply_light_shadows()
	_apply_upscaler()


func _apply_upscaler() -> void:
	var vp: Viewport = get_viewport()
	if QualityTier.is_mobile_tier() or preset == Preset.LOW:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = Viewport.MSAA_2X
		return
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	var height_px: float = float(DisplayServer.window_get_size().y)
	vp.scaling_3d_scale = 0.67 if (preset == Preset.ULTRA and height_px >= 2000.0) or (preset == Preset.HIGH and height_px >= 1400.0) else 1.0
