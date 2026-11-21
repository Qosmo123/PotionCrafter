class_name GemShowcase
extends CanvasLayer
## Cinematic hero shot for a finished gem or a special find. The stone is
## copied into a small jeweller's studio of its own (a separate 3D world with
## softbox reflections, a key/rim light rig, a velvet backdrop and drifting
## motes), shown full screen behind letterbox bars while the camera slowly
## dollies in and orbits and a title card names the piece. Click, Space or
## Esc moves on once the title is up. Only one plays at a time; others queue.

## Off for automated runs (scripts started with --script); tests that want it
## switch it back on.
static var enabled: bool = not OS.get_cmdline_args().has("--script")
static var current: GemShowcase = null
static var _queue: Array[Dictionary] = []

const SKY_SHADER: Shader = preload("res://visuals_3d/shaders/studio_sky.gdshader")
const BACKDROP_SHADER: Shader = preload("res://visuals_3d/shaders/showcase_backdrop.gdshader")
const SHOW_RADIUS_METERS: float = 0.05  # the copy is scaled to this size
const DURATION_S: float = 6.5
const SKIPPABLE_AFTER_S: float = 1.4
const FADE_S: float = 0.55

var _data: Dictionary = {}
var _t: float = 0.0
var _leaving: float = -1.0
var _viewport: SubViewport
var _view: TextureRect
var _flash: ColorRect
var _bars: Array[ColorRect] = []
var _card: VBoxContainer
var _hint: Label
var _cam: Camera3D
var _pivot: Node3D
var _sky_mat: ShaderMaterial
var _sparkle_light: OmniLight3D
var _rarity: int = 0


## Show `stone` in the studio. `kicker` is the small line above the name
## (e.g. "Faceted" or "Rare find!"), `subtitle` the details under it.
static func play(stone: Rock3D, kicker: String, title: String, subtitle: String, rarity: int = 2) -> void:
	if not enabled or stone == null or not is_instance_valid(stone) or not stone.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	var mesh_node: MeshInstance3D = stone._visual
	if mesh_node == null or mesh_node.mesh == null:
		return
	var data: Dictionary = {
		"mesh": mesh_node.mesh,
		"material": mesh_node.material_override,
		"scale": mesh_node.scale,
		"radius": maxf(stone.radius_meters(), 0.003),
		"color": stone.mineral.color if stone.mineral != null else Color.WHITE,
		"kicker": kicker, "title": title, "subtitle": subtitle, "rarity": rarity,
	}
	if current != null:
		_queue.append(data)
		return
	var show: GemShowcase = GemShowcase.new()
	show._data = data
	stone.get_tree().root.add_child(show)


static func is_playing() -> bool:
	return current != null


func _ready() -> void:
	current = self
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rarity = int(_data.get("rarity", 2))
	TactileGrabber3D.input_captured = true
	_build_stage()
	_build_overlay()
	AudioDirector.play_ui(&"whoosh", -8.0)
	AudioDirector.play_ui(&"discover", -4.0 if _rarity >= 3 else -7.0)


func _exit_tree() -> void:
	if current == self:
		current = null
		TactileGrabber3D.input_captured = ChalkDrawing3D.active
		if not _queue.is_empty():
			var next: Dictionary = _queue.pop_front()
			var show: GemShowcase = GemShowcase.new()
			show._data = next
			get_tree().root.add_child.call_deferred(show)


# --- Studio ------------------------------------------------------------------------

func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	_viewport.size = get_viewport().get_visible_rect().size
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var tint: Color = _data["color"]
	# Environment: studio sky for reflections, filmic grade, generous glow.
	var env: Environment = Environment.new()
	var sky: Sky = Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky_mat.set_shader_parameter(&"rim_color", Color(0.55, 0.75, 1.0).lerp(Color(tint, 1.0), 0.35))
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.12
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.9, 0.85, 1.0)
	env.volumetric_fog_ambient_inject = 0.0
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	# Camera with a shallow, macro-lens depth of field.
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_cam.h_offset = -0.055  # gem sits right of centre, clear of the title card
	_cam.near = 0.005
	_cam.far = 20.0
	var attrs: CameraAttributesPractical = CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 0.42
	attrs.dof_blur_far_transition = 0.5
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = 0.12
	attrs.dof_blur_near_transition = 0.08
	attrs.dof_blur_amount = 0.09
	_cam.attributes = attrs
	_viewport.add_child(_cam)
	_cam.current = true
	# Light rig: warm key, cool rim, a soft fill and a small glint light that
	# circles the stone so facets keep catching.
	var key: SpotLight3D = SpotLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 6.0
	key.spot_range = 3.0
	key.spot_angle = 22.0
	key.spot_angle_attenuation = 0.6
	key.shadow_enabled = true
	key.light_volumetric_fog_energy = 1.4
	_viewport.add_child(key)
	key.look_at_from_position(Vector3(-0.45, 0.7, 0.55), Vector3(0.0, 0.0, 0.0))
	var rim: SpotLight3D = SpotLight3D.new()
	rim.light_color = Color(0.6, 0.78, 1.0).lerp(Color(tint, 1.0), 0.4)
	rim.light_energy = 7.0
	rim.spot_range = 3.0
	rim.spot_angle = 18.0
	rim.light_volumetric_fog_energy = 2.0
	_viewport.add_child(rim)
	rim.look_at_from_position(Vector3(0.35, 0.45, -0.7), Vector3(0.0, 0.02, 0.0))
	var fill: OmniLight3D = OmniLight3D.new()
	fill.light_color = Color(0.85, 0.75, 1.0)
	fill.light_energy = 0.5
	fill.omni_range = 1.5
	fill.position = Vector3(0.4, 0.1, 0.5)
	_viewport.add_child(fill)
	_sparkle_light = OmniLight3D.new()
	_sparkle_light.light_color = Color(1.0, 0.97, 0.9)
	_sparkle_light.light_energy = 2.5
	_sparkle_light.omni_range = 0.4
	_viewport.add_child(_sparkle_light)
	# Velvet backdrop card and a dark pedestal with a brass ring.
	var back: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(3.2, 1.8)
	var back_mat: ShaderMaterial = ShaderMaterial.new()
	back_mat.shader = BACKDROP_SHADER
	back_mat.set_shader_parameter(&"tint", tint)
	back_mat.set_shader_parameter(&"strength", 1.0 + 0.25 * float(_rarity))
	quad.material = back_mat
	back.mesh = quad
	back.position = Vector3(0.0, 0.15, -0.9)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewport.add_child(back)
	var plinth: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.075
	cyl.bottom_radius = 0.085
	cyl.height = 0.04
	cyl.radial_segments = 96
	var velvet: StandardMaterial3D = StandardMaterial3D.new()
	velvet.albedo_color = Color(0.035, 0.015, 0.045)
	velvet.roughness = 1.0
	velvet.rim_enabled = true
	velvet.rim = 0.35
	velvet.rim_tint = 0.8
	velvet.metallic_specular = 0.1
	cyl.material = velvet
	plinth.mesh = cyl
	plinth.position = Vector3(0.0, -SHOW_RADIUS_METERS - 0.03, 0.0)
	_viewport.add_child(plinth)
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.074
	torus.outer_radius = 0.08
	torus.rings = 96
	torus.ring_segments = 12
	var brass: StandardMaterial3D = StandardMaterial3D.new()
	brass.albedo_color = Color(0.83, 0.62, 0.3)
	brass.metallic = 1.0
	brass.roughness = 0.22
	torus.material = brass
	ring.mesh = torus
	ring.position = plinth.position + Vector3(0.0, 0.02, 0.0)
	_viewport.add_child(ring)
	# The stone itself, scaled up to fill the frame, turning slowly.
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	var copy: MeshInstance3D = MeshInstance3D.new()
	copy.mesh = _data["mesh"]
	copy.material_override = _data["material"]
	copy.scale = (_data["scale"] as Vector3) * (SHOW_RADIUS_METERS / float(_data["radius"]))
	_pivot.add_child(copy)
	_pivot.rotation = Vector3(0.35, 0.0, 0.12)
	# Motes of light in the stone's colour drifting up past it.
	var motes: GPUParticles3D = GPUParticles3D.new()
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.22
	pm.gravity = Vector3(0.0, 0.012, 0.0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.01
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.3, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var fade_tex: GradientTexture1D = GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	motes.process_material = pm
	motes.amount = 28 + 12 * _rarity
	motes.lifetime = 4.0
	motes.preprocess = 4.0
	var dot: QuadMesh = QuadMesh.new()
	dot.size = Vector2(0.0018, 0.0018)
	dot.material = VesselEffects.billboard_material(true, 3.0, Color(tint, 1.0).lerp(Color(1.0, 0.9, 0.7), 0.5))
	motes.draw_pass_1 = dot
	_viewport.add_child(motes)


# --- Overlay -----------------------------------------------------------------------

func _build_overlay() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_gui_input)
	add_child(root)
	_view = TextureRect.new()
	_view.texture = _viewport.get_texture()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.modulate.a = 0.0
	root.add_child(_view)
	for top: bool in [true, false]:
		var bar: ColorRect = ColorRect.new()
		bar.color = Color(0.0, 0.0, 0.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.anchor_bottom = 0.0
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
		root.add_child(bar)
		_bars.append(bar)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 0.95, 0.85, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	# Title card, lower left, in the display face.
	_card = VBoxContainer.new()
	_card.anchor_left = 0.07
	_card.anchor_top = 0.62
	_card.anchor_right = 0.6
	_card.anchor_bottom = 0.86
	_card.add_theme_constant_override(&"separation", 2)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	root.add_child(_card)
	var aura: Color = MineralData.RARITY_COLORS[clampi(_rarity, 0, 4)]
	var kicker: Label = CosmicTheme.label(String(_data["kicker"]).to_upper(), 18, aura, CosmicTheme.mono_font())
	_card.add_child(kicker)
	var name_label: Label = CosmicTheme.label(String(_data["title"]), 54, Color(0.98, 0.94, 0.86), CosmicTheme.display_font())
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(name_label)
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(CosmicTheme.STARLIGHT_GOLD, 0.8)
	rule.custom_minimum_size = Vector2(220, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_card.add_child(rule)
	var sub: Label = CosmicTheme.label(String(_data["subtitle"]), 20, Color(0.86, 0.82, 0.92))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(sub)
	_hint = CosmicTheme.label("click to continue", 15, Color(0.8, 0.76, 0.9, 0.0))
	_hint.anchor_left = 0.8
	_hint.anchor_right = 0.97
	_hint.anchor_top = 0.93
	_hint.anchor_bottom = 0.97
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_hint)


func _on_gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_skip()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ESCAPE, KEY_ENTER]:
		_skip()
		get_viewport().set_input_as_handled()


func _skip() -> void:
	if _t >= SKIPPABLE_AFTER_S and _leaving < 0.0:
		_leaving = 0.0


# --- Timeline ----------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION_S and _leaving < 0.0:
		_leaving = 0.0
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if Vector2(_viewport.size) != vp_size:
		_viewport.size = vp_size
	# Fade in, with a bright flash for the rarest pieces.
	var fade_in: float = smoothstep(0.0, FADE_S, _t)
	var out: float = 1.0
	if _leaving >= 0.0:
		_leaving += delta
		out = 1.0 - smoothstep(0.0, FADE_S, _leaving)
		if _leaving >= FADE_S:
			queue_free()
			return
	_view.modulate.a = fade_in * out
	if _rarity >= 4:
		_flash.color.a = maxf(0.0, 0.7 - _t * 1.6) * out
	var bar_h: float = vp_size.y * 0.11 * smoothstep(0.0, 0.6, _t) * out
	_bars[0].offset_bottom = bar_h
	_bars[1].offset_top = -bar_h
	_card.modulate.a = smoothstep(0.9, 1.6, _t) * out
	_card.position.x = lerpf(-30.0, 0.0, smoothstep(0.9, 1.8, _t)) + _card.get_parent_area_size().x * _card.anchor_left
	_hint.modulate.a = smoothstep(SKIPPABLE_AFTER_S, SKIPPABLE_AFTER_S + 0.6, _t) * 0.8 * out
	# Camera: a slow dolly in and a quarter orbit, looking slightly down.
	var k: float = clampf(_t / DURATION_S, 0.0, 1.0)
	var ease_k: float = 1.0 - pow(1.0 - k, 2.2)
	var orbit: float = lerpf(-0.55, 0.35, ease_k)
	var dist: float = lerpf(0.55, 0.34, ease_k)
	var height: float = lerpf(0.13, 0.06, ease_k)
	_cam.position = Vector3(sin(orbit) * dist, height, cos(orbit) * dist)
	_cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	(_cam.attributes as CameraAttributesPractical).dof_blur_far_distance = dist + 0.08
	(_cam.attributes as CameraAttributesPractical).dof_blur_near_distance = dist - 0.1
	# The stone turns and bobs; the softboxes drift so facets flash.
	_pivot.rotate_y(delta * 0.55)
	_pivot.position.y = 0.006 * sin(_t * 1.3)
	_sky_mat.set_shader_parameter(&"turn", _t * 0.25)
	_sparkle_light.position = Vector3(cos(_t * 1.7) * 0.12, 0.08 + 0.03 * sin(_t * 2.3), sin(_t * 1.7) * 0.12)
